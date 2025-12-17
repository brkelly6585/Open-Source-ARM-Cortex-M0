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
            Instructions[i] = 16'hFFFF;
        end
    end
    
    initial begin
        //Instructions go here
        /* Basic Test
        Instructions[0] = 16'b00100_000_00000000; // MOV (Immediate) | MOVS R0, #0
        Instructions[1] = 16'b00100_001_00000001; // MOV (Immediate) | MOVS R1, #1
        Instructions[2] = 16'b01000100_0_0001_000; // ADD (Reg) | ADD R0, R1
        Instructions[3] = 16'b0100000000_001_000; // ANDS | ANDS R0, R1
        //Instructions[4] = 16'b01001_011_00000001; // LDR (Lit) | LDR R3, 1
        //Instructions[5] = 16'b10010_001_00000001; // STR (Imm) | STR R1, 1
        Instructions[4] = 16'b0100001111_001_110; // MVNS | MVNS R6, R1
        Instructions[5] = 16'b00010_00001_110_111; // ASRS (imm) | ASRS R7, R6, #1
        Instructions[6] = 16'b00100_010_11110000; // MOV (Immediate) | MOVS R2, #240
        Instructions[7] = 16'b0100001100_001_010; // ORRS | ORRS R2, R1
        Instructions[8] = 16'b0100001110_001_010; // BICS | BICS R2, R1
        Instructions[9] = 16'b0100000001_001_000; // EORS | EORS R0, R1
        Instructions[10] = 16'b00000_00011_001_100; // LSLS (imm) | LSLS R4, R1, #3
        Instructions[11] = 16'b00001_00010_100_101; // LSRS (imm) | LSRS R5, R4, #2
        Instructions[12] = 16'b0100001101_100_101; // MULS | MULS R5, R4
        Instructions[13] = 16'b0001101_001_101_011; // SUBS (reg) | SUBS R3, R5, R1
        Instructions[14] = 16'b0100001001_011_100; // RSBS | RSBS R4, R3, #0
        */
        
        /* Flag Test */
        Instructions[0] = 16'b00100_000_00000000; // MOV (Immediate) | MOVS R0, #0
        Instructions[1] = 16'b0100001111_000_001; // MVNS | MVNS R1, R0
        Instructions[2] = 16'b00001_00001_001_010; // LSRS (imm) | LSRS R2, R1, #1
        Instructions[3] = 16'b00110_010_00000001; // ADD (Imm) | ADDS R2, #1
        
    end
    
    always @ (posedge clk) begin
        if (~Addr[0])
            Instr = {Instructions[{Addr[31:1], 1'b1}], Instructions[{Addr[31:1], 1'b0}]};
        
    end
    
endmodule
