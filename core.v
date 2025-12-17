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
    
    wire [31:0] PC_in, PC_IF, PC_ID, Instr_IF, Instr_ID, PC_Branch;
    wire [31:0] Instruction;
    wire [3:0] Rd_ID, Rm, Rn, Rd_EX, ALU_op_ID, ALU_op_EX, cond_EX;
    wire [31:0] Rn_ID, Rm_ID, Rn_EX, Rm_EX, Imm_ID, Imm_EX, ALU_in_n, ALU_in_m, ASPR;
    wire [31:0] wd_WB;
    
    wire[31:0] ALUdata, MEMdata;
    
    wire PC_EN, IFID_EN, IDEX_EN;
    wire branchX_ID, branchCond_ID, memread_ID, memwrite_ID, regwrite_ID, ALU_src_ID, wd_src_ID, flags_ID;
    wire memread_EX, memwrite_EX, regwrite_EX, ALU_src_EX, wd_src_EX, branch_EX, flags_EX;
    
    wire [4:0] instr_check;
    wire [1:0] instr_step;
    
    assign PC_in = branch_EX ? PC_Branch : PC_EN ? PC_IF + instr_step : PC_IF;
    
    assign instr_step = (instr_check == 5'b11101) ? 2'b10 : (instr_check[4:1] == 5'b1111) ? 2'b10 : 2'b01;
    
    assign instr_check = Instr_IF[15:11];
    
    program_counter PC(clk, PC_in, PC_IF);
    
    Instruction_Mem Instruction_Memory(clk, PC_IF, Instr_IF);
    
    IFID IFIDbuffer(clk, IFID_EN, branch_EX, PC_IF, Instr_IF, PC_ID, Instr_ID);
    
    Instr_decode decoder(PC_ID[0], Instr_ID, Instruction, Imm_ID, Rd_ID, Rn, Rm, 
                         ALU_op_ID, ALU_src_ID, flags_ID, memread_ID, memwrite_ID, regwrite_ID, wd_src_ID, branchCond_ID, branchX_ID, move_ID);
    
    Register_File reg_file(clk, regwrite_EX, wd_WB, Rd_EX, Rn, Rm, Rn_ID, Rm_ID);
    
    //Not implemented
    Hazard_Det hazard_det_unit(clk, PC_IF, memread_ID, memwrite_ID, PC_EN, IFID_EN, IDEX_EN);
    
    IDEX IDEXbuffer(clk, IDEX_EN, branch_EX, Rd_ID, Rn_ID, Rm_ID, Imm_ID,
                    ALU_op_ID, Rd, ALU_src_ID, memread_ID, memwrite_ID, regwrite_ID, wd_src_ID, branchCond_ID, branchX_ID, move_ID, flags_ID,
                    Rd_EX, Rn_EX, Rm_EX, Imm_EX,
                    ALU_op_EX, cond_EX, ALU_src_EX, memread_EX, memwrite_EX, regwrite_EX, wd_src_EX, branchCond_EX, branchX_EX, move_EX, flags_EX);
    
    
    
    assign ALU_in_m = ALU_src_EX ? Imm_EX : Rm_EX;
    
    assign ALU_in_n = move_EX ? 0 : Rn_EX;
    
    arthALU ALU(clk, ALU_op_EX, ALU_in_n, ALU_in_m, flags_EX, ALUdata, N, Z, C, V, APSR);
    
    Branch_Unit Branch(cond_EX, PC_IF, Imm_EX, N,Z,C,V, branch_EX, PC_Branch);
    
    //Implemented but not fully tested
    Data_Memory DataMem(clk, memread_EX, memwrite_EX, ALUdata, data_in, MEMdata);
    
    assign wd_WB = wd_src_EX ? MEMdata : ALUdata;
    
    initial begin
    #400
    $finish;
    end
    
endmodule
