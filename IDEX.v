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
    input [3:0] Rd_ID,
    input [31:0] Rn_ID,
    input [31:0] Rm_ID,
    output reg [3:0] Rd_EX,
    output reg [31:0] Rn_EX,
    output reg [31:0] Rm_EX
    );
    
    always @ (negedge clk) begin
        Rd_EX <= Rd_ID;
        Rn_EX <= Rn_ID;
        Rm_EX <= Rm_ID;
    end
endmodule
