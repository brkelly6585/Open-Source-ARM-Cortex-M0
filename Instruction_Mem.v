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
        Instructions[0] = 16'b00100_000_00000000; // MOV (Immediate) | MOVS R0, #0
        Instructions[1] = 16'b00100_001_00000001; // MOV (Immediate) | MOVS R1, #1
        Instructions[2] = 16'b010001000_0000_001; // ADD (Reg) | ADD R0, R1
        Instructions[3] = 16'b0100000000_001_000; // ANDS | ANDS R0, R1
        Instructions[4] = 16'b0100001111_001_110; // MVNS | MVNS R6, R1
        Instructions[5] = 16'b00010_00001_110_111; // ASRS (imm) | ASRS R7, R6, #1
        
    end
    
    always @ (posedge clk) begin
        if (~Addr[0])
            Instr = {Instructions[{Addr[31:1], 1'b1}], Instructions[{Addr[31:1], 1'b0}]};
        
    end
    
endmodule
