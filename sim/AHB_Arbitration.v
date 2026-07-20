`timescale 1ns / 1ps
// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2025-2026 Dylan Thornburg and Bryce Kelly
//
// This file is part of the Open-Source ARM Cortex-M0 project.
// Licensed under the GNU General Public License v3.0 or later.
// See the LICENSE file at the root of this repository.
//////////////////////////////////////////////////////////////////////////////////
// Create Date: 04/27/2026 04:18:38 AM
// Module Name: AHB_Arbitration
// Description: Arbitrates instruction fetch against data access on the single
// AHB-Lite master port, and handles branch redirects.
//////////////////////////////////////////////////////////////////////////////////


module AHB_Arbitration(
    input clk,
    input rst_n,

    input [31:0] if_PC_i, branch_addr_i,
    input if_read_req_i,
    input fetch, branch,
    output reg [31:0] if_data_o,
    output reg if_ready_o, if_stall_o,
    output     if_word_valid_o,   // Instr in if_data_o is the valid fetched word for if_PC_i

    input [31:0] dm_addr_i,  dm_data_i,
    input dm_read_req_i, dm_write_req_i,
    input [1:0] dm_size_i,
    output reg [31:0] dm_data_o,
    output reg dm_ready_o,
    output dm_grant_o,             // dm_addr_i is being issued as an AHB ADDRESS phase this cycle
    output reg dm_error_o,         // data access terminated by a bus error

    input [31:0] ahb_data_i,
    input ahb_ready_i,
    input ahb_error_i,             // AHB error response (HRESP=ERROR) from master
    output reg [31:0] ahb_addr_o,
    output reg [1:0] ahb_size_o,
    output reg ahb_write_req_o, ahb_read_req_o,
    output [31:0] ahb_data_o,


    input  [31:0] exc_addr_i, exc_data_i,
    input  exc_read_req_i, exc_write_req_i,
    input  [1:0] exc_size_i,
    output reg exc_ready_o,
    output reg exc_error_o,        // exception-unit access terminated by a bus error
    output reg [31:0] exc_data_o
    );

    parameter [2:0] IDLE = 3'b000, DM = 3'b001, IF = 3'b010, EXC = 3'b011, BRANCH = 3'b100;
    reg [2:0] curr_state, next_state;

    reg data_phase_if_r, data_phase_dm_r, data_write_r, data_phase_exc_r, data_write_exc_r;
    reg [31:0] if_data_held, if_addr_held, addr_bus;
    // FIX: AHB is pipelined. addr_bus is the address currently in the ADDRESS phase;
    // the data for it lands one transfer LATER. addr_dp shifts addr_bus into the DATA
    // phase, so it is the address that ahb_data_i actually belongs to.
    reg [31:0] addr_dp;
    reg if_data_valid, bus_valid;
    reg fresh_fetch;   // set by a branch; suppresses the prefetch increment so the
                       // first fetch after a redirect grabs the target's OWN word
                       // (fetch = PC[1] otherwise prefetches the next word, which is
                       // wrong when the target lands on a high halfword)

    wire [4:0] instr_check_local = if_PC_i[1] ? if_data_o[31:27] : if_data_o[15:11];
    wire is_32bit_local = (instr_check_local == 5'b11101) || (instr_check_local[4:1] == 4'b1111);

    always @ (posedge clk) begin
        if(!rst_n) begin
            curr_state <= IDLE;
            data_phase_if_r <= 1'b0;
            data_phase_dm_r <= 1'b0;
            data_write_r <= 1'b0;
            data_phase_exc_r <= 1'b0;
            data_write_exc_r <= 1'b0;
            if_data_held  <= 32'b0;
            if_addr_held <= 32'b0;
            if_data_valid <= 1'b0;
            if_stall_o <= 1'b0;
            addr_bus <= 32'b0;
            addr_dp  <= 32'b0;
            bus_valid <= 1'b0;
            fresh_fetch <= 1'b0;
        end
        else begin
            curr_state <= next_state;
            data_phase_if_r <= (next_state == IF);
            data_phase_dm_r <= (next_state == DM);
            data_write_r <= dm_write_req_i & (next_state == DM);
            data_phase_exc_r <= (next_state == EXC);
            data_write_exc_r <= exc_write_req_i & (next_state == EXC);
            if_stall_o <= fetch && ~if_ready_o;

            if (next_state == IF || next_state == BRANCH) begin
                addr_bus <= ahb_addr_o;
                bus_valid <= 1'b1;
            end
            addr_dp <= addr_bus;   // address phase -> data phase

            if (branch)
                fresh_fetch <= 1'b1;
            else if (next_state == IF)
                fresh_fetch <= 1'b0;

            if (branch) begin
                if_data_valid <= 1'b0;
                if_addr_held  <= 32'b0;
            end
            // FIX: BRANCH removed. In the BRANCH state the target is still in the AHB
            // ADDRESS phase, so ahb_data_i is the PREVIOUS transfer's data. Capturing
            // there stamped stale data (observed: mem[0] = 0x20002000) with the branch
            // target's address, and the core decoded it as a real instruction. The IF
            // state refetches the target immediately after, so nothing is lost.
            else if ((curr_state == IF || curr_state == BRANCH) && ahb_ready_i && bus_valid
                     && (addr_bus[31:2] == if_PC_i[31:2])) begin
                if_data_held  <= ahb_data_i;
                // Tag the word with addr_bus, the address this data phase actually
                // belongs to. ahb_addr_o would be wrong here: it already holds the NEXT
                // transfer's address, so a load or store preempting a fetch would tag
                // the instruction word with a data address.
                if_addr_held <= addr_bus;
                if_data_valid <= 1'b1;
            end
            else if (({if_PC_i[31:2], 2'b00} != {if_addr_held[31:2], 2'b00}))
                if_data_valid <= 1'b0;
        end
    end

    always @(*)begin
        // Hold the current state unless an arm below says otherwise. Every wait
        // condition in DM/IF/EXC/BRANCH relies on this: without an explicit default
        // the state vector is incompletely assigned and synthesis infers level
        // latches on it, which wrecks static timing analysis.
        next_state = curr_state;
        case (curr_state)
            IDLE: begin
                if(branch) next_state = BRANCH;
                else if (exc_read_req_i || exc_write_req_i)
                    next_state = EXC;
                else if(dm_read_req_i || dm_write_req_i)
                    next_state = DM;
                else if (if_read_req_i)
                    next_state = IF;
                else next_state = IDLE;
            end
            DM: begin
                if(branch) next_state = BRANCH;
                else if(ahb_ready_i | ahb_error_i) begin
                    if (exc_read_req_i || exc_write_req_i)
                        next_state = EXC;
                    else if(dm_read_req_i || dm_write_req_i)
                        next_state = DM;
                    else if (if_read_req_i)
                        next_state = IF;
                    else next_state = IDLE;
                end
            end
            IF: begin
                if(branch) next_state = BRANCH;
                else if(ahb_ready_i | ahb_error_i) begin
                    if (exc_read_req_i || exc_write_req_i)
                        next_state = EXC;
                    else if(dm_read_req_i || dm_write_req_i)
                        next_state = DM;   // FIX: was IDLE -- a wasted bus cycle on every access
                    else if (if_read_req_i)
                        next_state = IF;
                    else next_state = IDLE;
                end
            end
            EXC: begin
                if(branch) next_state = BRANCH;
                else if(ahb_ready_i | ahb_error_i) begin
                    if (exc_read_req_i || exc_write_req_i)
                        next_state = EXC;
                    else if(dm_read_req_i || dm_write_req_i)
                        next_state = DM;   // FIX: was IDLE -- a wasted bus cycle on every access
                    else if (if_read_req_i)
                        next_state = IF;
                    else next_state = IDLE;
                end
            end
            BRANCH: begin
                if (ahb_ready_i) begin
                    if (exc_read_req_i || exc_write_req_i)
                        next_state = EXC;
                    else if(dm_read_req_i || dm_write_req_i)
                        next_state = DM;   // FIX: was IDLE -- a wasted bus cycle on every access
                    else if (if_read_req_i)
                        next_state = IDLE;
                    else next_state = IDLE;
                end
            end
            default: next_state = IDLE;
        endcase
    end
    assign ahb_data_o = (next_state == DM) ? dm_data_i : exc_data_i;
    // Address-phase grant for the data-memory sequencer. next_state == DM marks the
    // cycle in which ahb_main latches dm_addr_i as a new NONSEQ address phase (from
    // ST_IDLE on request, or in ST_DATA when HREADY). next_state also holds DM
    // through a slave wait state, so qualify with the same completion condition the
    // transition logic used; from arbiter IDLE the launch is unconditional. This is
    // the signal a pipelined multi-register stream must advance on: dm_ready_o marks
    // the DATA phase, one transfer later, and advancing on it re-issues the first
    // address of every stream (one duplicated bus transfer per LDM/STM/PUSH/POP).
    assign dm_grant_o = (next_state == DM) &&
                        ((curr_state == IDLE) | ahb_ready_i | ahb_error_i);
    always @(*) begin
        ahb_addr_o = 32'b0;
        ahb_size_o = 2'b10;
        ahb_write_req_o = 1'b0;
        ahb_read_req_o = 1'b0;


        case(next_state)
            IDLE: begin
                ahb_addr_o = dm_addr_i;
                ahb_size_o = dm_size_i;
                // FIX: next_state==IDLE means NO transfer is being issued. Driving the
                // data-memory write request here made ahb_main see `request` high and
                // start a NONSEQ address phase from IDLE, and then a SECOND one when the
                // FSM actually entered DM. Every store went out as TWO AHB writes, the
                // first with HWDATA still 0. Invisible on SRAM (0 then the real value, so
                // the end state is right) but a peripheral saw the side effect twice.
                ahb_write_req_o = 1'b0;
            end
            DM: begin
                ahb_addr_o = dm_addr_i;
                ahb_size_o = dm_size_i;
                ahb_write_req_o = dm_write_req_i;
                ahb_read_req_o = dm_read_req_i;

            end
            IF: begin
                ahb_addr_o = {if_PC_i[31:2]
                              + ((fetch | is_32bit_local) & have_word & ~fresh_fetch), 2'b0};
                ahb_size_o = 2'b10;
                ahb_read_req_o = 1'b1;
            end
            EXC: begin
                ahb_addr_o = exc_addr_i;
                ahb_size_o = exc_size_i;
                ahb_write_req_o = exc_write_req_i;
                ahb_read_req_o = exc_read_req_i;
            end
            BRANCH: begin
                ahb_addr_o = {branch_addr_i[31:2], 2'b0};
                ahb_size_o = 2'b10;
                ahb_read_req_o =  1'b1;
            end
            default: ;
        endcase
    end
    // Source word(PC) from whichever holder actually has it.
    wire held_match = if_data_valid   & (if_addr_held[31:2] == if_PC_i[31:2]);
    wire bus_match  = (data_phase_if_r | (curr_state == BRANCH))
                    & (addr_bus[31:2] == if_PC_i[31:2]);
    wire have_word  = held_match | bus_match;
    assign if_word_valid_o = have_word;
    always @(*) begin
        dm_data_o = 32'b0;
        dm_ready_o = 1'b0;
        dm_error_o = 1'b0;
        exc_error_o = 1'b0;
        if_ready_o = 1'b0;
        if_data_o = 32'b0;
        exc_ready_o = 1'b0;
        exc_data_o = 32'b0;

        if(curr_state == IDLE && fetch)
            if_data_o = if_data_o;
        else
            if_data_o = 32'b0;

        if (ahb_ready_i | ahb_error_i) begin
            if(data_phase_exc_r) begin
                exc_ready_o = 1'b1;              // complete on ready or error
                exc_error_o = ahb_error_i;
                if(~data_write_exc_r)
                    exc_data_o = ahb_data_i;
            end
            else if(data_phase_dm_r) begin
                dm_ready_o = 1'b1;               // complete on ready or error
                dm_error_o = ahb_error_i;
                if(~data_write_r)
                    dm_data_o = ahb_data_i;
            end
        end

        // A fetch that takes a bus error completes with a UDF poison word (0xDE00 in
        // each halfword); it raises a HardFault only if it is actually executed, so a
        // speculative prefetch past a branch that gets flushed never faults.
        if_data_o  = bus_match  ? (ahb_error_i ? 32'hDE00DE00 : ahb_data_i) :
                     held_match ? if_data_held :
                                  32'b0;   // nothing for PC -> is_32bit_local reads 0



        if_ready_o = ((bus_match & (ahb_ready_i | ahb_error_i)) | held_match)
                     & ~branch;

    end
endmodule
