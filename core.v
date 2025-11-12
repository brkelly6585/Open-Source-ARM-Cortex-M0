`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 10/26/2025 05:12:19 PM
// Design Name: 
// Module Name: core
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


module core(

    );
    reg clk;
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end
    
    wire [31:0] PC_in, PC_IF, PC_ID, Instr_IF, Instr_ID;
    wire [31:0] Instruction;
    wire [31:0] Imm;
    wire [3:0] Rd_ID, Rm, Rn, Rd_EX;
    wire [31:0] Rn_ID, Rm_ID, Rn_EX, Rm_EX;
    
    wire [4:0] instr_check;
    wire [1:0] instr_step, step;
    
    assign PC_in = PC_IF + instr_step;
    
    assign instr_step = (instr_check == 5'b11101) ? 2'b10 : (instr_check[4:1] == 5'b1111) ? 2'b10 : 2'b01;
    
    assign instr_check = Instr_IF[15:11];
    
    program_counter PC(clk, PC_in, PC_IF);
    
    Instruction_Mem Instructio_Memory(clk, PC_IF, Instr_IF);
    
    IFID IFIDbuffer(clk, PC_IF, Instr_IF, PC_ID, Instr_ID);
    
    Instr_decode decoder(PC_ID[0], Instr_ID, Instruction, step, Imm, Rd_ID, Rn, Rm);
    
    Register_File reg_file(clk, we_WB, wd_WB, Rd_WB, Rn, Rm, Rn_ID, Rm_ID);
    
    IDEX IDEXbuffer(clk, Rd_ID, Rn_ID, Rm_ID, Rd_EX, Rn_EX, Rm_EX);
    
    initial begin
    #100
    $finish;
    end
    
endmodule
