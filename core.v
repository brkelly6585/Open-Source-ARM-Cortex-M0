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
        output [31:0] addr_o, wdata_o,

        output [31:0] ppb_addr_o,
        output [31:0] ppb_wdata_o,
        output ppb_wr_o,
        output ppb_rd_o,
        input [31:0] ppb_rdata_i,

        output exc_taken_o,
        output [5:0] exc_taken_num_o,
        output exc_return_o,
        output [5:0] exc_return_num_o,
        output svcall_req_o,
        output fault_req_o,
        output [5:0]  IPSR_o,
        output PRIMASK_o,
        output core_halted_o,

        input int_pend_i,
        input [5:0] int_pend_num_i,
        input SLEEPONEXIT_i,
        input SLEEPDEEP_i,
        input SEVONPEND_i
    );
    
    // IF
    wire [31:0] PC_in, PC_IF,  Instr_IF, Instr_ID, PC_Branch;
    wire [31:0] Instruction;
    
    //ID
    wire [1:0]  size_ID, type_ID, barrier_ID;
    wire [3:0]  Rd_ID, Rm, Rn,  ALU_op_ID, cond_ID;
    wire [31:0] PC_ID, Rn_ID, Rm_ID, Rt_ID, Addr_ID, Imm_ID;
    
    //EX
    wire [1:0] size_EX, type_EX, barrier_EX;
    wire [3:0] Rd_EX, ALU_op_EX, cond_EX,  MEMRd, MEMRm, flags_next;
    wire [31:0] PC_EX, Rn_EX, Rm_EX, Rt_EX, APSR, Addr_EX, Imm_EX;
    wire [31:0] ALUdata, MEMdata, EXTdata, REVdata, SRdata, wd_WB;
    
    // Data Mem
    wire dm_read_req_i, dm_write_req_i, dm_ready_o;
    wire [1:0] dm_size_i;
    wire [31:0] dm_addr_i, dm_wdata_i, dm_data_o;

    // Exception
    wire exc_read_req, exc_write_req, exc_ready, exc_active, exc_flush, exc_PC_valid;
    wire [1:0] exc_size;
    wire [31:0] exc_addr, exc_wdata, exc_rdata, exc_PC_target;

    wire b_exc_o, dm_exc_o;

    // Exception - Reg File
    wire rf_we_exc;
    wire [3:0] rf_addr_exc;
    wire [31:0] rf_wdata_exc, R0_v, R1_v, R2_v, R3_v, R12_v, SP_v, LR_v;
    
    wire ipsr_we, apsr_we;
    wire [5:0] ipsr_wdata_hw;
    wire [3:0] apsr_wdata_hw;

    // Control
    wire PC_EN, if_ready, if_stall;
    wire memread_ID, memwrite_ID, regwrite_ID, ALU_src_ID, wd_src_ID;
    wire flags_ID, sign_ID, extend_ID, reverse_ID, sr_ID, branchC_ID, move_ID;
    wire memread_EX, memwrite_EX, regwrite_EX, ALU_src_EX, wd_src_EX, branch_EX;
    wire flags_EX, sign_EX, extend_EX, reverse_EX, sr_EX, branchC_EX, move_EX;
    wire N, Z, C, V;
    wire [4:0] instr_check;
    wire [2:0] instr_step;
    wire global_stall, haz_stall, consumed_ID;
    wire ld_en, ld_stall, barrier_hold, barrier_flush;


    //////////////////////////////////////////////
    // Instruction Fetch stage
    //////////////////////////////////////////////
    
    // Stalls + PC
    assign global_stall = ld_stall | barrier_hold | exc_active;

    assign PC_in = exc_PC_valid ? exc_PC_target :
                   branch_EX    ? PC_Branch     :
                   (if_ready & ~global_stall) ? PC_IF + instr_step :
                                                PC_IF;

    assign instr_step  = (instr_check == 5'b11101)        ? 3'b100 :
                         (instr_check[4:1] == 4'b1111)    ? 3'b100 : 3'b010;
    assign instr_check = PC_IF[1] ? Instr_IF[31:27] : Instr_IF[15:11];

    program_counter PC(HCLK, HRESETn, PC_in, PC_IF);

    
    AHB_Arbitration ARB(
        .clk(HCLK), .rst_n(HRESETn),

        .if_PC_i(PC_IF),
        .branch_addr_i(PC_Branch),
        .if_read_req_i(branch_EX | ~global_stall),
        .fetch(PC_IF[1]),
        .branch(branch_EX),
        .if_data_o(Instr_IF),
        .if_ready_o(if_ready),
        .if_stall_o(if_stall),

        .dm_addr_i(dm_addr_i),
        .dm_data_i(dm_wdata_i),
        .dm_read_req_i(dm_read_req_i),
        .dm_write_req_i(dm_write_req_i),
        .dm_size_i(dm_size_i),
        .dm_data_o(dm_data_o),
        .dm_ready_o(dm_ready_o),

        .ahb_data_i(rdata_i),
        .ahb_ready_i(ready_i),
        .ahb_addr_o(addr_o),
        .ahb_size_o(size_o),
        .ahb_write_req_o(write_req_o),
        .ahb_read_req_o(read_req_o),
        .ahb_data_o(wdata_o),

        .exc_addr_i(exc_addr),
        .exc_data_i(exc_wdata),
        .exc_read_req_i(exc_read_req),
        .exc_write_req_i(exc_write_req),
        .exc_size_i(exc_size),
        .exc_ready_o(exc_ready),
        .exc_data_o(exc_rdata)
    );

    IFID IFIDbuffer(HCLK,
                    (if_ready & ~global_stall & ~haz_stall),
                    ~global_stall & ~haz_stall,
                    branch_EX | ~HRESETn | exc_flush,
                    PC_IF, Instr_IF,
                    consumed_ID, PC_ID, Instr_ID);
    
    //////////////////////////////////////////////
    // Instruction Decode stage
    //////////////////////////////////////////////

    Instr_decode decoder(PC_ID[1], Instr_ID, Instruction, Imm_ID, Rd_ID, Rn, Rm, cond_ID,
                         ALU_op_ID, size_ID, type_ID, barrier_ID, ALU_src_ID, flags_ID,
                         memread_ID, memwrite_ID, regwrite_ID, wd_src_ID, branchC_ID,
                         move_ID, sign_ID, extend_ID, reverse_ID, sr_ID);

    Register_File reg_file(
        .clk(HCLK),
        .we_WB(ld_en | regwrite_EX),
        .wd_WB(wd_WB),
        .PC_in(PC_in),
        .Rd_WB(ld_en ? MEMRd : Rd_EX),
        .Rn(Rn),
        .Rm(|type_EX ? MEMRm : Rm),
        .Rt(Rd_ID),
        .Rn_o(Rn_ID),
        .Rm_o(Rm_ID),
        .Rt_o(Rt_ID),
        .we_exc(rf_we_exc),
        .Rd_exc(rf_addr_exc),
        .wd_exc(rf_wdata_exc),
        .R0(R0_v), .R1(R1_v), .R2(R2_v), .R3(R3_v),
        .R12(R12_v), .SP(SP_v), .LR(LR_v)
    );


    AGU agu(ALU_src_ID, (|type_ID), Rn_ID, Rm_ID, Imm_ID, Addr_ID);

    Hazard_Det hazard_det_unit(memread_EX, Rd_EX, Rn, Rm, haz_stall);

    IDEX IDEXbuffer(HCLK, ~global_stall, ~HRESETn|haz_stall,
        PC_ID, Rd_ID, Rn_ID, Rm_ID, Rt_ID, Imm_ID, Addr_ID,
        ALU_op_ID, cond_ID, size_ID, type_ID, barrier_ID,
        ALU_src_ID, memread_ID, memwrite_ID, regwrite_ID, wd_src_ID,
        branchC_ID, move_ID, flags_ID, sign_ID, extend_ID, reverse_ID, sr_ID,
        PC_EX, Rd_EX, Rn_EX, Rm_EX, Rt_EX, Imm_EX, Addr_EX,
        ALU_op_EX, cond_EX, size_EX, type_EX, barrier_EX,
        ALU_src_EX, memread_EX, memwrite_EX, regwrite_EX, wd_src_EX,
        branchC_EX, move_EX, flags_EX, sign_EX, extend_EX, reverse_EX, sr_EX);

    //////////////////////////////////////////////
    // Execution stage
    //////////////////////////////////////////////

    Extender EXT(HCLK, sign_EX, size_EX[0], Rm_EX[15:0], EXTdata);
    Reverser REV(HCLK, reverse_EX, sign_EX, size_EX[1], Rm_EX, REVdata);

    Barrier_Unit BU(HCLK, HRESETn, barrier_EX, ready_i, ld_en, write_reg_o, barrier_hold, barrier_flush);

    arthALU ALU(HCLK, ALU_op_EX, move_EX ? 32'b0 : Rn_EX,
                ALU_src_EX ? Imm_EX : Rm_EX, flags_EX, move_EX,
                ALUdata, N, Z, C, V, flags_next);

    Special_Register_File SR(
        .HCLK(HCLK), .HRESETn(HRESETn),
        .flags_EX(flags_EX),
        .flags(flags_next),
        .sr_op(sr_EX),
        .mrs(regwrite_EX),
        .ipsr_we(ipsr_we),
        .ipsr_data(ipsr_wdata_hw),
        .apsr_we(apsr_we),
        .apsr_data(apsr_wdata_hw),
        .SYSm(Imm_EX[7:0]),
        .wdata(Rn_EX),
        .rdata_o(SRdata),
        .APSR_o(APSR),
        .PRIMASK_o(PRIMASK_o),
        .IPSR_o(IPSR_o)
    );

    Branch_Unit Branch(branchC_EX, cond_EX, PC_EX, Imm_EX, Rm_EX, N, Z, C, V,
                       branch_EX, PC_Branch, b_exc_o);

    Data_Memory DataMem(HCLK, HRESETn,
        Addr_EX,
        |type_EX ? Rm_ID   : Rt_EX,
        Rd_EX, size_EX, sign_EX,
        memread_EX, memwrite_EX, 1'b1,
        type_EX, Imm_EX[8:0],
        dm_data_o, dm_ready_o,
        dm_addr_i, dm_wdata_i, dm_read_req_i, dm_write_req_i, dm_size_i,
        MEMdata, MEMRd, MEMRm, ld_en, ld_stall, dm_exc_o);

    assign wd_WB = (sr_EX & regwrite_EX) ? SRdata :
                   (wd_src_EX || ld_en)  ? MEMdata :
                   extend_EX  ? EXTdata :
                   reverse_EX ? REVdata :
                                ALUdata;

    Exception_Unit EXC(
        .clk(HCLK), .rst_n(HRESETn),

        .int_pend_i(int_pend_i),
        .int_pend_num_i(int_pend_num_i),
        .exc_taken_o(exc_taken_o),
        .exc_taken_num_o(exc_taken_num_o),
        .exc_return_o(exc_return_o),
        .exc_return_num_o(exc_return_num_o),

        .branch_exc_in(b_exc_o),
        .ldm_exc_in(dm_exc_o),
        .IPSR_i(IPSR_o),
        .return_PC_i(PC_ID),       // next-to-execute instruction
        .APSR_i(APSR),
        .R0_i(R0_v), .R1_i(R1_v), .R2_i(R2_v),
        .R3_i(R3_v), .R12_i(R12_v), .LR_i(LR_v),
        .SP_i(SP_v),

        .exc_active_o(exc_active),
        .exc_flush_o(exc_flush),
        .exc_PC_valid_o(exc_PC_valid),
        .exc_PC_target_o(exc_PC_target),

        .rf_we_o(rf_we_exc),
        .rf_addr_o(rf_addr_exc),
        .rf_wdata_o(rf_wdata_exc),

        .ipsr_we_o(ipsr_we),
        .ipsr_wdata_o(ipsr_wdata_hw),
        .apsr_we_o(apsr_we),
        .apsr_wdata_o(apsr_wdata_hw),

        .exc_read_req_o(exc_read_req),
        .exc_write_req_o(exc_write_req),
        .exc_size_o(exc_size),
        .exc_addr_o(exc_addr),
        .exc_wdata_o(exc_wdata),
        .exc_rdata_i(exc_rdata),
        .exc_ready_i(exc_ready)
    );

    
    assign ppb_addr_o  = dm_addr_i;
    assign ppb_wdata_o = dm_wdata_i;
    assign ppb_wr_o    = dm_write_req_i & (dm_addr_i[31:12] == 20'hE000E);
    assign ppb_rd_o    = dm_read_req_i  & (dm_addr_i[31:12] == 20'hE000E);

endmodule