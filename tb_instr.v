`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 10/26/2025 05:12:19 PM
// Design Name: 
// Module Name: tb_instr
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


module tb_instr(

    );
    reg clk;
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end
    
    wire [31:0] PC_in, PC_IF, PC_ID, Instr_IF, Instr_ID;
    wire [31:0] Instruction;
    wire [31:0] Imm;
    wire [3:0] Rd, Rm, Rn;
    wire cout;
    
    fullAdder PCadder(PC_IF, 1, cout, PC_in);
    
    program_counter PC(clk, PC_in, PC_IF);
    
    Instruction_Mem Instructio_Memory(clk, PC_IF, Instr_IF);
    
    IFID buffer(clk, PC_IF, Instr_IF, PC_ID, Instr_ID);
    
    Instr_decode decoder(clk, PC_ID[0], Instr_ID, Instruction, Imm, Rd, Rm, Rn);
    
    initial begin
    #100
    $finish;
    end
    
endmodule
