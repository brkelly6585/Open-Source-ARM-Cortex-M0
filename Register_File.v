`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 11/12/2025 05:07:48 AM
// Design Name: 
// Module Name: Register_File
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


module Register_File(
    input clk,
    input we_WB,
    input [31:0] wd_WB,
    input [31:0] PC_in,
    input [3:0] Rd_WB,
    input [3:0] Rn,
    input [3:0] Rm,
    input [3:0] Rt,
    output reg [31:0] Rn_o,
    output reg [31:0] Rm_o,
    output reg [31:0] Rt_o,
    
    input we_exc,
    input [3:0] Rd_exc,
    input [31:0] wd_exc,
    output [31:0] R0, R1, R2, R3, R12, SP, LR
    );
    
    // Test setup so registers can be used from the start
    reg [31:0] Registers[0:14];
    integer i;
    
    assign R0 = Registers[0];
    assign R1 = Registers[1];
    assign R2 = Registers[2];
    assign R3 = Registers[3];
    assign R12 = Registers[12];
    assign SP = Registers[13];
    assign LR = Registers[14];
    
    initial begin
        for (i=0; i<15; i=i+1)
            Registers[i] = 0;
    end
    
    
    
    always@(negedge clk) begin
        if (we_exc) Registers[Rd_exc] <= wd_exc; else if (we_WB) Registers[Rd_WB] <= wd_WB;
    end
   
    always@(*) begin
        Rn_o = (we_exc && Rn == Rd_exc) ? wd_exc : (we_WB && Rn == Rd_WB) ? wd_WB : Rn==15 ? PC_in : Registers[Rn];
        Rm_o = (we_exc && Rm == Rd_exc) ? wd_exc : (we_WB && Rm == Rd_WB) ? wd_WB : Rm==15 ? PC_in : Registers[Rm];
        Rt_o = (we_exc && Rt == Rd_exc) ? wd_exc : (we_WB && Rt == Rd_WB) ? wd_WB : Rt==15 ? PC_in : Registers[Rt];
    
    end 
    
endmodule
