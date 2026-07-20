`timescale 1ns / 1ps
// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2025-2026 Dylan Thornburg and Bryce Kelly
//
// This file is part of the Open-Source ARM Cortex-M0 project.
// Licensed under the GNU General Public License v3.0 or later.
// See the LICENSE file at the root of this repository.
//////////////////////////////////////////////////////////////////////////////////
// Create Date: 04/05/2026 09:43:34 PM
// Module Name: Exception_Unit
// Description: Exception entry and return sequencing, including stacking,
// unstacking and EXC_RETURN handling.
//////////////////////////////////////////////////////////////////////////////////

module Exception_Unit (
    input clk,
    input rst_n,

    input int_pend_i,
    input [5:0] int_pend_num_i,
    output reg         exc_taken_o,
    output reg  [5:0]  exc_taken_num_o,
    output reg         exc_return_o,
    output reg  [5:0]  exc_return_num_o,

    input branch_exc_in,
    input ldm_exc_in,
    input [5:0] IPSR_i,
    input  [31:0] return_PC_i,
    input  [31:0] APSR_i,
    input  [31:0] R0_i, R1_i, R2_i,
    input  [31:0] R3_i, R12_i, LR_i,
    input  [31:0] SP_i,
    input         spsel_i,          // CONTROL.SPSEL
    input  [31:0] psp_i,            // Process SP (for FD return unstacking)
    input  [31:0] exc_return_val_i, // EXC_RETURN token that triggered a return

    output reg exc_active_o,
    output reg exc_flush_o,
    output reg exc_PC_valid_o,
    output reg [31:0] exc_PC_target_o,

    output reg rf_we_o,
    output reg [3:0]  rf_addr_o,
    output reg [31:0] rf_wdata_o,
    output reg        exc_sp_psp_o,   // exception SP write target: 1=PSP, 0=MSP

    output reg ipsr_we_o,
    output reg [5:0] ipsr_wdata_o,
    output reg apsr_we_o,
    output reg [3:0] apsr_wdata_o,

    output reg exc_read_req_o,
    output reg exc_write_req_o,
    output reg [1:0] exc_size_o,
    output reg [31:0] exc_addr_o,
    output reg [31:0] exc_wdata_o,
    input [31:0] exc_rdata_i,
    input exc_ready_i
);


    parameter [3:0] R_R0 = 4'd0, R_R1 = 4'd1, R_R2 = 4'd2, R_R3 = 4'd3, R_R12 = 4'd12,
                    R_SP = 4'd13, R_LR = 4'd14;

    parameter [31:0] EXC_RETURN_HANDLER_MSP = 32'hFFFF_FFF1;
    parameter [31:0] EXC_RETURN_THREAD_MSP  = 32'hFFFF_FFF9;
    parameter [31:0] EXC_RETURN_THREAD_PSP  = 32'hFFFF_FFFD;

    parameter [4:0] //States for Pushing registers on excp
        S_RESET_FETCH_SP   = 5'd0,
        S_RESET_FETCH_PC   = 5'd1,
        S_RESET_COMMIT     = 5'd2,
        S_IDLE             = 5'd3,
        S_ENT_PUSH_xPSR    = 5'd4,
        S_ENT_PUSH_PC      = 5'd5,
        S_ENT_PUSH_LR      = 5'd6,
        S_ENT_PUSH_R12     = 5'd7,
        S_ENT_PUSH_R3      = 5'd8,
        S_ENT_PUSH_R2      = 5'd9,
        S_ENT_PUSH_R1      = 5'd10,
        S_ENT_PUSH_R0      = 5'd11,
        S_ENT_VECFETCH     = 5'd12,
        S_ENT_COMMIT       = 5'd13,
        S_RET_POP_R0       = 5'd14,
        S_RET_POP_R1       = 5'd15,
        S_RET_POP_R2       = 5'd16,
        S_RET_POP_R3       = 5'd17,
        S_RET_POP_R12      = 5'd18,
        S_RET_POP_LR       = 5'd19,
        S_RET_POP_PC       = 5'd20,
        S_RET_POP_xPSR     = 5'd21,
        S_RET_COMMIT       = 5'd22;

    reg [4:0]  state, next_state;

    reg [5:0]  vec_num_r;
    reg [31:0] sp_r;
    reg [31:0] vec_addr_r;
    reg [31:0] vector_r;
    reg [31:0] return_PC_r;
    reg [31:0] popped_PC_r;
    reg [5:0]  ret_ipsr_r;
    reg [5:0]  ret_ipsr_stk_r;   // pre-exception IPSR recovered from the stacked xPSR
    reg        align_r;          // entry: 8-byte alignment pad inserted
    reg        align_ret_r;      // return: stacked alignment bit
    reg [31:0] excret_r;         // computed EXC_RETURN token
    reg        sppsp_r;          // SP write target for this entry/return

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) state <= S_RESET_FETCH_SP;
        else        state <= next_state;
    end

    // AHB-Lite slave read data is registered, so it lags the address phase by
    // a cycle. rd_settled is low for the first cycle after the FSM presents a
    // new fetch address (state change), preventing the reset vector fetch from
    // latching stale read data left over from the previous transfer. Without
    // this, the PC fetch (addr 0x4) captures the SP word (addr 0x0) and the
    // core resets with PC = initial SP instead of the reset handler.
    reg [4:0] state_q;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) state_q <= S_RESET_FETCH_SP;
        else        state_q <= state;
    end
    wire rd_settled = (state == state_q);

    always @(*) begin
        next_state = state;
        case (state)
            S_RESET_FETCH_SP: if (exc_ready_i && rd_settled) next_state = S_RESET_FETCH_PC;
            S_RESET_FETCH_PC: if (exc_ready_i && rd_settled) next_state = S_RESET_COMMIT;
            S_RESET_COMMIT:                 next_state = S_IDLE;

            S_IDLE: begin
                if (branch_exc_in || ldm_exc_in)
                    next_state = S_RET_POP_R0;
                else if (int_pend_i)
                    next_state = S_ENT_PUSH_xPSR;
            end

            S_ENT_PUSH_xPSR: if (exc_ready_i) next_state = S_ENT_PUSH_PC;
            S_ENT_PUSH_PC:   if (exc_ready_i) next_state = S_ENT_PUSH_LR;
            S_ENT_PUSH_LR:   if (exc_ready_i) next_state = S_ENT_PUSH_R12;
            S_ENT_PUSH_R12:  if (exc_ready_i) next_state = S_ENT_PUSH_R3;
            S_ENT_PUSH_R3:   if (exc_ready_i) next_state = S_ENT_PUSH_R2;
            S_ENT_PUSH_R2:   if (exc_ready_i) next_state = S_ENT_PUSH_R1;
            S_ENT_PUSH_R1:   if (exc_ready_i) next_state = S_ENT_PUSH_R0;
            S_ENT_PUSH_R0:   if (exc_ready_i) next_state = S_ENT_VECFETCH;
            S_ENT_VECFETCH:  if (exc_ready_i && rd_settled) next_state = S_ENT_COMMIT;
            S_ENT_COMMIT:                  next_state = S_IDLE;

            S_RET_POP_R0:    if (exc_ready_i && rd_settled) next_state = S_RET_POP_R1;
            S_RET_POP_R1:    if (exc_ready_i && rd_settled) next_state = S_RET_POP_R2;
            S_RET_POP_R2:    if (exc_ready_i && rd_settled) next_state = S_RET_POP_R3;
            S_RET_POP_R3:    if (exc_ready_i && rd_settled) next_state = S_RET_POP_R12;
            S_RET_POP_R12:   if (exc_ready_i && rd_settled) next_state = S_RET_POP_LR;
            S_RET_POP_LR:    if (exc_ready_i && rd_settled) next_state = S_RET_POP_PC;
            S_RET_POP_PC:    if (exc_ready_i && rd_settled) next_state = S_RET_POP_xPSR;
            S_RET_POP_xPSR:  if (exc_ready_i && rd_settled) next_state = S_RET_COMMIT;
            S_RET_COMMIT:                  next_state = S_IDLE;

            default: next_state = S_IDLE;
        endcase
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            vec_num_r   <= 6'd0;
            sp_r        <= 32'd0;
            vec_addr_r  <= 32'd0;
            vector_r    <= 32'd0;
            return_PC_r <= 32'd0;
            popped_PC_r <= 32'd0;
            ret_ipsr_r  <= 6'd0;
            ret_ipsr_stk_r <= 6'd0;
            align_r     <= 1'b0;
            align_ret_r <= 1'b0;
            excret_r    <= EXC_RETURN_THREAD_MSP;
            sppsp_r     <= 1'b0;
        end else begin
            case (state)
                S_IDLE: begin
                    if (branch_exc_in || ldm_exc_in) begin
                        // Return: EXC_RETURN[3:0] picks the SP to unstack from.
                        // FD -> PSP; F1/F9 -> MSP (= active SP, since we are in Handler).
                        sp_r       <= (exc_return_val_i[3:0] == 4'hD) ? psp_i : SP_i;
                        sppsp_r    <= (exc_return_val_i[3:0] == 4'hD);
                        ret_ipsr_r <= IPSR_i;
                    end else if (int_pend_i) begin
                        vec_num_r   <= int_pend_num_i;
                        // 8-byte frame alignment: xPSR slot sits at top of the aligned frame.
                        sp_r        <= (((SP_i - 32'h20) & ~32'h4) + 32'h1C);
                        align_r     <= SP_i[2];
                        return_PC_r <= return_PC_i;
                        vec_addr_r  <= {24'd0, int_pend_num_i, 2'b00};
                        // EXC_RETURN reflects the interrupted context.
                        excret_r    <= (IPSR_i != 6'd0) ? EXC_RETURN_HANDLER_MSP :
                                       (spsel_i)        ? EXC_RETURN_THREAD_PSP  :
                                                          EXC_RETURN_THREAD_MSP;
                        sppsp_r     <= (IPSR_i == 6'd0) & spsel_i;
                    end
                end

                S_ENT_PUSH_xPSR, S_ENT_PUSH_PC,  S_ENT_PUSH_LR,
                S_ENT_PUSH_R12, S_ENT_PUSH_R3,  S_ENT_PUSH_R2,
                S_ENT_PUSH_R1:
                    if (exc_ready_i) sp_r <= sp_r - 32'd4;

                // S_ENT_PUSH_R0 done -> sp_r holds at final value (= SP - 32)

                S_ENT_VECFETCH:
                    if (exc_ready_i && rd_settled) vector_r <= {exc_rdata_i[31:1], 1'b0};

                S_RET_POP_R0,  S_RET_POP_R1,   S_RET_POP_R2,
                S_RET_POP_R3,  S_RET_POP_R12,  S_RET_POP_LR:
                    if (exc_ready_i && rd_settled) sp_r <= sp_r + 32'd4;

                S_RET_POP_PC:
                    if (exc_ready_i && rd_settled) begin
                        popped_PC_r <= {exc_rdata_i[31:1], 1'b0};
                        sp_r        <= sp_r + 32'd4;
                    end

                S_RET_POP_xPSR:
                    if (exc_ready_i && rd_settled) begin
                        sp_r           <= sp_r + 32'd4;
                        ret_ipsr_stk_r <= exc_rdata_i[5:0];
                        align_ret_r    <= exc_rdata_i[9];
                    end

                S_RESET_FETCH_SP: if (exc_ready_i && rd_settled) sp_r     <= exc_rdata_i;
                S_RESET_FETCH_PC: if (exc_ready_i && rd_settled) vector_r <= {exc_rdata_i[31:1], 1'b0};

                default: ;
            endcase
        end
    end

    always @(*) begin
        exc_active_o     = 1'b1;       // default: be busy
        exc_flush_o      = 1'b0;
        exc_PC_valid_o   = 1'b0;
        exc_PC_target_o  = 32'd0;

        exc_read_req_o   = 1'b0;
        exc_write_req_o  = 1'b0;
        exc_size_o       = 2'b10;
        exc_addr_o       = 32'd0;
        exc_wdata_o      = 32'd0;

        rf_we_o          = 1'b0;
        rf_addr_o        = 4'd0;
        rf_wdata_o       = 32'd0;
        exc_sp_psp_o     = sppsp_r;

        ipsr_we_o        = 1'b0;
        ipsr_wdata_o     = 6'd0;
        apsr_we_o        = 1'b0;
        apsr_wdata_o     = 4'd0;

        exc_taken_o      = 1'b0;
        exc_taken_num_o  = 6'd0;
        exc_return_o     = 1'b0;
        exc_return_num_o = 6'd0;

        case (state)
            // Fetch PC on restart
            S_RESET_FETCH_SP: begin
                exc_read_req_o = 1'b1;
                exc_addr_o     = 32'h0000_0000;
            end

            S_RESET_FETCH_PC: begin
                exc_read_req_o = 1'b1;
                exc_addr_o     = 32'h0000_0004;
                if (exc_ready_i) begin
                    rf_we_o    = 1'b1;
                    rf_addr_o  = R_SP;
                    rf_wdata_o = sp_r;
                end
            end

            S_RESET_COMMIT: begin
                rf_we_o          = 1'b1;
                rf_addr_o        = R_SP;
                rf_wdata_o       = sp_r;
                exc_PC_valid_o   = 1'b1;
                exc_PC_target_o  = vector_r;
                exc_flush_o      = 1'b1;
            end

            S_IDLE: begin
                exc_active_o = (int_pend_i || branch_exc_in || ldm_exc_in);
            end

            // Push regs
            S_ENT_PUSH_xPSR: begin
                exc_write_req_o = 1'b1;
                exc_addr_o      = sp_r;
                exc_wdata_o     = {APSR_i[31:28], 3'b0, 1'b1, 14'b0, align_r, 3'b0, IPSR_i[5:0]};
            end
            S_ENT_PUSH_PC: begin
                exc_write_req_o = 1'b1;
                exc_addr_o      = sp_r;
                exc_wdata_o     = return_PC_r;
            end
            S_ENT_PUSH_LR: begin
                exc_write_req_o = 1'b1;
                exc_addr_o      = sp_r;
                exc_wdata_o     = LR_i;
            end
            S_ENT_PUSH_R12: begin
                exc_write_req_o = 1'b1;
                exc_addr_o      = sp_r;
                exc_wdata_o     = R12_i;
            end
            S_ENT_PUSH_R3: begin
                exc_write_req_o = 1'b1;
                exc_addr_o      = sp_r;
                exc_wdata_o     = R3_i;
            end
            S_ENT_PUSH_R2: begin
                exc_write_req_o = 1'b1;
                exc_addr_o      = sp_r;
                exc_wdata_o     = R2_i;
            end
            S_ENT_PUSH_R1: begin
                exc_write_req_o = 1'b1;
                exc_addr_o      = sp_r;
                exc_wdata_o     = R1_i;
            end
            S_ENT_PUSH_R0: begin
                exc_write_req_o = 1'b1;
                exc_addr_o      = sp_r;
                exc_wdata_o     = R0_i;
            end

            S_ENT_VECFETCH: begin
                exc_read_req_o = 1'b1;
                exc_addr_o     = vec_addr_r;
                if (exc_ready_i) begin
                    rf_we_o    = 1'b1;
                    rf_addr_o  = R_SP;
                    rf_wdata_o = sp_r;
                end
            end

            S_ENT_COMMIT: begin
                rf_we_o          = 1'b1;
                rf_addr_o        = R_LR;
                rf_wdata_o       = excret_r;
                ipsr_we_o        = 1'b1;
                ipsr_wdata_o     = vec_num_r;
                exc_PC_valid_o   = 1'b1;
                exc_PC_target_o  = vector_r;
                exc_flush_o      = 1'b1;
                exc_taken_o      = 1'b1;
                exc_taken_num_o  = vec_num_r;
            end

            // Return pop regs
            S_RET_POP_R0: begin
                exc_read_req_o = 1'b1;
                exc_addr_o     = sp_r;
                if (exc_ready_i && rd_settled) begin
                    rf_we_o    = 1'b1;
                    rf_addr_o  = R_R0;
                    rf_wdata_o = exc_rdata_i;
                end
            end
            S_RET_POP_R1: begin
                exc_read_req_o = 1'b1;
                exc_addr_o     = sp_r;
                if (exc_ready_i && rd_settled) begin
                    rf_we_o    = 1'b1;
                    rf_addr_o  = R_R1;
                    rf_wdata_o = exc_rdata_i;
                end
            end
            S_RET_POP_R2: begin
                exc_read_req_o = 1'b1;
                exc_addr_o     = sp_r;
                if (exc_ready_i && rd_settled) begin
                    rf_we_o    = 1'b1;
                    rf_addr_o  = R_R2;
                    rf_wdata_o = exc_rdata_i;
                end
            end
            S_RET_POP_R3: begin
                exc_read_req_o = 1'b1;
                exc_addr_o     = sp_r;
                if (exc_ready_i && rd_settled) begin
                    rf_we_o    = 1'b1;
                    rf_addr_o  = R_R3;
                    rf_wdata_o = exc_rdata_i;
                end
            end
            S_RET_POP_R12: begin
                exc_read_req_o = 1'b1;
                exc_addr_o     = sp_r;
                if (exc_ready_i && rd_settled) begin
                    rf_we_o    = 1'b1;
                    rf_addr_o  = R_R12;
                    rf_wdata_o = exc_rdata_i;
                end
            end
            S_RET_POP_LR: begin
                exc_read_req_o = 1'b1;
                exc_addr_o     = sp_r;
                if (exc_ready_i && rd_settled) begin
                    rf_we_o    = 1'b1;
                    rf_addr_o  = R_LR;
                    rf_wdata_o = exc_rdata_i;
                end
            end
            S_RET_POP_PC: begin
                exc_read_req_o = 1'b1;
                exc_addr_o     = sp_r;
            end
            S_RET_POP_xPSR: begin
                exc_read_req_o = 1'b1;
                exc_addr_o     = sp_r;
                if (exc_ready_i) begin
                    apsr_we_o    = 1'b1;
                    apsr_wdata_o = exc_rdata_i[31:28];
                end
            end

            S_RET_COMMIT: begin
                rf_we_o          = 1'b1;
                rf_addr_o        = R_SP;
                rf_wdata_o       = align_ret_r ? (sp_r | 32'h4) : sp_r;
                exc_PC_valid_o   = 1'b1;
                exc_PC_target_o  = popped_PC_r;
                exc_flush_o      = 1'b1;
                ipsr_we_o        = 1'b1;
                ipsr_wdata_o     = ret_ipsr_stk_r;
                exc_return_o     = 1'b1;
                exc_return_num_o = ret_ipsr_r;
            end

            default: ;
        endcase
    end

endmodule
