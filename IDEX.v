`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 11/12/2025 05:07:48 AM
// Design Name: 
// Module Name: IDEX
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module IDEX(
    input clk,
    input IDEX_EN,
    input [3:0] Rd_ID,
    input [31:0] Rn_ID,
    input [31:0] Rm_ID,
    input [31:0] Imm_ID,
    input [3:0] ALU_op_ID, cond_ID,
    input ALU_src_ID, memread_ID, memwrite_ID, regwrite_ID, wd_src_ID, branchCond_ID, branchX_ID, move_ID, flags_ID,
    
    output reg [3:0] Rd_EX,
    output reg [31:0] Rn_EX,
    output reg [31:0] Rm_EX,
    output reg [31:0] Imm_EX,
    output reg [3:0] ALU_op_EX, cond_EX,
    output reg ALU_src_EX, memread_EX, memwrite_EX, regwrite_EX, wd_src_EX, branchCond_EX, branchX_EX, move_EX, flags_EX,
    );
    
    always @ (negedge clk) begin
        if(IDEX_EN) begin
            Rd_EX <= Rd_ID;
            Rn_EX <= Rn_ID;
            Rm_EX <= Rm_ID;
            Imm_EX <= Imm_ID;
            ALU_op_EX <= ALU_op_ID;
            ALU_src_EX <= ALU_src_ID;
            memread_EX <= memread_ID;
            memwrite_EX <= memwrite_ID;
            regwrite_EX <= regwrite_ID;
            wd_src_EX <= wd_src_ID;
            branchCond_EX <= branchCond_ID;
            branchX_EX <= branchX_ID;
            move_EX <= move_ID;
            flags_EX <= flags_ID;
            cond_EX <= cond_ID;
        end
    end
endmodule
