`timescale 1ns / 1ps
// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2025-2026 Dylan Thornburg and Bryce Kelly
//
// This file is part of the Open-Source ARM Cortex-M0 project.
// Licensed under the GNU General Public License v3.0 or later.
// See the LICENSE file at the root of this repository.
//////////////////////////////////////////////////////////////////////////////////
// Create Date: 10/26/2025 05:12:19 PM
// Module Name: IDEX
//////////////////////////////////////////////////////////////////////////////////
module IDEX(
    input clk,
    input IDEX_EN, IDEX_wipe,
    input [31:0] PC_ID,
    input [3:0] Rd_ID,
    input [31:0] Rn_ID,
    input [31:0] Rm_ID,
    input [31:0] Rt_ID,
    input [31:0] Imm_ID,
    input [31:0] Addr_ID,
    input [3:0] ALU_op_ID, cond_ID,
    input [1:0] size_ID, type_ID, barrier_ID,
    input ALU_src_ID, memread_ID, memwrite_ID, regwrite_ID, wd_src_ID, branchC_ID, move_ID, flags_ID, sign_ID, extend_ID, reverse_ID, sr_ID, cps_ID, svc_ID, bkpt_ID, udf_ID,
    input [1:0] awpc_ID,

    output reg [31:0] PC_EX,
    output reg [3:0] Rd_EX,
    output reg [31:0] Rn_EX,
    output reg [31:0] Rm_EX,
    output reg [31:0] Rt_EX,
    output reg [31:0] Imm_EX,
    output reg [31:0] Addr_EX,
    output reg [3:0] ALU_op_EX, cond_EX,
    output reg [1:0] size_EX, type_EX, barrier_EX,
    output reg ALU_src_EX, memread_EX, memwrite_EX, regwrite_EX, wd_src_EX, branchC_EX, move_EX, flags_EX, sign_EX, extend_EX, reverse_EX, sr_EX, cps_EX, svc_EX, bkpt_EX, udf_EX,
    output reg [1:0] awpc_EX
    );

    always @ (negedge clk) begin
        if (IDEX_wipe) begin
            PC_EX       <= 0;
            Rd_EX       <= 0;
            Rn_EX       <= 0;
            Rm_EX       <= 0;
            Rt_EX       <= 0;
            Imm_EX      <= 0;
            Addr_EX     <= 0;
            ALU_op_EX   <= 0;
            cond_EX     <= 0;
            size_EX     <= 0;
            type_EX     <= 0;
            barrier_EX  <= 0;
            ALU_src_EX  <= 0;
            memread_EX  <= 0;
            memwrite_EX <= 0;
            regwrite_EX <= 0;
            wd_src_EX   <= 0;
            branchC_EX  <= 0;
            move_EX     <= 0;
            flags_EX    <= 0;
            sign_EX     <= 0;
            extend_EX   <= 0;
            reverse_EX  <= 0;
            sr_EX       <= 0;
            cps_EX      <= 0;
            svc_EX      <= 0;
            bkpt_EX     <= 0;
            udf_EX      <= 0;
            awpc_EX     <= 0;
        end
        else if (IDEX_EN) begin
            PC_EX       <= PC_ID;
            Rd_EX       <= Rd_ID;
            Rn_EX       <= Rn_ID;
            Rm_EX       <= Rm_ID;
            Rt_EX       <= Rt_ID;
            Imm_EX      <= Imm_ID;
            Addr_EX     <= Addr_ID;
            ALU_op_EX   <= ALU_op_ID;
            cond_EX     <= cond_ID;
            size_EX     <= size_ID;
            type_EX     <= type_ID;
            barrier_EX  <= barrier_ID;
            ALU_src_EX  <= ALU_src_ID;
            memread_EX  <= memread_ID;
            memwrite_EX <= memwrite_ID;
            regwrite_EX <= regwrite_ID;
            wd_src_EX   <= wd_src_ID;
            branchC_EX  <= branchC_ID;
            move_EX     <= move_ID;
            flags_EX    <= flags_ID;
            sign_EX     <= sign_ID;
            extend_EX   <= extend_ID;
            reverse_EX  <= reverse_ID;
            sr_EX       <= sr_ID;
            cps_EX      <= cps_ID;
            svc_EX      <= svc_ID;
            bkpt_EX     <= bkpt_ID;
            udf_EX      <= udf_ID;
            awpc_EX     <= awpc_ID;
        end
    end
endmodule
