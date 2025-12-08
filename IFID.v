`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 10/26/2025 04:04:00 PM
// Design Name: 
// Module Name: IFID
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


module IFID(
    input clk,
    input IFID_EN,
    input [31:0] PC_in,
    input [31:0] Instr_in,
    output reg [31:0] PC_out,
    output reg [31:0] Instr_out
    );
    
    always @ (negedge clk)
    begin
        if (IFID_EN) begin
            PC_out <= PC_in;
            Instr_out <= Instr_in;
        end
        else begin
            Instr_out <= Instr_out;
            PC_out <= PC_out;
        end
        
    end
endmodule
