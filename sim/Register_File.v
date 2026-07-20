`timescale 1ns / 1ps
// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2025-2026 Dylan Thornburg and Bryce Kelly
//
// This file is part of the Open-Source ARM Cortex-M0 project.
// Licensed under the GNU General Public License v3.0 or later.
// See the LICENSE file at the root of this repository.
//////////////////////////////////////////////////////////////////////////////////
// Create Date: 11/12/2025 05:07:48 AM
// Module Name: Register_File
// Description: R0 to R14. R15 is not stored here: PC reads are supplied from the
// pipeline and PC writes are handled as branch redirects.
//////////////////////////////////////////////////////////////////////////////////


module Register_File(
    input clk,
    input we_WB,
    input [31:0] wd_WB,
    input [31:0] PC_in,
    input [3:0] Rd_WB,
    input [3:0] Rn,
    input [3:0] Rm,
    input [3:0] Rt,
    input [3:0] Rmulti,          // dedicated read for multi-store data (never hijacks Rm)
    output reg [31:0] Rn_o,
    output reg [31:0] Rm_o,
    output reg [31:0] Rt_o,
    output reg [31:0] Rmulti_o,

    input we_exc,
    input [3:0] Rd_exc,
    input [31:0] wd_exc,
    input exc_sp_psp,          // exception SP write target: 1=PSP, 0=MSP (from Exception_Unit)
    input spsel,            // CONTROL.SPSEL
    input [5:0] ipsr,       // IPSR (0 = Thread mode)
    input msr_msp_we,       // MSR MSP,<Rn>  -> write Registers[13]
    input msr_psp_we,       // MSR PSP,<Rn>  -> write psp_r
    input [31:0] msr_sp_d,  // value for MSR MSP/PSP
    input dm_sp_we,             // multi-register base writeback (PUSH/POP/LDM/STM)
    input [31:0] dm_sp_d,
    input [3:0]  dm_wb_reg,      // base register to write back (SP=13 for PUSH/POP)
    output [31:0] R0, R1, R2, R3, R12, SP, LR,
    output [31:0] MSP_o, PSP_o
    );

    // Test setup so registers can be used from the start
    reg [31:0] Registers[0:14];   // R13 entry = MSP
    reg [31:0] psp_r;             // banked Process Stack Pointer
    integer i;

    // ARMv6-M: the active SP is PSP only in Thread mode with SPSEL=1; Handler
    // mode (IPSR != 0) always uses MSP. With SPSEL=0 (reset default) this is
    // transparent: the active SP is always MSP = Registers[13].
    wire use_psp = spsel & (ipsr == 6'd0);
    wire [31:0] sp_active = use_psp ? psp_r : Registers[13];

    assign R0 = Registers[0];
    assign R1 = Registers[1];
    assign R2 = Registers[2];
    assign R3 = Registers[3];
    assign R12 = Registers[12];
    assign SP = sp_active;
    assign LR = Registers[14];
    assign MSP_o = Registers[13];   // MRS MSP reads the main SP specifically
    assign PSP_o = psp_r;           // MRS PSP reads the process SP specifically

    initial begin
        for (i=0; i<15; i=i+1)
            Registers[i] = 0;
        psp_r = 0;
    end



    always@(negedge clk) begin
        if (we_exc) begin
            if      (Rd_exc == 4'd13 && exc_sp_psp) psp_r         <= wd_exc;
            else if (Rd_exc == 4'd13)               Registers[13] <= wd_exc;
            else                                    Registers[Rd_exc] <= wd_exc;
        end else if (we_WB) begin
            if (Rd_WB == 4'd13 && use_psp) psp_r <= wd_WB;
            else                           Registers[Rd_WB] <= wd_WB;
        end
        // MSR MSP/PSP,<Rn> target the specific stack pointer regardless of banking.
        if (msr_msp_we) Registers[13] <= msr_sp_d;
        if (msr_psp_we) psp_r         <= msr_sp_d;
        if (dm_sp_we) begin
            if      (dm_wb_reg == 4'd13 && use_psp) psp_r         <= dm_sp_d;
            else if (dm_wb_reg == 4'd13)            Registers[13] <= dm_sp_d;
            else                                    Registers[dm_wb_reg] <= dm_sp_d;
        end
    end

    // Same-cycle bypasses. dm_sp_we mirrors the we_WB bypass: a pipelined LDM/POP
    // now releases the pipeline stall in its final retire cycle, so the following
    // instruction reads its operands in the same cycle the base-register writeback
    // is committed on the negedge. Without the bypass it would read the stale base
    // (e.g. push {r7,lr} / sub sp,#n prologues would compute from the pre-push SP).
    // dm_sp_we is checked first, matching the negedge block where it is written
    // last and therefore wins any same-register conflict.
    always@(*) begin
        Rn_o = (dm_sp_we && Rn == dm_wb_reg) ? dm_sp_d : (we_exc && Rn == Rd_exc) ? wd_exc : (we_WB && Rn == Rd_WB) ? wd_WB : Rn==15 ? PC_in : Rn==13 ? sp_active : Registers[Rn];
        Rm_o = (dm_sp_we && Rm == dm_wb_reg) ? dm_sp_d : (we_exc && Rm == Rd_exc) ? wd_exc : (we_WB && Rm == Rd_WB) ? wd_WB : Rm==15 ? PC_in : Rm==13 ? sp_active : Registers[Rm];
        Rt_o = (dm_sp_we && Rt == dm_wb_reg) ? dm_sp_d : (we_exc && Rt == Rd_exc) ? wd_exc : (we_WB && Rt == Rd_WB) ? wd_WB : Rt==15 ? PC_in : Rt==13 ? sp_active : Registers[Rt];
        Rmulti_o = (dm_sp_we && Rmulti == dm_wb_reg) ? dm_sp_d : (we_exc && Rmulti == Rd_exc) ? wd_exc : (we_WB && Rmulti == Rd_WB) ? wd_WB : Rmulti==15 ? PC_in : Rmulti==13 ? sp_active : Registers[Rmulti];

    end

endmodule
