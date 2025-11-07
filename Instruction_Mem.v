`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 10/26/2025 03:57:37 PM
// Design Name: 
// Module Name: Instruction_Mem
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


module Instruction_Mem(
    input clk,
    input [31:0] Addr,
    output reg [31:0] Instr
    );
    
    integer i;
    
    reg [15:0] Instructions [0:255];
    
    initial begin
        for (i = 0; i< 256; i=i+1) begin
            Instructions[i] = 15'b0;
        end
    end
    
    initial begin
        //Instructions go here
        Instructions[0] = 16'hFF00;
        Instructions[1] = 16'h4800;
        Instructions[2] = 16'h19C2; // ADD R0, R2, R7
        Instructions[3] = 16'h1CCC; // ADD R1, R4, 3
        Instructions[4] = 16'h9500; 
        Instructions[5] = 16'hF000;
        Instructions[6] = 16'hEF00;
        Instructions[7] = 16'h6600;
        Instructions[8] = 16'h0880;
        Instructions[9] = 16'h6007;
    end
    
    always @ (posedge clk) begin
        if (~Addr[0])
            Instr = {Instructions[{Addr[31:1], 1'b1}], Instructions[{Addr[31:1], 1'b0}]};
        
    end
    
endmodule
