`timescale 1ns / 1ps
// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2025-2026 Dylan Thornburg and Bryce Kelly
//
// This file is part of the Open-Source ARM Cortex-M0 project.
// Licensed under the GNU General Public License v3.0 or later.
// See the LICENSE file at the root of this repository.
//////////////////////////////////////////////////////////////////////////////////
// Create Date: 04/04/2026 05:32:26 AM
// Module Name: Special_Register_File
// Description: APSR, IPSR, EPSR, PRIMASK and CONTROL, plus the banked
// stack pointers.
//////////////////////////////////////////////////////////////////////////////////


module Special_Register_File(
    input HCLK, HRESETn,

    input flags_EX,
    input [3:0] flags,

    input sr_op,
    input mrs,             // 1=MRS(read), 0=MSR(write)
    input ipsr_we, apsr_we,
    input [3:0] apsr_data,
    input [5:0] ipsr_data,
    input [7:0] SYSm,
    input [31:0] wdata,
    input [31:0] msp_i,
    input [31:0] psp_i,
    output reg [31:0] rdata_o,
    output [31:0] APSR_o,
    output PRIMASK_o,
    output [5:0] IPSR_o,
    output [1:0] CONTROL_o
);

    reg [3:0]  APSR_flags;   // N,Z,C,V - bits [31:28]
    reg PRIMASK;
    reg [1:0] CONTROL;      // [1]=SPSEL, [0]=nPRIV
    reg [5:0] IPSR;

    assign APSR_o = {APSR_flags, 28'b0};
    assign PRIMASK_o = PRIMASK;
    assign IPSR_o = IPSR;
    assign CONTROL_o = CONTROL;

    // PRIMASK / CONTROL / IPSR update on the rising edge.  CONTROL.nPRIV (bit 0) is
    // RES0 on this core: ARMv6-M only defines nPRIV when the Unprivileged/Privileged
    // Extension is implemented, which a base Cortex-M0 does not, so it reads as zero
    // and ignores writes.  Only CONTROL.SPSEL (bit 1) is writable.
    always @(posedge HCLK or negedge HRESETn) begin
        if (!HRESETn) begin
            PRIMASK <= 1'b0;
            CONTROL <= 2'b0;
            IPSR    <= 6'b0;
        end else begin
            if (sr_op && !mrs && SYSm[7:3] == 5'b00010) begin
                case (SYSm[2:0])
                    3'b000:  PRIMASK <= wdata[0];
                    3'b100:  CONTROL <= {wdata[1], 1'b0};   // SPSEL only; nPRIV RES0
                    default: ;
                endcase
            end
            if (ipsr_we) IPSR <= ipsr_data;
        end
    end

    // APSR flag byte (N,Z,C,V,Q): a single driver, updated on the falling edge so it
    // lines up with the ALU's flag latch.  Sources, in priority order: the ALU result
    // flags, an exception-return APSR restore, then an explicit MSR APSR write.
    wire msr_apsr = sr_op && !mrs && (SYSm[7:3] == 5'b00000) && (SYSm[2:0] == 3'b000);
    always @(negedge HCLK or negedge HRESETn) begin
        if (!HRESETn)      APSR_flags <= 4'b0;
        else if (flags_EX) APSR_flags <= flags;
        else if (apsr_we)  APSR_flags <= apsr_data;
        else if (msr_apsr) APSR_flags <= wdata[31:28];
    end

    always @(*) begin
        rdata_o = 32'b0;
        if (sr_op && mrs) begin
            case (SYSm[7:3])
                5'b00000: begin
                    if (!SYSm[2]) rdata_o[31:28] = APSR_flags;
                    if (SYSm[0]) rdata_o[8:0] = {3'b0, IPSR};
                end
                5'b00001: begin
                    rdata_o = SYSm[0] ? psp_i : msp_i;   // MRS PSP(9)/MSP(8)
                end
                5'b00010: begin
                    case (SYSm[2:0])
                        3'b000: rdata_o[0] = PRIMASK;
                        3'b100: rdata_o[1:0] = CONTROL;
                    endcase
                end
                default: ;
            endcase
        end
    end
endmodule
