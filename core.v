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
        input HCLK, HRESETn,
        
        input ready_i, error_i,
        input [31:0] rdata_i,
        
        output read_req_o, write_req_o,
        output [1:0] size_o,
        output [31:0] addr_o, wdata_o
    );
    
    wire [31:0] PC_in, PC_IF, PC_ID, PC_EX, Instr_IF, Instr_ID, PC_Branch;
    wire [31:0] Instruction;
    wire [3:0] Rd_ID, Rm, Rn, Rd_EX, ALU_op_ID, ALU_op_EX, cond_EX, MEMRd, MEMRm, cond_ID;
    wire [31:0] Rn_ID, Rm_ID, Rt_ID, Addr_ID, Rn_EX, Rm_EX, Rt_EX, Imm_ID, Imm_EX, ALU_in_n, ALU_in_m, ASPR, Addr_EX, Maddr_o;
    wire [31:0] wd_WB;
    
    wire [1:0] size_ID, type_ID, size_EX, type_EX, Msize_o, barrier_ID, barrier_EX;
    
    wire[31:0] ALUdata, MEMdata, EXTdata, REVdata;
    
    wire Mread_req, Iread_req;
    wire PC_EN, IFID_EN, IDEX_EN;
    wire branchX_ID, branchCond_ID, memread_ID, memwrite_ID, regwrite_ID, ALU_src_ID, wd_src_ID, flags_ID, sign_ID, extend_ID, reverse_ID;
    wire memread_EX, memwrite_EX, regwrite_EX, ALU_src_EX, wd_src_EX, branch_EX, flags_EX, sign_EX, extend_EX, reverse_EX;
    
    wire [4:0] instr_check;
    wire [1:0] instr_step;
    
    wire global_stall, haz_stall, AHB_stall;
    
    assign global_stall = ld_stall | barrier_hold;
    
    assign PC_in = branch_EX ? PC_Branch : ~global_stall ? PC_IF + instr_step : PC_IF;
    
    assign instr_step = (instr_check == 5'b11101) ? 2'b10 : (instr_check[4:1] == 5'b1111) ? 2'b10 : 2'b01;
    
    assign instr_check = Instr_IF[15:11];
    
    //assign addr_o = ld_stall ? Maddr_o : PC_IF;
    //assign size_o = ld_stall ? Msize_o : 2'b11;
    //assign read_req_o = ld_stall ? Mread_req : Iread_req;
    
    program_counter PC(HCLK, HRESETn, PC_in, PC_IF);
    
    Instruction_Mem Instruction_Memory(HCLK, PC_IF, Instr_IF);
    //Instruction_Fetch Instruction_Mem(HCLK, HRESETn, ld_stall, 
    //Iread_req, rdata_i, ready_i,
    //Fetch_stall, Instr_IF);
    
    IFID IFIDbuffer(HCLK, ~global_stall&~haz_stall, branch_EX|~HRESETn, PC_IF, Instr_IF, PC_ID, Instr_ID);
    
    Instr_decode decoder(PC_ID[0], Instr_ID, Instruction, Imm_ID, Rd_ID, Rn, Rm, cond_ID, 
                         ALU_op_ID, size_ID, type_ID, barrier_ID, ALU_src_ID, flags_ID, memread_ID, memwrite_ID, regwrite_ID, wd_src_ID, branchC_ID, move_ID, sign_ID, extend_ID, reverse_ID);
    
    Register_File reg_file(HCLK, ld_en|regwrite_EX, wd_WB, PC_in, ld_en ? MEMRd : Rd_EX, Rn, |type_EX ? MEMRm : Rm, Rd_ID, Rn_ID, Rm_ID, Rt_ID);
    
    AGU agu(ALU_src_ID, (|type_ID), Rn_ID, Rm_ID, Imm_ID, Addr_ID);
    
    Hazard_Det hazard_det_unit(memread_EX, Rd_EX, Rn, Rm, haz_stall);
    
    IDEX IDEXbuffer(HCLK, ~global_stall, ~HRESETn|haz_stall, PC_ID, Rd_ID, Rn_ID, Rm_ID, Rt_ID, Imm_ID, Addr_ID,
                    ALU_op_ID, cond_ID, size_ID, type_ID, barrier_ID, ALU_src_ID, memread_ID, memwrite_ID, regwrite_ID, wd_src_ID, branchC_ID, move_ID, flags_ID, sign_ID, extend_ID, reverse_ID,
                    PC_EX, Rd_EX, Rn_EX, Rm_EX, Rt_EX, Imm_EX, Addr_EX,
                    ALU_op_EX, cond_EX, size_EX, type_EX, barrier_EX, ALU_src_EX, memread_EX, memwrite_EX, regwrite_EX, wd_src_EX, branchC_EX, move_EX, flags_EX, sign_EX, extend_EX, reverse_EX);
    
    
    
    assign ALU_in_m = ALU_src_EX ? Imm_EX : Rm_EX;
    
    assign ALU_in_n = move_EX ? 0 : Rn_EX;
    
    Extender EXT(clk, extend_EX, sign_EX, size_EX[0], Rm_EX, EXTdata);
    Reverser REV(clk, reverse_EX, sign_EX, size_EX[1], Rm_EX, REVdata);
    
    Barrier_Unit BU(HCLK, HRESETn, barrier, ready_i, ld_en, write_reg_o, barrier_hold, barrier_flush); 
    
    arthALU ALU(HCLK, ALU_op_EX, ALU_in_n, ALU_in_m, flags_EX, ALUdata, N, Z, C, V, APSR);
    
    Branch_Unit Branch(branchC_EX, cond_EX, PC_EX, Imm_EX, Rm_EX, N,Z,C,V, branch_EX, PC_Branch);
    
    
    Data_Memory DataMem(HCLK, HRESETn, |type_EX ? Addr_ID : Addr_EX, |type_EX ? Rm_EX : Rt_EX, Rd_EX, size_EX, memread_EX, memwrite_EX, 1'b1,
    type_EX, Imm_EX,
    rdata_i, ready_i, addr_o, wdata_o, read_req_o, write_req_o, size_o,
    MEMdata, MEMRd, MEMRm, ld_en, ld_stall);
    
    assign wd_WB = wd_src_EX || ld_en ? MEMdata : (extend_EX ? EXTdata : (reverse_EX ? REVdata : ALUdata));
    
    
endmodule
