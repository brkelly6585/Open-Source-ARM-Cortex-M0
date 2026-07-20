`timescale 1ns / 1ps
// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2025-2026 Dylan Thornburg and Bryce Kelly
//
// This file is part of the Open-Source ARM Cortex-M0 project.
// Licensed under the GNU General Public License v3.0 or later.
// See the LICENSE file at the root of this repository.

// Load/store sequencer.
//
// Design rule:
//   Once an access is accepted in IDLE, every field used by that access is
//   held in a register until the access completes.  In particular, a
//   multi-register store never drives the bus from the live Register_File
//   output while curr_reg is changing.
//
// The external AHB arbitration layer treats a request presented while ready_i
// is high as the next back-to-back transaction.  Therefore normal AHB requests
// are deasserted during the ready_i completion cycle.  PPB/SCS accesses are
// local one-cycle accesses; they keep their local request asserted even though
// ready_i is high, while core.v prevents them from reaching AHB.
module Data_Memory (
    input clk,
    input rst_n,

    input [31:0] base_addr_i,
    input [31:0] store_data_i,
    input [3:0]  Rd_i,
    input [1:0]  size_i,
    input        sign_i,
    input        load_i,
    input        store_i,
    input        valid_i,

    input [1:0]  type_i,
    input [8:0]  reg_list_i,

    input [31:0] rdata_i,
    input        ready_i,

    output reg [31:0] addr_o,
    output reg [31:0] wdata_o,
    output reg        read_req_o,
    output reg        write_req_o,
    output reg [1:0]  size_o,

    output reg [31:0] load_data_o,
    output reg [3:0]  Rd_o,
    output reg [3:0]  curr_reg,
    output reg        wb_valid_o,
    output reg        stall_o,
    output reg        exc_o,
    output reg        sp_we_o,
    output reg [31:0] sp_data_o,
    output [3:0]      base_reg_o,
    input             abort_i,       // exception entry: drop any in-flight access
    input             grant_i        // arbiter is issuing addr_o as an AHB ADDRESS phase this cycle
);

    localparam [3:0]
        IDLE          = 4'd0,
        SINGLE_REQ    = 4'd1,
        SINGLE_RESP   = 4'd2,
        MULTI_START   = 4'd3,
        MULTI_PREP    = 4'd4,
        MULTI_REQ     = 4'd5,
        MULTI_RESP    = 4'd6,
        MULTI_ADVANCE = 4'd7,
        ML_STREAM     = 4'd8,   // pipelined load: 1 register per ready cycle
        MS_STREAM     = 4'd9;   // pipelined store: 1 register per ready cycle

    reg [3:0] curr_state;
    reg [3:0] next_state;

    // Transaction fields.  No request state uses live EX/Register_File data.
    reg [31:0] base_addr_r;
    reg [31:0] store_data_r;
    reg [31:0] resp_data_r;
    reg [3:0]  resp_rd_r;
    reg [3:0]  Rd_r;
    reg [1:0]  size_r;
    reg        sign_r;
    reg        load_r;
    reg        local_r;

    // Multi-register transfer state.
    reg [8:0] reg_mask_r;
    reg       multi_load_r;
    reg       stack_r;
    reg       suppress_wb_r;   // LDM with base in list -> no base writeback
    reg       dec_r;
    reg       inc_r;
    reg [3:0] curr_reg_r;
    // Pipelined-load bookkeeping. next_reg_r is the register selected one step ahead,
    // so its address can be driven while the current register's data returns. The
    // *_pend regs describe the writeback owed for the register whose data arrives THIS
    // cycle. is_last_r / last_pend_r are registered so the ready-cycle next-state
    // decision never races a same-cycle mask update (the CoreMark-breaking hazard).
    reg [3:0] next_reg_r;      // register whose ADDRESS phase is being driven now
    reg [8:0] load_mask_r;     // remaining registers not yet address-phased
    reg       is_last_r;       // next_reg_r is the final register (its addr is last)
    reg       have_pend_r;     // a load writeback is owed this stream cycle
    reg [3:0] pend_rd_r;       // destination for the owed writeback
    reg       last_pend_r;     // the owed writeback is for the final register
    reg       addr_done_r;     // every list register has had its address phase issued
    // Store-stream pipeline.
    reg [31:0] str_addr_r;     // address of the store beat currently on the bus
    reg       str_go_r;        // a store beat is being driven this cycle
    reg       str_last_r;      // the current store beat is the final register
    reg       str_prime_r;     // priming cycle: settle the first register's read
    reg [3:0] str_next_reg_r;  // register to prefetch (drives curr_reg output)

    // Architectural register represented by the currently selected list bit.
    // PUSH bit 8 is LR; POP bit 8 is PC.
    wire [3:0] cur_mapped = (curr_reg_r == 4'd8) ?
                            (multi_load_r ? 4'd15 : 4'd14) : curr_reg_r;

    wire [8:0] mask_after_current =
        reg_mask_r & ~(9'b000000001 << curr_reg_r);
    wire multi_last = (mask_after_current == 9'b0);
    // Mask remaining after the store-stream's prefetch register is consumed.
    wire [8:0] mask_after_next = reg_mask_r & ~(9'b1 << str_next_reg_r);
    // First store register for an incoming multi-store (combinational), used to settle
    // the register-file read during the accept cycle so no prime cycle is needed.
    wire [3:0] first_store_reg = select_list_reg(reg_list_i, (type_i == 2'b10));

    // Stream advance strobe. AHB streams advance one register per ADDRESS phase
    // (grant_i); the data phase completes one transfer later on its own. Local PPB
    // accesses never reach the arbiter, so they keep the one-cycle ready handshake.
    wire s_adv = local_r ? ready_i : grant_i;

    // Final retire cycle of a pipelined load: the last register's data is live on
    // rdata_i. The stream is complete; the stall is released here exactly as in
    // SINGLE_REQ's ready cycle, and a back-to-back memory instruction is accepted
    // here for the same reason (routing it through IDLE would lose it). A POP that
    // retires PC is excluded: it redirects the front end, so the instruction in EX
    // is wrong-path and must not be accepted, and the stall holds one more cycle.
    wire ml_last_ret  = (curr_state == ML_STREAM) && ready_i && have_pend_r && last_pend_r;
    wire ml_ret_to_pc = (pend_rd_r == 4'd15);

    // Every cycle in which a new transfer descriptor can be captured. Settling the
    // first store register's read (curr_reg override below) must happen in ALL of
    // them: covering only IDLE let a multi-store accepted in SINGLE_REQ's ready
    // cycle latch a stale register's word as its first beat (observed: back-to-back
    // LDR -> PUSH {r2,r3} stored r2's value in both stack slots).
    wire accept_win = (curr_state == IDLE)
                   || ((curr_state == SINGLE_REQ) && ready_i)
                   || (ml_last_ret && !ml_ret_to_pc);
    wire       accepting_mstore = accept_win && valid_i && store_i
                                   && (type_i != 2'b00) && (reg_list_i != 9'b0);

    // Select lowest listed register for incrementing transfers (LDMIA/POP/STMIA)
    // and highest listed register for decrementing PUSH.  The latter lets the
    // sequencer pre-decrement once per stored register while producing the
    // architecturally required final memory order.
    function [3:0] select_list_reg;
        input [8:0] mask;
        input       descending;
        integer k;
        begin
            select_list_reg = 4'd0;
            if (descending) begin
                for (k = 0; k < 9; k = k + 1)
                    if (mask[k]) select_list_reg = k;
            end else begin
                for (k = 8; k >= 0; k = k - 1)
                    if (mask[k]) select_list_reg = k;
            end
        end
    endfunction

    function [31:0] extend_load;
        input [31:0] data;
        input [1:0]  size;
        input        sign;
        begin
            if (!sign) begin
                extend_load = data;
            end else begin
                case (size)
                    2'b00: extend_load = {{24{data[7]}},  data[7:0]};
                    2'b01: extend_load = {{16{data[15]}}, data[15:0]};
                    default: extend_load = data;
                endcase
            end
        end
    endfunction

    // State register.
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            curr_state <= IDLE;
        else if (abort_i)
            curr_state <= IDLE;          // abort in-flight access on exception entry
        else
            curr_state <= next_state;
    end

    // State transitions.  A response state gives a load exactly one stable
    // writeback point.  MULTI_ADVANCE is bookkeeping only: no bus request and
    // no duplicate load writeback are emitted there.
    always @(*) begin
        next_state = curr_state;

        case (curr_state)
            IDLE: begin
                if (valid_i && (load_i || store_i)) begin
                    if (type_i == 2'b00)
                        next_state = SINGLE_REQ;
                    else if (reg_list_i != 9'b0)
                        next_state = (load_i) ? ML_STREAM : MS_STREAM;
                end
            end

            SINGLE_REQ: begin
                // The load data is live on rdata_i in the ready cycle, so the writeback
                // is issued there; SINGLE_RESP was an entire extra STALLED cycle spent
                // only to replay a value we already had.
                //
                // The stall is ALSO released in this cycle (see stall_o), so IDEX
                // advances on the following negedge and a new instruction is in EX by
                // the time this block is next sampled. If that instruction is a memory
                // access it must be accepted HERE -- routing it through IDLE would let
                // it slip past before IDLE could latch it. Handle BOTH forms: a single
                // access, and a multi (LDM/STM/PUSH/POP). Missing the multi case is
                // what hung CoreMark on the earlier attempt.
                if (ready_i) begin
                    if (valid_i && (load_i || store_i)) begin
                        if (type_i == 2'b00)
                            next_state = SINGLE_REQ;          // back-to-back single
                        else if (reg_list_i != 9'b0)
                            next_state = (load_i) ? ML_STREAM : MS_STREAM;  // back-to-back multi
                        else
                            next_state = IDLE;
                    end else begin
                        next_state = IDLE;
                    end
                end
            end

            SINGLE_RESP:
                next_state = IDLE;

            MULTI_START:
                next_state = MULTI_PREP;

            MULTI_PREP:
                next_state = MULTI_REQ;

            MULTI_REQ: begin
                if (ready_i)
                    next_state = multi_load_r ? MULTI_RESP : MULTI_ADVANCE;
            end

            MULTI_RESP:
                next_state = MULTI_ADVANCE;

            MULTI_ADVANCE:
                next_state = multi_last ? IDLE : MULTI_PREP;

            // Pipelined load. Each ready cycle drives one address phase and retires one
            // data phase. Leave when the final register's data has been retired, which
            // is signalled by last_pend_r (registered, so this decision never races the
            // same-cycle mask update).
            ML_STREAM: begin
                if (ml_last_ret) begin
                    // The stall is released in this cycle (see stall_o), so the next
                    // instruction is already in EX and must be accepted HERE, exactly
                    // as in SINGLE_REQ's ready cycle. Not when PC was just retired:
                    // the redirect makes the EX instruction wrong-path.
                    if (!ml_ret_to_pc && valid_i && (load_i || store_i)) begin
                        if (type_i == 2'b00)
                            next_state = SINGLE_REQ;
                        else if (reg_list_i != 9'b0)
                            next_state = (load_i) ? ML_STREAM : MS_STREAM;
                        else
                            next_state = IDLE;
                    end else begin
                        next_state = IDLE;
                    end
                end
            end

            MS_STREAM: begin
                // Leave when the final ADDRESS phase is issued; the last data phase
                // completes on the bus by itself, overlapping the next instruction.
                if (str_go_r && s_adv && str_last_r)
                    next_state = IDLE;
            end

            default:
                next_state = IDLE;
        endcase
    end

    // Transaction-state updates.
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            base_addr_r  <= 32'd0;
            store_data_r <= 32'd0;
            resp_data_r  <= 32'd0;
            resp_rd_r    <= 4'd0;
            Rd_r         <= 4'd0;
            size_r       <= 2'd0;
            sign_r       <= 1'b0;
            load_r       <= 1'b0;
            local_r      <= 1'b0;

            reg_mask_r   <= 9'd0;
            multi_load_r <= 1'b0;
            stack_r      <= 1'b0;
            suppress_wb_r<= 1'b0;
            dec_r        <= 1'b0;
            inc_r        <= 1'b0;
            curr_reg_r   <= 4'd0;
            next_reg_r   <= 4'd0;
            load_mask_r  <= 9'd0;
            is_last_r    <= 1'b0;
            have_pend_r  <= 1'b0;
            pend_rd_r    <= 4'd0;
            last_pend_r  <= 1'b0;
            addr_done_r  <= 1'b0;
            str_addr_r   <= 32'd0;
            str_go_r     <= 1'b0;
            str_last_r   <= 1'b0;
            str_prime_r  <= 1'b0;
            str_next_reg_r <= 4'd0;
        end else begin
            case (curr_state)
                IDLE: begin
                    if (valid_i && (load_i || store_i)) begin
                        // Capture the entire single-transfer descriptor now.
                        // Later pipeline activity cannot alter this transfer.
                        base_addr_r  <= base_addr_i;
                        store_data_r <= store_data_i;
                        Rd_r         <= Rd_i;
                        size_r       <= size_i;
                        sign_r       <= sign_i;
                        load_r       <= load_i;
                        local_r      <= (base_addr_i[31:12] == 20'hE000E);

                        if (type_i != 2'b00) begin
                            reg_mask_r   <= reg_list_i;
                            multi_load_r <= load_i;
                            stack_r      <= (type_i == 2'b10);
                            suppress_wb_r<= (type_i == 2'b01) && load_i && (Rd_i <= 4'd7) && reg_list_i[Rd_i[2:0]];
                            dec_r        <= (type_i == 2'b10) && store_i;
                            inc_r        <= (type_i == 2'b01) ||
                                            ((type_i == 2'b10) && load_i);
                            curr_reg_r   <= select_list_reg(
                                                reg_list_i,
                                                (type_i == 2'b10) && store_i
                                            );
                            // Pipelined-load setup: address-phase the first (lowest)
                            // register next cycle; stage the rest.
                            if (load_i) begin
                                next_reg_r  <= select_list_reg(reg_list_i, 1'b0);
                                load_mask_r <= reg_list_i & ~(9'b1 << select_list_reg(reg_list_i, 1'b0));
                                is_last_r   <= (reg_list_i & ~(9'b1 << select_list_reg(reg_list_i, 1'b0))) == 9'b0;
                                have_pend_r <= 1'b0;
                                addr_done_r <= 1'b0;
                            end
                            // Pipelined-store setup. curr_reg was driven combinationally
                            // to the first register during THIS accept cycle, so
                            // store_data_i is already settled -- latch it now and enter
                            // MS_STREAM directly at the first beat (no prime cycle).
                            if (store_i) begin
                                str_prime_r  <= 1'b0;
                                str_go_r     <= 1'b1;
                                store_data_r <= store_data_i;      // first register's word
                                curr_reg_r   <= first_store_reg;   // "current beat" reg
                                // First beat address from the incoming base: PUSH
                                // (type 10) pre-decrements once; STMIA (type 01) uses
                                // the base as-is. base_addr_r is also loaded from
                                // base_addr_i this same cycle.
                                str_addr_r   <= (type_i == 2'b10) ? (base_addr_i - 32'd4)
                                                                  : base_addr_i;
                                // Align base_addr_r with the first beat so the stream's
                                // first advance is correct: PUSH decrements, so base
                                // must start at the first (highest) written address;
                                // STMIA keeps base_addr_i (increments per beat).
                                if (type_i == 2'b10)
                                    base_addr_r <= base_addr_i - 32'd4;
                                // Prefetch pointer -> second register.
                                str_next_reg_r <= select_list_reg(
                                                    reg_list_i & ~(9'b1 << first_store_reg),
                                                    (type_i == 2'b10));
                                str_last_r   <= (reg_list_i & ~(9'b1 << first_store_reg)) == 9'b0;
                                reg_mask_r   <= reg_list_i & ~(9'b1 << first_store_reg);
                            end
                        end
                    end
                end

                // PUSH is STMDB SP!,<list>.  Choose highest register first,
                // then pre-decrement before each write.
                MULTI_START: begin
                    if (stack_r && dec_r)
                        base_addr_r <= base_addr_r - 32'd4;
                end

                // curr_reg_r is stable for this entire state.  Capture the
                // selected source word before starting the store transfer.
                MULTI_PREP: begin
                    if (!multi_load_r)
                        store_data_r <= store_data_i;
                end

                // Capture a returned load word and its destination only once.
                // The response state presents these registered values to WB.
                MULTI_REQ: begin
                    if (ready_i) begin
                        if (multi_load_r) begin
                            resp_data_r <= rdata_i;
                            resp_rd_r   <= cur_mapped;
                        end

                        // LDMIA/STMIA and POP advance after every completed
                        // transfer, including the final one.
                        if (inc_r)
                            base_addr_r <= base_addr_r + 32'd4;
                    end
                end

                SINGLE_REQ: begin
                    if (ready_i && load_r) begin
                        resp_data_r <= rdata_i;
                        resp_rd_r   <= Rd_r;
                    end

                    // Accept the next transfer in the ready cycle. Identical to the
                    // IDLE capture below, so nothing can be lost to the released stall.
                    if (ready_i && valid_i && (load_i || store_i)) begin
                        base_addr_r  <= base_addr_i;
                        store_data_r <= store_data_i;
                        Rd_r         <= Rd_i;
                        size_r       <= size_i;
                        sign_r       <= sign_i;
                        load_r       <= load_i;
                        local_r      <= (base_addr_i[31:12] == 20'hE000E);

                        if (type_i != 2'b00) begin
                            reg_mask_r   <= reg_list_i;
                            multi_load_r <= load_i;
                            stack_r      <= (type_i == 2'b10);
                            suppress_wb_r<= (type_i == 2'b01) && load_i && (Rd_i <= 4'd7) && reg_list_i[Rd_i[2:0]];
                            dec_r        <= (type_i == 2'b10) && store_i;
                            inc_r        <= (type_i == 2'b01) ||
                                            ((type_i == 2'b10) && load_i);
                            curr_reg_r   <= select_list_reg(
                                                reg_list_i,
                                                (type_i == 2'b10) && store_i
                                            );
                            // Pipelined-load setup: address-phase the first (lowest)
                            // register next cycle; stage the rest.
                            if (load_i) begin
                                next_reg_r  <= select_list_reg(reg_list_i, 1'b0);
                                load_mask_r <= reg_list_i & ~(9'b1 << select_list_reg(reg_list_i, 1'b0));
                                is_last_r   <= (reg_list_i & ~(9'b1 << select_list_reg(reg_list_i, 1'b0))) == 9'b0;
                                have_pend_r <= 1'b0;
                                addr_done_r <= 1'b0;
                            end
                            // Pipelined-store setup. curr_reg was driven combinationally
                            // to the first register during THIS accept cycle, so
                            // store_data_i is already settled -- latch it now and enter
                            // MS_STREAM directly at the first beat (no prime cycle).
                            if (store_i) begin
                                str_prime_r  <= 1'b0;
                                str_go_r     <= 1'b1;
                                store_data_r <= store_data_i;      // first register's word
                                curr_reg_r   <= first_store_reg;   // "current beat" reg
                                // First beat address from the incoming base: PUSH
                                // (type 10) pre-decrements once; STMIA (type 01) uses
                                // the base as-is. base_addr_r is also loaded from
                                // base_addr_i this same cycle.
                                str_addr_r   <= (type_i == 2'b10) ? (base_addr_i - 32'd4)
                                                                  : base_addr_i;
                                // Align base_addr_r with the first beat so the stream's
                                // first advance is correct: PUSH decrements, so base
                                // must start at the first (highest) written address;
                                // STMIA keeps base_addr_i (increments per beat).
                                if (type_i == 2'b10)
                                    base_addr_r <= base_addr_i - 32'd4;
                                // Prefetch pointer -> second register.
                                str_next_reg_r <= select_list_reg(
                                                    reg_list_i & ~(9'b1 << first_store_reg),
                                                    (type_i == 2'b10));
                                str_last_r   <= (reg_list_i & ~(9'b1 << first_store_reg)) == 9'b0;
                                reg_mask_r   <= reg_list_i & ~(9'b1 << first_store_reg);
                            end
                        end
                    end
                end

                // Pipelined store. Prime settles the first register's read; then each
                // ready cycle drives one store beat and prefetches the next register's
                // data by pointing the register-file read (curr_reg output) one ahead.
                MS_STREAM: begin
                    if (str_prime_r) begin
                        // First register's data has settled on store_data_i.
                        store_data_r <= store_data_i;
                        // First beat address: PUSH pre-decrements once (already done in
                        // base_addr_r via... no: compute here). STMIA uses base as-is.
                        if (dec_r) begin
                            str_addr_r  <= base_addr_r - 32'd4;
                            base_addr_r <= base_addr_r - 32'd4;
                        end else begin
                            str_addr_r <= base_addr_r;
                        end
                        str_last_r  <= (mask_after_next == 9'b0);
                        // Advance the prefetch pointer to the second register.
                        curr_reg_r  <= str_next_reg_r;   // now the "current" beat reg
                        str_next_reg_r <= select_list_reg(mask_after_next, dec_r);
                        reg_mask_r  <= mask_after_next;
                        str_prime_r <= 1'b0;
                        str_go_r    <= 1'b1;
                    end else if (str_go_r && s_adv) begin
                        // Current beat accepted. Prefetch next register's data (curr_reg
                        // output already points at str_next_reg_r this cycle).
                        store_data_r <= store_data_i;

                        // STMIA advances base after EVERY beat, including the last, so
                        // the base writeback is start + 4*N. (PUSH's base already points
                        // at the final/lowest written address, so it is not advanced on
                        // the last beat.)
                        if (inc_r)
                            base_addr_r <= base_addr_r + 32'd4;

                        if (str_last_r) begin
                            // Final address phase issued. ahb_main has latched the last
                            // wdata at this acceptance; drop the stream next cycle.
                            str_go_r <= 1'b0;
                        end else begin
                            // Prepare next beat address.
                            if (dec_r) begin
                                str_addr_r  <= base_addr_r - 32'd4;
                                base_addr_r <= base_addr_r - 32'd4;
                            end else begin
                                str_addr_r  <= base_addr_r + 32'd4;
                            end
                            curr_reg_r     <= str_next_reg_r;
                            str_last_r     <= (mask_after_next == 9'b0);
                            str_next_reg_r <= select_list_reg(mask_after_next, dec_r);
                            reg_mask_r     <= mask_after_next;
                        end
                    end
                end

                // Pipelined load. On each accepted transfer (ready_i):
                //  - the register we address-phased LAST cycle now has its data on
                //    rdata_i -> retire it (writeback happens in the combinational block
                //    using pend_rd_r + rdata_i);
                //  - address-phase next_reg_r THIS cycle (combinational block drives its
                //    address and read_req); record that a writeback for it is now owed;
                //  - advance the staged register and base.
                ML_STREAM: begin
                    // Address side: one register per ADDRESS phase (s_adv), matching
                    // the bus pipeline. Advancing on ready_i (the DATA phase, one
                    // transfer later) re-issued the first address of every stream.
                    if (s_adv && !addr_done_r) begin
                        // Record the writeback owed for the register whose address is
                        // being driven THIS cycle (its data returns with the next
                        // completed transfer).
                        have_pend_r <= 1'b1;
                        pend_rd_r   <= (next_reg_r == 4'd8) ? 4'd15 : next_reg_r;
                        last_pend_r <= is_last_r;

                        // POP/LDM always increments the base after each element.
                        base_addr_r <= base_addr_r + 32'd4;

                        // Advance to the next staged register.
                        if (is_last_r) begin
                            addr_done_r <= 1'b1;   // stop driving read requests
                        end else begin
                            next_reg_r  <= select_list_reg(load_mask_r, 1'b0);
                            load_mask_r <= load_mask_r & ~(9'b1 << select_list_reg(load_mask_r, 1'b0));
                            is_last_r   <= (load_mask_r & ~(9'b1 << select_list_reg(load_mask_r, 1'b0))) == 9'b0;
                        end
                    end else if (ready_i && have_pend_r) begin
                        // Data phase retired with no new address granted this cycle
                        // (only the final element, or a wait-state gap): nothing is
                        // outstanding any more.
                        have_pend_r <= 1'b0;
                    end

                    // Back-to-back accept in the final retire cycle. Identical to the
                    // SINGLE_REQ ready-cycle capture: the stall is released this cycle
                    // (see stall_o), so the instruction now in EX would be lost if it
                    // were routed through IDLE. Never after a PC retire (wrong-path).
                    if (ml_last_ret && !ml_ret_to_pc && valid_i && (load_i || store_i)) begin
                        base_addr_r  <= base_addr_i;
                        store_data_r <= store_data_i;
                        Rd_r         <= Rd_i;
                        size_r       <= size_i;
                        sign_r       <= sign_i;
                        load_r       <= load_i;
                        local_r      <= (base_addr_i[31:12] == 20'hE000E);

                        if (type_i != 2'b00) begin
                            reg_mask_r   <= reg_list_i;
                            multi_load_r <= load_i;
                            stack_r      <= (type_i == 2'b10);
                            suppress_wb_r<= (type_i == 2'b01) && load_i && (Rd_i <= 4'd7) && reg_list_i[Rd_i[2:0]];
                            dec_r        <= (type_i == 2'b10) && store_i;
                            inc_r        <= (type_i == 2'b01) ||
                                            ((type_i == 2'b10) && load_i);
                            curr_reg_r   <= select_list_reg(
                                                reg_list_i,
                                                (type_i == 2'b10) && store_i
                                            );
                            // Pipelined-load setup: address-phase the first (lowest)
                            // register next cycle; stage the rest.
                            if (load_i) begin
                                next_reg_r  <= select_list_reg(reg_list_i, 1'b0);
                                load_mask_r <= reg_list_i & ~(9'b1 << select_list_reg(reg_list_i, 1'b0));
                                is_last_r   <= (reg_list_i & ~(9'b1 << select_list_reg(reg_list_i, 1'b0))) == 9'b0;
                                have_pend_r <= 1'b0;
                                addr_done_r <= 1'b0;
                            end
                            // Pipelined-store setup. curr_reg is driven combinationally
                            // to the first register during THIS accept cycle (see
                            // accept_win), so store_data_i is already settled.
                            if (store_i) begin
                                str_prime_r  <= 1'b0;
                                str_go_r     <= 1'b1;
                                store_data_r <= store_data_i;      // first register's word
                                curr_reg_r   <= first_store_reg;   // "current beat" reg
                                str_addr_r   <= (type_i == 2'b10) ? (base_addr_i - 32'd4)
                                                                  : base_addr_i;
                                if (type_i == 2'b10)
                                    base_addr_r <= base_addr_i - 32'd4;
                                // Prefetch pointer -> second register.
                                str_next_reg_r <= select_list_reg(
                                                    reg_list_i & ~(9'b1 << first_store_reg),
                                                    (type_i == 2'b10));
                                str_last_r   <= (reg_list_i & ~(9'b1 << first_store_reg)) == 9'b0;
                                reg_mask_r   <= reg_list_i & ~(9'b1 << first_store_reg);
                            end
                        end
                    end
                end

                // Clear the transfer just completed, select the next list
                // member, and prepare its address.  This state never touches
                // the external memory request signals.
                MULTI_ADVANCE: begin
                    reg_mask_r <= mask_after_current;

                    if (!multi_last) begin
                        curr_reg_r <= select_list_reg(mask_after_current, dec_r);
                        if (dec_r)
                            base_addr_r <= base_addr_r - 32'd4;
                    end
                end

                default: ;
            endcase
        end
    end

    always @(*) begin
        // Safe defaults.
        addr_o      = 32'd0;
        wdata_o     = 32'd0;
        read_req_o  = 1'b0;
        write_req_o = 1'b0;
        size_o      = 2'b10;

        load_data_o = 32'd0;
        Rd_o        = 4'd0;
        curr_reg    = cur_mapped;
        // Settle the first store register's read during the accept cycle. This lets the
        // accept edge latch store_data_r directly, skipping the prime cycle.
        if (accepting_mstore)
            curr_reg = (first_store_reg == 4'd8) ? 4'd14 : first_store_reg;
        wb_valid_o  = 1'b0;
        exc_o       = 1'b0;
        sp_we_o     = 1'b0;
        sp_data_o   = 32'd0;

        // Keep EX frozen through every response/bookkeeping state.  The IDEX
        // register updates on the falling edge; releasing the stall in a
        // response state would let a following memory instruction enter EX,
        // then be overwritten before this sequencer returned to IDLE and could
        // accept it.  Releasing only in IDLE avoids that lost back-to-back
        // memory-operation race.
        // The transfer is complete in SINGLE_REQ's ready cycle: the store is committed
        // and the load writeback is being issued from live bus data. EX no longer needs
        // to be frozen, and the accept logic above catches whatever arrives next. This
        // is what turns a 3-cycle load/store into the 2 cycles the Cortex-M0 TRM
        // specifies.
        // A pipelined load is likewise complete in its final retire cycle: the last
        // register's writeback is issued from live bus data, so the stall is released
        // there too, giving LDM/POP the 1+N cost the Cortex-M0 TRM specifies. Held
        // when PC was retired: the redirect must flush before anything advances.
        stall_o = (curr_state != IDLE) && !((curr_state == SINGLE_REQ) && ready_i)
                                       && !(ml_last_ret && !ml_ret_to_pc);

        case (curr_state)
            SINGLE_REQ: begin
                addr_o  = base_addr_r;
                wdata_o = store_data_r;
                size_o  = size_r;

                // For normal AHB accesses, dropping the request in the ready
                // cycle prevents the arbiter from interpreting the completed
                // transfer as a back-to-back duplicate.  PPB is local and is
                // removed from AHB in core.v, so it keeps a full-cycle strobe.
                if (local_r) begin
                    read_req_o  = load_r;
                    write_req_o = ~load_r;
                end else begin
                    read_req_o  = load_r  && !ready_i;
                    write_req_o = !load_r && !ready_i;
                end

                // Writeback in the ready cycle, straight off the bus.
                if (ready_i && load_r) begin
                    load_data_o = extend_load(rdata_i, size_r, sign_r);
                    Rd_o        = Rd_r;
                    wb_valid_o  = 1'b1;
                end
            end

            // Retained; no longer reachable for single accesses.
            SINGLE_RESP: begin
                addr_o      = base_addr_r;
                load_data_o = extend_load(resp_data_r, size_r, sign_r);
                Rd_o        = resp_rd_r;
                wb_valid_o  = 1'b1;
            end

            MULTI_PREP: begin
                // Keep the selected address visible for a local PPB decode,
                // although normal multi transfers target SRAM.
                addr_o = base_addr_r;
            end

            MULTI_REQ: begin
                addr_o = base_addr_r;
                size_o = 2'b10;

                if (local_r) begin
                    read_req_o  = multi_load_r;
                    write_req_o = ~multi_load_r;
                end else begin
                    read_req_o  = multi_load_r  && !ready_i;
                    write_req_o = !multi_load_r && !ready_i;
                end

                if (!multi_load_r)
                    wdata_o = store_data_r;
            end

            // Pipelined load output. Drive the current register's ADDRESS phase and,
            // in the same cycle, write back the register whose data returned (owed via
            // have_pend_r). rdata_i is the live returned word for that owed register.
            // Pipelined store output. During prime, point the register-file read at the
            // first register (settle). During beats, drive the current beat's address +
            // registered data, and point the read one register ahead to prefetch.
            MS_STREAM: begin
                size_o = 2'b10;
                if (str_prime_r) begin
                    // Settling read of the first register; no bus activity yet.
                    curr_reg = (str_next_reg_r == 4'd8) ? 4'd14 : str_next_reg_r;
                end else if (str_go_r) begin
                    addr_o  = str_addr_r;
                    wdata_o = store_data_r;
                    write_req_o = 1'b1;   // stream: new address phase every cycle
                    // Prefetch: present the NEXT register's data on store_data_i.
                    curr_reg = (str_next_reg_r == 4'd8) ? 4'd14 : str_next_reg_r;
                end

                // Base-register writeback once, after the final beat is accepted.
                // STMIA writes back last-address + 4; PUSH writes back the final
                // (lowest) address, which base_addr_r/str_addr_r already hold.
                if (str_go_r && s_adv && str_last_r && ~suppress_wb_r) begin
                    sp_we_o   = 1'b1;
                    sp_data_o = dec_r ? str_addr_r : (str_addr_r + 32'd4);
                end
            end

            ML_STREAM: begin
                addr_o     = base_addr_r;
                size_o     = 2'b10;
                read_req_o = !addr_done_r;         // one address phase per register,
                                                   // none once the list is exhausted

                if (ready_i && have_pend_r) begin
                    load_data_o = rdata_i;
                    Rd_o        = pend_rd_r;
                    // POP {...,pc} carrying an EXC_RETURN token goes to the exception
                    // unit, not the register file.
                    exc_o       = (pend_rd_r == 4'd15) && (rdata_i[31:4] == 28'hFFFFFFF);
                    wb_valid_o  = !exc_o;
                end

                // Base-register writeback once, after the final element is retired.
                if (ready_i && have_pend_r && last_pend_r && ~suppress_wb_r) begin
                    sp_we_o   = 1'b1;
                    sp_data_o = base_addr_r;
                end
            end

            MULTI_RESP: begin
                addr_o      = base_addr_r;
                load_data_o = resp_data_r;
                Rd_o        = resp_rd_r;

                // POP {...,pc} carrying an EXC_RETURN token is handed to the
                // exception unit, not the normal register-file writeback path.
                exc_o       = (resp_rd_r == 4'd15) &&
                              (resp_data_r[31:4] == 28'hFFFFFFF);
                wb_valid_o  = !exc_o;
            end

            MULTI_ADVANCE: begin
                addr_o = base_addr_r;

                // Stack writeback occurs exactly once after the final element.
                // base_addr_r already includes all POP increments or PUSH
                // decrements by the time this state is reached.
                if (multi_last && ~suppress_wb_r) begin
                    sp_we_o   = 1'b1;         // base-register writeback (PUSH/POP/LDM/STM)
                    sp_data_o = base_addr_r;
                end
            end

            default: ;
        endcase
    end

    assign base_reg_o = Rd_r;
endmodule
