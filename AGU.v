`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 02/09/2026 01:10:41 PM
// Design Name: 
// Module Name: AGU
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


module AGU(
    input src,
    input type,
    input [31:0] Rn,
    input [31:0] Rm,
    input [31:0] Imm,
    output [31:0] Addr
    );
    
    assign Addr = type ? Rn : src ? Rn + Imm : Rn + Rm;
    
endmodule
