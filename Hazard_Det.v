`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 12/01/2025 05:40:44 AM
// Design Name: 
// Module Name: Hazard_Det
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


module Hazard_Det(
    input memread_EX,
    input [3:0] Rd_EX,
    input [3:0] Rn_ID,
    input [3:0] Rm_ID,
    output haz_stall
    );
    
    
    assign haz_stall = memread_EX && (Rd_EX != 4'b0000) && ((Rd_EX == Rn_ID) || (Rd_EX == Rm_ID));
    
endmodule
