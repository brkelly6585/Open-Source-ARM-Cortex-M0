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
    input [3:0] Rd_WB,
    input [3:0] Rn,
    input [3:0] Rm,
    output reg [31:0] Rn_Out,
    output reg [31:0] Rm_Out
    );
    
    // Test setup so registers can be used from the start
    reg [31:0] Registers[0:12];
    integer i;
    
    initial begin
        for (i=0; i<16; i=i+1)
            Registers[i] = i;
    end
    
    
    always@(negedge clk) begin
        if(we_WB>0)
        begin
            Registers[Rd_WB] = wd_WB;
        end
    end
    
    always@(posedge clk) begin
        Rn_Out = Registers[Rn];
        Rm_Out = Registers[Rm];
    
    end
    
    /*
    wire [31:0] reg_Q [15:0];
    wire [15:0] write_sel;
    
    integer i;
    
    assign write_sel = 15'd1 << Rd_WB;
    
    register32 R0 (clk, wd_WB, write_sel[0], reg_Q[0]);
    register32 R1 (clk, wd_WB, write_sel[1], reg_Q[1]);
    register32 R2 (clk, wd_WB, write_sel[2], reg_Q[2]);
    register32 R3 (clk, wd_WB, write_sel[3], reg_Q[3]);
    register32 R4 (clk, wd_WB, write_sel[4], reg_Q[4]);
    register32 R5 (clk, wd_WB, write_sel[5], reg_Q[5]);
    register32 R6 (clk, wd_WB, write_sel[6], reg_Q[6]);
    register32 R7 (clk, wd_WB, write_sel[7], reg_Q[7]);
    register32 R8 (clk, wd_WB, write_sel[8], reg_Q[8]);
    register32 R9 (clk, wd_WB, write_sel[9], reg_Q[9]);
    register32 R10 (clk, wd_WB, write_sel[10], reg_Q[10]);
    register32 R11 (clk, wd_WB, write_sel[11], reg_Q[11]);
    register32 R12 (clk, wd_WB, write_sel[12], reg_Q[12]);
    register32 SP (clk, wd_WB, write_sel[13], reg_Q[13]);
    register32 LR (clk, wd_WB, write_sel[14], reg_Q[14]);
    register32 PC (clk, wd_WB, write_sel[15], reg_Q[15]);
    
    always @ (posedge clk) begin
        Rn_ID <= reg_Q[Rn];
        Rm_ID <= reg_Q[Rm];
    end
    */
    
    
endmodule
