`timescale 1ns / 1ps
// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2025-2026 Dylan Thornburg and Bryce Kelly
//
// This file is part of the Open-Source ARM Cortex-M0 project.
// Licensed under the GNU General Public License v3.0 or later.
// See the LICENSE file at the root of this repository.
//////////////////////////////////////////////////////////////////////////////////
// Create Date: 12/01/2025 10:14:31 AM
// Module Name: Branch_Unit
//////////////////////////////////////////////////////////////////////////////////


module Branch_Unit(
    input branch,
    input [1:0] awpc,          // 01=MOV PC (Rm), 10=ADD PC (PC+Rm): ALUWritePC plain branch
    input [3:0] cond,
    input [31:0] PC,
    input [31:0] imm,
    input [31:0] Rm,
    input N,
    input Z,
    input C,
    input V,
    output reg branch_EX,
    output [31:0] PC_Branch,
    output exc_out,
    output bx_fault
    );

    // ALUWritePC -> BranchWritePC: plain branch to result<31:1>:'0' (bit0 cleared, no interworking)
    wire [31:0] awpc_sum    = PC + Rm + 32'd4;                                    // ADD PC,PC,Rm result (PC read = addr+4)
    wire [31:0] awpc_target = (awpc == 2'b10) ? {awpc_sum[31:1], 1'b0}            // ADD PC,PC,Rm
                                              : {Rm[31:1], 1'b0};                  // MOV PC,Rm
    assign PC_Branch = (|awpc) ? awpc_target
                     : &cond   ? {Rm[31:1], 1'b0} : (PC+imm) + 4;

    //If we are ever at FFFFFFFx then its an excep call
    assign exc_out = (|awpc) ? 1'b0 : (&cond ? (Rm[31:4] == 28'hFFFFFFF) : 1'b0);

    // ARMv6-M has no ARM state: a BX/BLX/interworking target with bit[0]==0 faults.
    assign bx_fault = (|awpc) ? 1'b0 : (branch & (&cond) & ~exc_out & ~Rm[0]);

    always @ (*) begin
        branch_EX = 0;
        if (|awpc) branch_EX = branch;   // ALU-write-PC: unconditional plain branch
        else begin
        // (removed) PC[31:1]==0 suppression: provably dead (branch_EX is
        // unconditionally reassigned below) and not architectural.
        if(exc_out) branch_EX = 0;
        else if (branch) begin
        case(cond)
            4'h0:   if(Z==1) branch_EX = 1;
            4'h1:   if(Z==0) branch_EX = 1;
            4'h2:   if(C==1) branch_EX = 1;
            4'h3:   if(C==0) branch_EX = 1;
            4'h4:   if(N==1) branch_EX = 1;
            4'h5:   if(N==0) branch_EX = 1;
            4'h6:   if(V==1) branch_EX = 1;
            4'h7:   if(V==0) branch_EX = 1;
            4'h8:   if(C==1 && Z==0) branch_EX = 1;
            4'h9:   if(C==0 || Z==1) branch_EX = 1;
            4'ha:   if(N==V) branch_EX = 1;
            4'hb:   if(N!=V) branch_EX = 1;
            4'hc:   if(Z==0 && N==V) branch_EX = 1;
            4'hd:   if(Z==1 || N!=V) branch_EX = 1;
            4'he:   branch_EX = 1;
            4'hf:   branch_EX = 1;
            default: branch_EX = 0;
         endcase
         end else branch_EX = 0;
        if (bx_fault) branch_EX = 1'b0;
        end
    end


endmodule
