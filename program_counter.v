`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 10/26/2025 04:00:06 PM
// Design Name: 
// Module Name: program_counter
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


module program_counter(
    input clk, reset,
    input [31:0] PC_in,
    output reg [31:0] PC_out
    );
    
    always @ (negedge clk) begin
        if (!reset) PC_out <= 0;
        else begin
            PC_out <= PC_in;
        end
    end
    
endmodule
