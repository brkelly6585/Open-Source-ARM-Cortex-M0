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
    output reg [31:0] Rt_o
    );
    
    // Test setup so registers can be used from the start
    reg [31:0] Registers[0:14];
    integer i;
    
    
    initial begin
        for (i=0; i<13; i=i+1)
            Registers[i] = 0;
    end
    
    
    always@(negedge clk) begin
        if(we_WB>0)
        begin
            Registers[Rd_WB] <= wd_WB;
        end
    end
   
    always@(*) begin
        Rn_o = (we_WB && Rn == Rd_WB) ? wd_WB : Rn==15 ? PC_in : Registers[Rn];
        Rm_o = (we_WB && Rm == Rd_WB) ? wd_WB : Rn==15 ? PC_in : Registers[Rm];
        Rt_o = (we_WB && Rt == Rd_WB) ? wd_WB : Rn==15 ? PC_in : Registers[Rt];
    
    end 
    
endmodule
