`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 11/12/2025 05:54:23 AM
// Design Name: 
// Module Name: register32
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


module register32(
    input clk,
    input [31:0] D,
    input we,
    output [31:0] Q
    );
    
    always @ (posedge clk)
        if(we) Q <= D;
endmodule
