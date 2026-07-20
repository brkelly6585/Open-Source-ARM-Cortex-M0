`timescale 1ns / 1ps
// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2025-2026 Dylan Thornburg and Bryce Kelly
//
// This file is part of the Open-Source ARM Cortex-M0 project.
// Licensed under the GNU General Public License v3.0 or later.
// See the LICENSE file at the root of this repository.
//////////////////////////////////////////////////////////////////////////////////
// Create Date: 10/26/2025 05:12:19 PM
// Module Name: core
// Description: ARMv6-M (Cortex-M0) processor core. Three-stage pipeline with an
// AHB-Lite bus interface, timed to match the Cortex-M0 TRM cycle counts.
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
    wire [31:0] Rmulti_ID;
    wire dm_sp_we; wire [31:0] dm_sp_data; wire [3:0] dm_base_reg;
    wire dm_grant;
    wire dm_bus_error, exc_bus_error;
    reg  bus_fault_r;
    wire exc_sp_psp_w;
    wire [1:0]  CONTROL_v;   // CONTROL register from SR (bit1 = SPSEL)
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
    wire bx_fault;
    // Unaligned access: word access with Addr[1:0]!=0 or halfword with Addr[0]!=0.
    // Only single (non-multi) accesses to non-PPB space. A misaligned access to
    // mapped SRAM still completes (memory ignores low bits), so unlike an
    // unmapped bus error this frees the bus and the fault can be taken cleanly.
    wire align_fault = (memread_EX | memwrite_EX) & ~ppb_dm_sel & ~(|type_EX)
                       & ((size_EX == 2'b10 & (|Addr_EX[1:0])) | (size_EX == 2'b01 & Addr_EX[0]));

    // Exception - Reg File
    wire rf_we_exc;
    wire [3:0] rf_addr_exc;
    wire [31:0] rf_wdata_exc, R0_v, R1_v, R2_v, R3_v, R12_v, SP_v, LR_v;
    wire [31:0] MSP_v, PSP_v;
    // MSR MSP(SYSm=8)/PSP(SYSm=9),<Rn>: write the specific stack pointer.
    wire msr_msp_we = sr_EX & ~regwrite_EX & (Imm_EX[7:0] == 8'd8);
    wire msr_psp_we = sr_EX & ~regwrite_EX & (Imm_EX[7:0] == 8'd9);

    wire ipsr_we, apsr_we;
    wire [5:0] ipsr_wdata_hw;
    wire [3:0] apsr_wdata_hw;

    // Control
    wire PC_EN, if_ready, if_stall, if_word_valid;
    wire memread_ID, memwrite_ID, regwrite_ID, ALU_src_ID, wd_src_ID;
    wire flags_ID, sign_ID, extend_ID, reverse_ID, sr_ID, branchC_ID, move_ID;
    wire cps_ID, cps_EX;
    wire svc_ID, svc_EX;
    wire bkpt_ID, bkpt_EX;
    wire udf_ID, udf_EX;
    wire [1:0] awpc_ID, awpc_EX;
    wire memread_EX, memwrite_EX, regwrite_EX, ALU_src_EX, wd_src_EX, branch_EX;
    wire flags_EX, sign_EX, extend_EX, reverse_EX, sr_EX, branchC_EX, move_EX;
    wire N, Z, C, V;
    wire [4:0] instr_check;
    wire [2:0] instr_step;
    wire global_stall, haz_stall, consumed_ID;
    wire ld_en, ld_stall, barrier_hold, barrier_flush;

    // PPB (System Control Space, 0xE000Exxx) data-access completion.
    // The address decoder routes the PPB region to the AHB default slave, which
    // returns ERROR (never OKAY-ready), so a PPB load/store issued to the bus would
    // hang the LSU. PPB registers are serviced locally by NVIC/SCB/SysTick over the
    // ppb_* side channel: keep PPB accesses off the AHB and complete them in one
    // cycle. Reads feed ppb_rdata_i straight into the load-writeback path; the read
    // strobe ppb_rd_o is asserted on completion (below) so SysTick's COUNTFLAG
    // clear-on-read lines up with the cycle the value is actually sampled.
    // PPB side-channel select: gate on the DM transaction address (addr_o = base_addr_r,
    // registered/latched in SINGLE) rather than the EX-stage memread flag, which can drop
    // mid-transaction and let the AHB read to the unmapped PPB region hang. addr_o is 0 when
    // Data_Memory is idle, so this is 1 only during an actual PPB load/store.
    wire ppb_dm_sel = (dm_addr_i[31:12] == 20'hE000E);


    //////////////////////////////////////////////
    // Instruction Fetch stage
    //////////////////////////////////////////////

    // Stalls + PC
    // SVC: drive the synchronous SVCall request, and hold the pipeline while the
    // request propagates (SCB -> NVIC -> exception unit) so the return address
    // latched by the exception unit is the instruction right after the SVC.
    // SVC escalation: an SVC that cannot enter SVCall (executed in Handler mode,
    // or with PRIMASK set) escalates to HardFault instead. Uses the core's local
    // IPSR/PRIMASK (an SVC from Thread with interrupts enabled takes SVCall
    // normally). The fully-precise rule also compares the running handler's
    // configured priority against SVCall's; that extra case only differs for the
    // pathological config of a handler at numerically lower priority than SVCall.
    wire   svc_escalate = svc_EX & ((|IPSR_o) | PRIMASK_o);
    // A data-side AHB error (load/store to an unmapped/faulting address) raises a
    // HardFault.  The pulse is latched and held (freezing the pipeline via svc_hold)
    // until the exception is taken, so the fault is not lost and the LSU does not hang.
    always @(posedge HCLK or negedge HRESETn) begin
        if (!HRESETn)          bus_fault_r <= 1'b0;
        else if (dm_bus_error | exc_bus_error) bus_fault_r <= 1'b1;
        else if (exc_active)   bus_fault_r <= 1'b0;
    end
    wire bus_fault = dm_bus_error | exc_bus_error | bus_fault_r;

    // EXC_RETURN validation: on ARMv6-M only 0xFFFFFFF1, 0xFFFFFFF9 and 0xFFFFFFFD are
    // legal return tokens (low nibble 1/9/D).  b_exc_o/dm_exc_o already qualify the top
    // 28 bits as 0xFFFFFFF; here we check the nibble.  A return with any other nibble is
    // an invalid EXC_RETURN (INVPC) and raises a HardFault instead of returning.
    wire excret_nib_lr_ok  = (Rm_EX[3:0]  == 4'h1) | (Rm_EX[3:0]  == 4'h9) | (Rm_EX[3:0]  == 4'hD);
    wire excret_nib_mem_ok = (MEMdata[3:0] == 4'h1) | (MEMdata[3:0] == 4'h9) | (MEMdata[3:0] == 4'hD);
    wire excret_bad = (b_exc_o & ~excret_nib_lr_ok) | (dm_exc_o & ~excret_nib_mem_ok);

    assign svcall_req_o = svc_EX & ~svc_escalate;
    assign fault_req_o  = bkpt_EX | udf_EX | bx_fault | align_fault | svc_escalate | bus_fault | pop_pc_bad | excret_bad;   // -> HardFault (excno 3)
    wire   svc_hold     = (svc_EX | bkpt_EX | udf_EX | bx_fault | align_fault | pop_pc_bad | excret_bad) & ~exc_active;
    assign global_stall = ld_stall | barrier_hold | exc_active | svc_hold | bl_gate;

    // POP {..,PC} / LDM into PC.  EXC_RETURN 0xFFFFFFFx (bit[0]=1) is handled
    // separately by the exception unit.  A NORMAL loaded value with bit[0]=1
    // redirects the fetch to it; a value with bit[0]=0 would request ARM state,
    // which ARMv6-M does not implement, so it raises a HardFault (INVSTATE) instead
    // of silently forcing the bit clear.
    wire        pop_pc_load   = ld_en & (MEMRd == 4'hF) & ~dm_exc_o;
    wire        pop_pc_bad    = pop_pc_load & ~MEMdata[0];
    wire        pop_pc        = pop_pc_load &  MEMdata[0];
    wire [31:0] pop_pc_target = {MEMdata[31:1], 1'b0};

    // TRM POP {..,PC} = 4+N.  Even-halfword return targets complete one cycle
    // faster than a regular branch refill in this pipeline, so their redirect is
    // delayed by one cycle; odd-halfword targets already take 4+N through the
    // odd-target refill path and fire immediately.  EXC_RETURN values never
    // reach pop_pc (dm_exc_o excludes them above).  The delay cycle is covered
    // by the load stream's drain, so no extra stall is needed.
    wire        pop_now   = pop_pc &  MEMdata[1];
    wire        pop_dly_c = pop_pc & ~MEMdata[1];
    reg         pop_dly_r;
    reg  [31:0] pop_dly_tgt_r;
    always @(posedge HCLK) begin
        if (~HRESETn | exc_flush) pop_dly_r <= 1'b0;
        else                      pop_dly_r <= pop_dly_c;
        if (pop_dly_c)            pop_dly_tgt_r <= pop_pc_target;
    end
    wire        pop_go     = pop_now | pop_dly_r;
    wire [31:0] pop_go_tgt = pop_dly_r ? pop_dly_tgt_r : pop_pc_target;

    // TRM BL = 4 cycles.  The 32-bit BL occupies an extra issue slot on the
    // real core.  The branch fires normally; the cycle after it (pipeline
    // already flushed to the sentinel) the whole pipe holds for one cycle, so
    // the refilled target enters EX one cycle later.  This point cannot be
    // hidden by fetch slack.  BLX register (16-bit, cond 0xF link encoding)
    // stays at 3 cycles.
    wire        bl_is32     = is_link & (cond_EX != 4'hF);
    wire        bl_first    = branch_EX & bl_is32;
    reg         bl_pend_r;
    reg         bl_gate;
    // Real M0's 4th BL cycle is the extra fetch slot the 32-bit instruction
    // occupies.  If the BL's issue into EX was already starved -- a dead EX
    // cycle (bubble, PC_EX==0) immediately before it, beyond the two normal
    // refill bubbles of a redirect -- that slot has been paid naturally and
    // the gate is skipped.  The accounting also telescopes correctly for
    // slow refills: the extra bubble is part of the preceding redirect's
    // measured cost, so skipping the following BL keeps the pair at book
    // total.  The gate's own bubble is excluded from flagging.
    reg  [1:0]  bl_rfl_cnt;
    reg         bl_stv_r;
    wire        ex_bubble   = (PC_EX == 32'h0);
    always @(posedge HCLK) begin
        if (~HRESETn | exc_flush | branch_EX | pop_go) begin
            bl_rfl_cnt <= 2'd2;
            bl_stv_r   <= 1'b0;
        end else if (ex_bubble) begin
            if (bl_rfl_cnt != 2'd0) bl_rfl_cnt <= bl_rfl_cnt - 2'd1;
            else if (~bl_gate)      bl_stv_r   <= 1'b1;
        end else
            bl_stv_r <= 1'b0;
    end
    wire        bl_charge   = bl_first & ~bl_stv_r;
    // Known limitation: if the BL's target is itself a spanning 32-bit
    // instruction issued through the split32 fast path (zero ID dwell), the
    // gate cannot catch it and that BL stays at 3 cycles.  Compiled code does
    // not produce this shape (BL targets are 16-bit prologue instructions).
    wire        bl_hit      = bl_pend_r & ~branch_EX & (PC_ID != 32'h0000FFFF)
                              & ~(split32_detect  & ~split32_fast)
                              & ~(split32_waiting & ~split32_here2);
    always @(posedge HCLK) begin
        if (~HRESETn | exc_flush) begin
            bl_pend_r <= 1'b0;
            bl_gate   <= 1'b0;
        end else begin
            bl_gate   <= bl_hit & ~bl_gate;
            bl_pend_r <= bl_charge ? 1'b1 :
                         ((bl_gate | bl_first) ? 1'b0 : bl_pend_r);
        end
    end

    // Asynchronous interrupts (from the NVIC via int_pend_i) reuse the same EU
    // entry as synchronous exceptions, but there is no svc_hold to freeze the
    // pipeline, so the return address (return_PC_i = PC_ID) can be captured on a
    // branch-penalty cycle where PC_ID is a wrong-path fetch (branch_EX/pop_pc)
    // or an IFID flush sentinel (0x0000FFFF).  Take the async interrupt only at
    // a valid instruction boundary; int_pend_i from the NVIC is a level, so
    // delaying the take (not dropping it) matches M0 boundary semantics.
    wire        async_safe    = ~branch_EX & ~pop_pc & ~pop_pc_bad & ~pop_dly_r & ~bl_pend_r & (PC_ID != 32'h0000FFFF);
    wire        int_pend_gated = int_pend_i & async_safe;

    assign PC_in = exc_PC_valid ? exc_PC_target :
                   pop_go       ? pop_go_tgt    :
                   branch_EX    ? PC_Branch     :
                   split32_fast    ? (PC_ID + 32'd4) :  // -> word2 high half (next instr)
                   split32_detect  ? s32_redir_addr :   // slow path: redirect to 2nd word
                   // FIX: once the second word reaches ID the 32-bit instruction has been
                   // assembled and issued, so the PC must jump PAST it. PC_IF is held at word2
                   // during the wait, so without this IFID re-latches word2 next cycle and the
                   // core decodes the ORPHAN second halfword as a standalone 16-bit instruction.
                   // (A spanning DSB's 0x8F4F decodes as LDRH r7,[r1,#58] and silently ate r7.)
                   split32_here2   ? (split32_pc + 32'd4) :
                   split32_waiting ? PC_IF          :   // hold there until it arrives
                   (if_ready & ~global_stall) ? PC_IF + instr_step :
                                                PC_IF;

    // 32-bit instructions advance the fetch by 4 only when EVEN-aligned (both
    // halves in the current word).  ODD-aligned (spanning) 32-bit instructions are
    // handled by the split32 fetch redirect, so a +4 here is not needed and is in
    // fact harmful: a prefetched Instr_IF can be a word ahead of PC_IF during a
    // stall, and reading its high half at an odd PC_IF would spuriously skip the
    // 16-bit instruction sitting in the low half.
    assign instr_step  = (~PC_IF[1] & (instr_check == 5'b11101))     ? 3'b100 :
                         (~PC_IF[1] & (instr_check[4:1] == 4'b1111)) ? 3'b100 : 3'b010;
    assign instr_check = Instr_IF[15:11];

    program_counter PC(HCLK, HRESETn, PC_in, PC_IF);

    // ARMv6-M R15 read value for the instruction in ID: Align(PC_of_instr + 4, 4).
    // The old path fed PC_in (the next fetch PC, several instructions ahead), which
    // made LDR(literal)/ADR compute a wrong base.  PC_ID is this instruction's addr.
    wire [31:0] r15_read = (PC_ID_eff + 32'd4) & 32'hFFFFFFFC;

    // ---- L1: odd-halfword 32-bit instruction combine ----
    // A 32-bit Thumb instruction whose first halfword is the HIGH half of a fetched
    // word has its second halfword in the NEXT word.  Decoding it in place would use
    // the wrong second half.  Detect it in ID, latch the first halfword and its PC,
    // insert one bubble while IFID advances to the next word, then present the
    // reassembled instruction to the decoder with a word-aligned view.  Word-aligned
    // 32-bit instructions (PC_ID[1]==0) never enter this path.
    // ---- Spanning 32-bit instruction assembly (robust to a preceding stall) ----
    // A 32-bit Thumb instruction whose first halfword is the HIGH half of a fetched
    // word has its second halfword in the LOW half of the NEXT word.  The old scheme
    // combined in one fixed cycle and read the second half from Instr_ID; a multi-cycle
    // load/store stalling immediately before the instruction delayed detection until the
    // IFID/fetch had skipped the second word, losing the second half (32-bit BL then
    // mis-executed, so function calls were broken).  Robust scheme: on detecting a
    // 32-bit first half, latch it, redirect the fetch to the SECOND word and wait
    // (stalling EX) until the IFID actually presents that word, then assemble
    // {first, second} and issue.  Deterministic regardless of any preceding stall.
    reg        split32_waiting;
    reg [15:0] split32_hi;
    reg [31:0] split32_pc;
    wire is32_hi = (Instr_ID[31:27] == 5'b11101) | (Instr_ID[31:28] == 4'b1111);
    wire        id_valid_s32 = (PC_ID != 32'h0000FFFF);
    wire        is32_first   = PC_ID[1] & is32_hi & id_valid_s32
                               & ~branch_EX & ~exc_flush;
    wire [31:0] s32_word2    = (split32_pc & 32'hFFFFFFFC) + 32'd4;
    wire        split32_detect = ~split32_waiting & is32_first;             // enter assembly
    wire        s32_word2_prefetched = (PC_IF == ((PC_ID & 32'hFFFFFFFC) + 32'd4))
                                        & if_word_valid;   // Instr_IF really holds word2
    // NOTE: intentionally does NOT gate on haz_stall. haz_stall is generated by the
    // hazard detector from the (combinational) decode of dec_instr, and dec_instr depends
    // on split32_fast -- gating on haz_stall would close a combinational loop that Vivado
    // rejects (DRC LUTLP-1). A 32-bit instruction (BL/DSB/etc.) has no general-purpose
    // source registers, so haz_stall is never asserted while one is in decode; omitting
    // the term is therefore behaviourally identical and breaks the loop. ld_stall is safe
    // to use: it comes from the memory unit through registered IDEX inputs, not a comb path.
    wire        split32_fast = split32_detect & s32_word2_prefetched & ~ld_stall;
    wire        split32_here2  = split32_waiting & id_valid_s32
                                 & ({PC_ID[31:2], 2'b00} == s32_word2);     // 2nd word in ID
    always @(negedge HCLK or negedge HRESETn) begin
        if (!HRESETn) begin
            split32_waiting <= 1'b0;
            split32_hi      <= 16'b0;
            split32_pc      <= 32'b0;
        end else begin
            if (split32_detect & ~split32_fast) begin
                split32_hi      <= Instr_ID[31:16];
                split32_pc      <= PC_ID;
                split32_waiting <= 1'b1;
            end else if (split32_here2) begin
                split32_waiting <= 1'b0;
            end
        end
    end
    wire        split32_pending = split32_waiting;
    // Fetch redirect target = the second word (computed from live PC_ID before latch).
    wire [31:0] s32_redir_addr = (PC_ID & 32'hFFFFFFFC) + 32'd4;
    // Assembled instruction issues only on the cycle the second word is in ID.
    wire [31:0] dec_instr = split32_fast  ? {Instr_IF[15:0], Instr_ID[31:16]} :
                           split32_here2 ? {Instr_ID[15:0], split32_hi}     : Instr_ID;
    wire        dec_half  = (split32_pending | split32_fast) ? 1'b0 : PC_ID[1];
    wire [31:0] PC_ID_eff = split32_pending ? split32_pc : PC_ID;


    AHB_Arbitration ARB(
        .clk(HCLK), .rst_n(HRESETn),

        .if_PC_i(PC_IF),
        .branch_addr_i(exc_PC_valid ? exc_PC_target : pop_go ? pop_go_tgt : split32_detect ? s32_redir_addr : PC_Branch),
        .if_read_req_i(branch_EX | pop_go | exc_PC_valid | split32_detect | ~global_stall),
        .fetch(PC_IF[1]),
        .branch(branch_EX | pop_go | exc_PC_valid | split32_detect),
        .if_data_o(Instr_IF),
        .if_ready_o(if_ready),
        .if_word_valid_o(if_word_valid),
        .if_stall_o(if_stall),

        .dm_addr_i(dm_addr_i),
        .dm_data_i(dm_wdata_i),
        .dm_read_req_i(dm_read_req_i & ~ppb_dm_sel),
        .dm_write_req_i(dm_write_req_i & ~ppb_dm_sel),
        .dm_size_i(dm_size_i),
        .dm_data_o(dm_data_o),
        .dm_ready_o(dm_ready_o),
        .dm_grant_o(dm_grant),

        .ahb_data_i(rdata_i),
        .ahb_ready_i(ready_i),
        .ahb_error_i(error_i),
        .dm_error_o(dm_bus_error),
        .exc_error_o(exc_bus_error),
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
                    branch_EX | pop_go | ~HRESETn | exc_flush | split32_detect | split32_here2,
                    PC_IF, Instr_IF,
                    consumed_ID, PC_ID, Instr_ID);

    //////////////////////////////////////////////
    // Instruction Decode stage
    //////////////////////////////////////////////

    Instr_decode decoder(dec_half, dec_instr, Instruction, Imm_ID, Rd_ID, Rn, Rm, cond_ID,
                         ALU_op_ID, size_ID, type_ID, barrier_ID, ALU_src_ID, flags_ID,
                         memread_ID, memwrite_ID, regwrite_ID, wd_src_ID, branchC_ID,
                         move_ID, sign_ID, extend_ID, reverse_ID, sr_ID, cps_ID, svc_ID, bkpt_ID, awpc_ID, udf_ID);

    Register_File reg_file(
        .clk(HCLK),
        .we_WB(ld_en | (regwrite_EX & ~memread_EX)),
        .wd_WB(wd_WB),
        .PC_in(r15_read),
        .Rd_WB(ld_en ? MEMRd : Rd_EX),
        .Rn(Rn),
        .Rm(Rm),
        .Rt(Rd_ID),
        .Rmulti(MEMRm),
        .Rn_o(Rn_ID),
        .Rm_o(Rm_ID),
        .Rt_o(Rt_ID),
        .Rmulti_o(Rmulti_ID),
        .we_exc(rf_we_exc),
        .Rd_exc(rf_addr_exc),
        .wd_exc(rf_wdata_exc),
        .exc_sp_psp(exc_sp_psp_w),
        .spsel(CONTROL_v[1]),
        .ipsr(IPSR_o),
        .R0(R0_v), .R1(R1_v), .R2(R2_v), .R3(R3_v),
        .R12(R12_v), .SP(SP_v), .LR(LR_v),
        .msr_msp_we(msr_msp_we), .msr_psp_we(msr_psp_we), .msr_sp_d(Rn_EX),
        .dm_sp_we(dm_sp_we), .dm_sp_d(dm_sp_data), .dm_wb_reg(dm_base_reg),
        .MSP_o(MSP_v), .PSP_o(PSP_v)
    );


    AGU agu(ALU_src_ID, (|type_ID), Rn_ID, Rm_ID, Imm_ID, Addr_ID);

    Hazard_Det hazard_det_unit(memread_EX, Rd_EX, type_EX, Imm_EX[8:0], Rn, Rm, haz_stall);

        // FIX: IDEX_wipe overrides IDEX's enable, so wiping it during the split32
        // stall also destroyed the control signals of a multi-cycle PUSH/STM still
        // executing in EX. type_EX went to 0, so the store-data mux selected Rt_EX
        // instead of Rmulti_ID and PUSH wrote ZERO for LR. Hold the wipe off while
        // the memory unit is busy (ld_stall).
    IDEX IDEXbuffer(HCLK, ~global_stall, ~HRESETn|haz_stall|branch_EX|(((split32_detect & ~split32_fast)|(split32_waiting & ~split32_here2)) & ~ld_stall)|pop_go|exc_flush,
        PC_ID_eff, Rd_ID, Rn_ID, Rm_ID, Rt_ID, Imm_ID, Addr_ID,
        ALU_op_ID, cond_ID, size_ID, type_ID, barrier_ID,
        ALU_src_ID, memread_ID, memwrite_ID, regwrite_ID, wd_src_ID,
        branchC_ID, move_ID, flags_ID, sign_ID, extend_ID, reverse_ID, sr_ID, cps_ID, svc_ID, bkpt_ID, udf_ID, awpc_ID,
        PC_EX, Rd_EX, Rn_EX, Rm_EX, Rt_EX, Imm_EX, Addr_EX,
        ALU_op_EX, cond_EX, size_EX, type_EX, barrier_EX,
        ALU_src_EX, memread_EX, memwrite_EX, regwrite_EX, wd_src_EX,
        branchC_EX, move_EX, flags_EX, sign_EX, extend_EX, reverse_EX, sr_EX, cps_EX, svc_EX, bkpt_EX, udf_EX, awpc_EX);

    //////////////////////////////////////////////
    // Execution stage
    //////////////////////////////////////////////

    Extender EXT(HCLK, sign_EX, size_EX[0], Rm_EX[15:0], EXTdata);
    Reverser REV(HCLK, reverse_EX, sign_EX, size_EX[1], Rm_EX, REVdata);

    Barrier_Unit BU(HCLK, HRESETn, barrier_EX, ready_i, ld_en, write_req_o, barrier_hold, barrier_flush);

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
        .wdata(cps_EX ? {31'b0, Imm_EX[8]} : Rn_EX),
        .msp_i(MSP_v),
        .psp_i(PSP_v),
        .rdata_o(SRdata),
        .APSR_o(APSR),
        .PRIMASK_o(PRIMASK_o),
        .IPSR_o(IPSR_o),
        .CONTROL_o(CONTROL_v)
    );

    Branch_Unit Branch(branchC_EX, awpc_EX, cond_EX, PC_EX, Imm_EX, Rm_EX, N, Z, C, V,
                       branch_EX, PC_Branch, b_exc_o, bx_fault);

    Data_Memory DataMem(HCLK, HRESETn,
        Addr_EX,
        |type_EX ? Rmulti_ID : Rt_EX,
        Rd_EX, size_EX, sign_EX,
        memread_EX & ~align_fault, memwrite_EX & ~align_fault, 1'b1,
        type_EX, Imm_EX[8:0],
        ppb_dm_sel ? ppb_rdata_i : dm_data_o, ppb_dm_sel ? 1'b1 : dm_ready_o,
        dm_addr_i, dm_wdata_i, dm_read_req_i, dm_write_req_i, dm_size_i,
        MEMdata, MEMRd, MEMRm, ld_en, ld_stall, dm_exc_o, dm_sp_we, dm_sp_data, dm_base_reg, exc_flush, dm_grant);

    // BL / BLX write the return address (next instruction | Thumb bit) to LR.
    // The decode marks Rd=LR with regwrite+branchC but does not produce the
    // link value, so compute it explicitly here. Width is 4 for the 32-bit BL
    // (cond 0xE) and 2 for the 16-bit BLX (cond 0xF).
    wire        is_link  = branchC_EX & regwrite_EX & (Rd_EX == 4'hE);
    wire [31:0] link_val = (PC_EX + (cond_EX == 4'hF ? 32'd2 : 32'd4)) | 32'd1;

    assign wd_WB = is_link               ? link_val :
                   (sr_EX & regwrite_EX) ? SRdata :
                   (wd_src_EX || ld_en)  ? MEMdata :
                   extend_EX  ? EXTdata :
                   reverse_EX ? REVdata :
                                ALUdata;

    Exception_Unit EXC(
        .clk(HCLK), .rst_n(HRESETn),

        .int_pend_i(int_pend_gated),
        .int_pend_num_i(int_pend_num_i),
        .exc_taken_o(exc_taken_o),
        .exc_taken_num_o(exc_taken_num_o),
        .exc_return_o(exc_return_o),
        .exc_return_num_o(exc_return_num_o),

        .branch_exc_in(b_exc_o & excret_nib_lr_ok),
        .ldm_exc_in(dm_exc_o & excret_nib_mem_ok),
        .IPSR_i(IPSR_o),
        .return_PC_i(PC_ID),       // next-to-execute instruction
        .APSR_i(APSR),
        .R0_i(R0_v), .R1_i(R1_v), .R2_i(R2_v),
        .R3_i(R3_v), .R12_i(R12_v), .LR_i(LR_v),
        .SP_i(SP_v),
        .spsel_i(CONTROL_v[1]),
        .psp_i(PSP_v),
        .exc_return_val_i(dm_exc_o ? MEMdata : LR_v),

        .exc_active_o(exc_active),
        .exc_flush_o(exc_flush),
        .exc_PC_valid_o(exc_PC_valid),
        .exc_PC_target_o(exc_PC_target),

        .rf_we_o(rf_we_exc),
        .rf_addr_o(rf_addr_exc),
        .rf_wdata_o(rf_wdata_exc),
        .exc_sp_psp_o(exc_sp_psp_w),

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


    assign core_halted_o = 1'b0;   // no debug-halt mechanism; never halted (was undriven -> froze SysTick)
    assign ppb_addr_o  = dm_addr_i;
    assign ppb_wdata_o = dm_wdata_i;
    assign ppb_wr_o    = dm_write_req_i & (dm_addr_i[31:12] == 20'hE000E);
    assign ppb_rd_o    = ld_en          & (dm_addr_i[31:12] == 20'hE000E); // strobe at load completion

endmodule
