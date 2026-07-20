`timescale 1ns / 1ps
// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2025-2026 Dylan Thornburg and Bryce Kelly
//
// This file is part of the Open-Source ARM Cortex-M0 project.
// Licensed under the GNU General Public License v3.0 or later.
// See the LICENSE file at the root of this repository.
//////////////////////////////////////////////////////////////////////////////////
// Create Date: 02/09/2026 04:33:07 PM
// Module Name: M0_top
// Description: Simulation top level. Generates clock and reset, wires the core to the
// AHB system and the private peripheral bus, then self-checks the ARMv6-M
// instruction coverage results once the test program has finished.
//////////////////////////////////////////////////////////////////////////////////


module M0_top(
    );

    reg HCLK, HRESETn;

    wire        ahb_ready, ahb_error;
    wire [31:0] ahb_rdata;

    wire        ahb_read, ahb_write;
    wire [1:0]  ahb_size;
    wire [31:0] ahb_addr;
    wire [31:0] ahb_wdata;

    wire [31:0] cpu_addr;
    wire [31:0] cpu_wdata;
    wire        cpu_wr, cpu_rd;
    wire [31:0] nvic_rdata, scb_rdata, syst_rdata;

    wire ppb_sel      = (cpu_addr[31:12] == 20'hE000E);
    wire systick_sel  = ppb_sel && (cpu_addr[11:8] == 4'h0) && (cpu_addr[7:4] != 4'h0); // 0x010-0x0FF
    wire nvic_sel     = ppb_sel && (cpu_addr[11:8] >= 4'h1) && (cpu_addr[11:8] < 4'hD);
    wire scb_sel      = ppb_sel && (cpu_addr[11:8] == 4'hD);

    wire [31:0] ppb_rdata = nvic_sel     ? nvic_rdata :
                            scb_sel      ? scb_rdata  :
                            systick_sel  ? syst_rdata :
                                           32'b0;

    wire        nmi_pend, hardfault_pend;
    wire        svcall_pend, pendsv_pend, systick_pend;
    wire [1:0]  svcall_pri, pendsv_pri, systick_pri;
    wire        vectclractive;
    wire        isrpending;
    wire [8:0]  vectpending;

    wire        exc_taken,     exc_return;
    wire [5:0]  exc_taken_num, exc_return_num;
    wire        svcall_req;
    wire        fault_req;
    wire [5:0]  IPSR;
    wire        PRIMASK;
    wire        core_halted;
    wire        systick_fire;

    wire        int_pend;
    wire [5:0]  int_pend_num;

    wire nmi_i;
    wire [31:0] gpio_irq;
    wire SLEEPONEXIT, SLEEPDEEP, SEVONPEND, SYSRESETREQ;

    initial begin
        HCLK = 0;
        forever #5 HCLK = ~HCLK;
    end

    core core_dut(
                .HCLK(HCLK),
                .HRESETn(HRESETn),

                .rdata_i(ahb_rdata),
                .ready_i(ahb_ready),
                .error_i(ahb_error),

                .addr_o(ahb_addr),
                .wdata_o(ahb_wdata),
                .read_req_o(ahb_read),
                .write_req_o(ahb_write),
                .size_o(ahb_size),

                .ppb_addr_o     (cpu_addr),
                .ppb_wdata_o    (cpu_wdata),
                .ppb_wr_o       (cpu_wr),
                .ppb_rd_o       (cpu_rd),
                .ppb_rdata_i    (ppb_rdata),

                .exc_taken_o    (exc_taken),
                .exc_taken_num_o(exc_taken_num),
                .exc_return_o   (exc_return),
                .exc_return_num_o(exc_return_num),
                .svcall_req_o   (svcall_req),
                .fault_req_o    (fault_req),
                .IPSR_o         (IPSR),
                .PRIMASK_o      (PRIMASK),
                .core_halted_o  (core_halted),

                .int_pend_i     (int_pend),
                .int_pend_num_i (int_pend_num),

                .SLEEPONEXIT_i  (SLEEPONEXIT),
                .SLEEPDEEP_i    (SLEEPDEEP),
                .SEVONPEND_i    (SEVONPEND)
              );

    ahb_top ahb(
                .HCLK(HCLK),
                .HRESETn(HRESETn),

                .addr_i(ahb_addr),
                .wdata_i(ahb_wdata),
                .read_req_i(ahb_read),
                .write_req_i(ahb_write),
                .size_i(ahb_size),

                .rdata_o(ahb_rdata),
                .ready_o(ahb_ready),
                .error_o(ahb_error)
               );

    NVIC NVIC_Unit(
        .clk                (HCLK),
        .rst_n              (HRESETn),

        .reg_addr           (cpu_addr[11:0]),
        .reg_wdata          (cpu_wdata),
        .reg_wr             (cpu_wr & nvic_sel),
        .nvic_rdata         (nvic_rdata),

        .irq_i              (gpio_irq),

        .PRIMASK            (PRIMASK),
        .exc_taken          (exc_taken),
        .exc_taken_num      (exc_taken_num),
        .exc_return         (exc_return),
        .exc_return_num     (exc_return_num),

        .nmi_pend           (nmi_pend),
        .hardfault_pend     (hardfault_pend),
        .svcall_pend        (svcall_pend),
        .pendsv_pend        (pendsv_pend),
        .systick_pend       (systick_pend),
        .svcall_pri         (svcall_pri),
        .pendsv_pri         (pendsv_pri),
        .systick_pri        (systick_pri),
        .VECTCLRACTIVE      (vectclractive),

        .int_pend           (int_pend),
        .int_pend_num       (int_pend_num),

        .isrpending         (isrpending),
        .vectpending        (vectpending)
    );

    SysTick SysTick_Unit (
        .clk                (HCLK),
        .rst_n              (HRESETn),

        .reg_addr           (cpu_addr[11:0]),
        .reg_wdata          (cpu_wdata),
        .reg_wr             (cpu_wr & systick_sel),
        .reg_rd             (cpu_rd & systick_sel),
        .syst_rdata         (syst_rdata),

        .core_halted        (core_halted),

        .systick_fire       (systick_fire)
    );

    SCB SCB_Unit (
        .clk                (HCLK),
        .rst_n              (HRESETn),

        .reg_addr           (cpu_addr[11:0]),
        .reg_wdata          (cpu_wdata),
        .reg_wr             (cpu_wr & scb_sel),
        .scb_rdata          (scb_rdata),

        .nmi_i              (nmi_i),

        .IPSR               (IPSR),
        .exc_taken          (exc_taken),
        .exc_taken_num      (exc_taken_num),
        .svcall_req         (svcall_req),
        .fault_req          (fault_req),
        .systick_fire       (systick_fire),

        .isrpending         (isrpending),
        .vectpending        (vectpending),
        .nmi_pend           (nmi_pend),
        .hardfault_pend     (hardfault_pend),
        .svcall_pend        (svcall_pend),
        .pendsv_pend        (pendsv_pend),
        .systick_pend       (systick_pend),
        .svcall_pri         (svcall_pri),
        .pendsv_pri         (pendsv_pri),
        .systick_pri        (systick_pri),
        .VECTCLRACTIVE      (vectclractive),

        .SYSRESETREQ        (SYSRESETREQ),
        .SLEEPONEXIT        (SLEEPONEXIT),
        .SLEEPDEEP          (SLEEPDEEP),
        .SEVONPEND          (SEVONPEND)
    );

    initial begin
        HRESETn = 1'b0;
        #10
        HRESETn = 1'b1;
    end

    // ---------------------------------------------------------------------------
    // Self-check for insn_coverage.hex
    //
    // The test program writes one result word per instruction to SRAM starting at
    // 0x20000000, then parks in a spin loop at "done". The expected values are the
    // ARMv6-M architectural results, identical to what an STM32F051 produces, and
    // they are listed alongside each test in insn_coverage.s.
    //
    // Completion is detected by watching the result pointer stop advancing rather
    // than by waiting a fixed number of cycles, so this stays correct if tests are
    // added or removed.
    // ---------------------------------------------------------------------------
    localparam integer N_RESULTS = 75;

    reg [31:0] expected [0:N_RESULTS-1];
    integer i, failures, idle;

    initial begin
        expected[ 0] = 32'h0000002A;   // MOVS imm8
        expected[ 1] = 32'h0000002A;   // MOV reg
        expected[ 2] = 32'h00000055;   // MOV (high registers)
        expected[ 3] = 32'h0000002D;   // ADDS imm3
        expected[ 4] = 32'h00000030;   // ADDS imm8
        expected[ 5] = 32'h0000005A;   // ADDS reg
        expected[ 6] = 32'h00000054;   // ADD (high registers)
        expected[ 7] = 32'h00000010;   // ADD SP + imm
        expected[ 8] = 32'h00000000;   // SUB SP / ADD SP round trip
        expected[ 9] = 32'h00000025;   // SUBS imm3
        expected[10] = 32'h00000040;   // SUBS imm8
        expected[11] = 32'h0000001A;   // SUBS reg
        expected[12] = 32'hFFFFFFD6;   // RSBS / NEGS
        expected[13] = 32'h00000021;   // ADCS
        expected[14] = 32'h00000020;   // SBCS
        expected[15] = 32'h0000002A;   // MULS
        expected[16] = 32'h00000018;   // ANDS
        expected[17] = 32'h00000066;   // EORS
        expected[18] = 32'h0000007E;   // ORRS
        expected[19] = 32'h00000042;   // BICS
        expected[20] = 32'hFFFFFFC3;   // MVNS
        expected[21] = 32'h00000001;   // TST sets Z
        expected[22] = 32'h00000001;   // CMN sets Z
        expected[23] = 32'h00000010;   // LSLS imm
        expected[24] = 32'h00000020;   // LSLS reg
        expected[25] = 32'h00000010;   // LSRS imm
        expected[26] = 32'h00000008;   // LSRS reg
        expected[27] = 32'hFFFFFFF8;   // ASRS imm
        expected[28] = 32'hFFFFFFF8;   // ASRS reg
        expected[29] = 32'h20000001;   // RORS
        expected[30] = 32'hFFFFFF80;   // SXTB
        expected[31] = 32'hFFFF8000;   // SXTH
        expected[32] = 32'h000000F0;   // UXTB
        expected[33] = 32'h0000F000;   // UXTH
        expected[34] = 32'h34120000;   // REV
        expected[35] = 32'h00003412;   // REV16
        expected[36] = 32'hFFFF8000;   // REVSH
        expected[37] = 32'h0000005A;   // STR / LDR imm
        expected[38] = 32'h0000003C;   // STR / LDR imm offset
        expected[39] = 32'h00000077;   // STR / LDR register offset
        expected[40] = 32'h000000C5;   // STRB / LDRB
        expected[41] = 32'h00000FF0;   // STRH / LDRH
        expected[42] = 32'hFFFFFF80;   // LDRSB
        expected[43] = 32'hFFFF8000;   // LDRSH
        expected[44] = 32'h00000011;   // STMIA with writeback
        expected[45] = 32'h00000099;   // PUSH / POP
        expected[46] = 32'h00000001;   // BEQ
        expected[47] = 32'h00000001;   // BNE
        expected[48] = 32'h00000001;   // BCS / BHS
        expected[49] = 32'h00000001;   // BCC / BLO
        expected[50] = 32'h00000001;   // BMI
        expected[51] = 32'h00000001;   // BPL
        expected[52] = 32'h00000001;   // BVS
        expected[53] = 32'h00000001;   // BVC
        expected[54] = 32'h00000001;   // BHI
        expected[55] = 32'h00000001;   // BLS taken
        expected[56] = 32'h00000000;   // BLS not taken
        expected[57] = 32'h00000001;   // BGE
        expected[58] = 32'h00000001;   // BLT
        expected[59] = 32'h00000001;   // BGT
        expected[60] = 32'h00000001;   // BLE taken
        expected[61] = 32'h00000000;   // BLE not taken
        expected[62] = 32'h000000B1;   // BL then BX LR
        expected[63] = 32'h000000B2;   // BLX then BX LR
        expected[64] = 32'h80000000;   // MRS APSR with N set
        expected[65] = 32'h00000001;   // CPSID then MRS PRIMASK
        expected[66] = 32'h00000000;   // CPSIE then MRS PRIMASK
        expected[67] = 32'h00000000;   // MRS IPSR in thread mode
        expected[68] = 32'hF0000000;   // MSR then MRS APSR
        expected[69] = 32'h00000002;   // MSR then MRS CONTROL
        expected[70] = 32'h000000D1;   // DMB
        expected[71] = 32'h000000D2;   // DSB
        expected[72] = 32'h00000015;   // ISB
        expected[73] = 32'h000000AB;   // NOP / YIELD / SEV
        expected[74] = 32'h1234ABCD;   // LDR literal
    end

    // Result pointer lives in R7. Once it has stopped moving for a comfortable
    // margin, every store has retired and the array can be compared.
    reg [31:0] ptr_prev;
    initial begin
        idle    = 0;
        ptr_prev = 32'hFFFFFFFF;
        @(posedge HRESETn);
        forever begin
            @(posedge HCLK);
            if (core_dut.reg_file.Registers[7] !== ptr_prev) begin
                ptr_prev = core_dut.reg_file.Registers[7];
                idle     = 0;
            end else begin
                idle = idle + 1;
            end
            if (idle == 2000) begin
                failures = 0;
                $display("");
                $display("=== ARMv6-M instruction coverage ===");
                for (i = 0; i < N_RESULTS; i = i + 1) begin
                    if (ahb.DMEM.mem[i] !== expected[i]) begin
                        $display("  FAIL  result %0d: got %08h, expected %08h",
                                 i, ahb.DMEM.mem[i], expected[i]);
                        failures = failures + 1;
                    end
                end
                if (failures == 0)
                    $display("  PASS  %0d/%0d results match ARMv6-M expectations",
                             N_RESULTS, N_RESULTS);
                else
                    $display("  %0d of %0d results differ", failures, N_RESULTS);
                $display("====================================");
                $display("");
                $finish;
            end
        end
    end

endmodule
