`timescale 1ns / 1ps
// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2025-2026 Dylan Thornburg and Bryce Kelly
//
// This file is part of the Open-Source ARM Cortex-M0 project.
// Licensed under the GNU General Public License v3.0 or later.
// See the LICENSE file at the root of this repository.
//////////////////////////////////////////////////////////////////////////////////
// Module Name: M0_fpga_top
// Description: Synthesizable top level for the open-source Cortex-M0 SoC.
//
//   This replaces the simulation-only M0_top (which generates its own clock and
//   reset with initial blocks and is NOT synthesizable). It exposes a real
//   board clock and reset button, includes a standard reset synchronizer, and
//   drives LEDs from the instruction-fetch address so the running core is
//   observable on hardware. Internal SoC wiring is identical to M0_top.
//
//   Program / data images: ahb_mem initializes its BRAM from coremark_fpga.hex
//   (instruction memory) and dmem_blank.hex (data memory) via $readmemh. In
//   Vivado, add both .hex files to the project as Memory Initialization Files.
//
//   Ports:
//     clk : board oscillator (set the create_clock period in the XDC to match)
//     rst : active-high reset (press = reset). For an active-low board button,
//           invert at the pin or change the synchronizer polarity below.
//     led : CoreMark status plus PLL/reset/CPU-activity diagnostics.
//////////////////////////////////////////////////////////////////////////////////

module M0_fpga_top #(
    // Nexys A7 board oscillator.
    parameter integer BOARD_CLK_HZ         = 100_000_000,
    parameter real    BOARD_CLK_PERIOD_NS  = 10.0,

    // 7-series PLL ratios. The generated clock is:
    //
    //   HCLK = BOARD_CLK_HZ * PLL_CLKFBOUT_MULT
    //                         / PLL_DIVCLK_DIVIDE
    //                         / PLL_CLKOUT0_DIVIDE
    //
    // Defaults: 100 MHz / 5 * 48 / 48 = exactly 20 MHz.
    parameter integer PLL_DIVCLK_DIVIDE    = 5,
    parameter integer PLL_CLKFBOUT_MULT    = 48,
    parameter integer PLL_CLKOUT0_DIVIDE   = 48
)(
    input        clk,
    input        rst,        // active-high reset button
    output [7:0] led,

    // ---- Nexys A7 seven-segment display (active low) ----
    output [6:0] seg,        // cathodes CA..CG
    output [7:0] an,         // digit anodes
    output       dp,         // decimal point

    // ---- display select ----
    //   00  total cycles reported by CoreMark   (the number to compare vs silicon)
    //   01  crclist : crcmatrix                 (expect E714 : 1FD7)
    //   10  crcstate : crcfinal                 (expect 8E3A : ....)
    //   11  live free-running cycle counter     (proves HCLK/reset/display are alive)
    input  [1:0] sw
);

    // ---------------------------------------------------------------
    // Parameterized clock generation and reset.
    // ---------------------------------------------------------------
    localparam integer CORE_CLK_HZ =
        ((BOARD_CLK_HZ / PLL_DIVCLK_DIVIDE) * PLL_CLKFBOUT_MULT)
        / PLL_CLKOUT0_DIVIDE;

    wire HCLK;
    wire clock_locked;

    clock_gen #(
        .CLKIN_PERIOD_NS (BOARD_CLK_PERIOD_NS),
        .DIVCLK_DIVIDE   (PLL_DIVCLK_DIVIDE),
        .CLKFBOUT_MULT   (PLL_CLKFBOUT_MULT),
        .CLKOUT0_DIVIDE  (PLL_CLKOUT0_DIVIDE)
    ) CLOCK_GEN (
        .clk_in (clk),
        .reset  (rst),
        .clk_out(HCLK),
        .locked (clock_locked)
    );

    // Asynchronous assertion while the button is pressed or the PLL is
    // unlocked; synchronous release after two rising edges of HCLK.
    wire reset_async = rst | ~clock_locked;
    reg [1:0] rst_sync;

    always @(posedge HCLK or posedge reset_async) begin
        if (reset_async)
            rst_sync <= 2'b00;
        else
            rst_sync <= {rst_sync[0], 1'b1};
    end

    wire HRESETn = rst_sync[1];

    // ---------------------------------------------------------------
    // SoC interconnect (identical to M0_top)
    // ---------------------------------------------------------------
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
    wire systick_sel  = ppb_sel && (cpu_addr[11:8] == 4'h0) && (cpu_addr[7:4] != 4'h0);
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

    wire        SLEEPONEXIT, SLEEPDEEP, SEVONPEND, SYSRESETREQ;

    // Future-expansion interrupt hooks. Tied off for basic synthesis; route to
    // top-level input pins when external interrupts are needed.
    wire        nmi_i    = 1'b0;
    wire [31:0] gpio_irq = 32'b0;

    // LEDs: instruction-fetch address (proof of life on hardware)
    // (old debug LED assignment removed: led is now driven by bench_leds)

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

    // ---- CoreMark benchmark I/O observation signals (from bench_io @ 0x40000000) ----
    wire [31:0] bench_cycle;
    wire [31:0] bench_status, bench_total_cycles, bench_iterations;
    wire [31:0] bench_seedcrc, bench_crclist, bench_crcmatrix, bench_crcstate, bench_crcfinal;
    wire [7:0]  bench_console_data;
    wire        bench_console_valid;

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
        .error_o(ahb_error),

        .bench_cycle_o        (bench_cycle),
        .bench_status_o       (bench_status),
        .bench_total_cycles_o (bench_total_cycles),
        .bench_iterations_o   (bench_iterations),
        .bench_seedcrc_o      (bench_seedcrc),
        .bench_crclist_o      (bench_crclist),
        .bench_crcmatrix_o    (bench_crcmatrix),
        .bench_crcstate_o     (bench_crcstate),
        .bench_crcfinal_o     (bench_crcfinal),
        .bench_console_data_o (bench_console_data),
        .bench_console_valid_o(bench_console_valid)
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

    // ---------------------------------------------------------------
    // Front panel
    // ---------------------------------------------------------------
    reg [31:0] disp_value;
    always @(*) begin
        case (sw)
            2'b00:   disp_value = bench_total_cycles;
            2'b01:   disp_value = {bench_crclist[15:0],  bench_crcmatrix[15:0]};
            2'b10:   disp_value = {bench_crcstate[15:0], bench_crcfinal[15:0]};
            2'b11:   disp_value = bench_cycle;
            default: disp_value = bench_total_cycles;
        endcase
    end

    // Split the two 16-bit CRC views with a decimal point so they read as two fields.
    wire [7:0] dp_mask = (sw == 2'b01 || sw == 2'b10) ? 8'b0001_0000 : 8'b0000_0000;

    seven_seg #(.CLK_HZ(CORE_CLK_HZ), .REFRESH_HZ(500)) DISP (
        .clk(HCLK),
        .rst_n(HRESETn),
        .value(disp_value),
        .dp_mask(dp_mask),
        .blank(8'b0000_0000),
        .an(an),
        .seg(seg),
        .dp(dp)
    );

    // ---------------------------------------------------------------
    // Status LEDs plus hardware diagnostics.
    //
    //   LD0 / H17: heartbeat
    //   LD1 / K15: CoreMark RUNNING status (0xA5)
    //   LD2 / J13: CoreMark DONE status (1, 2, or 3)
    //   LD3 / N14: PLL locked
    //   LD4 / R18: SoC reset released (HRESETn = 1)
    //   LD5 / V17: CPU address is advancing / bus activity
    //   LD6 / U17: CoreMark FAIL
    //   LD7 / U16: CoreMark PASS, flashing
    // ---------------------------------------------------------------
    wire [7:0] bench_led;

    bench_leds #(.CLK_HZ(CORE_CLK_HZ)) LEDS (
        .clk(HCLK),
        .rst_n(HRESETn),
        .status(bench_status),
        .led(bench_led)
    );

    // Hold LD5 on for roughly 50 ms whenever an accepted CPU transaction
    // advances to a different address. Continuous instruction execution keeps
    // it visibly lit; a core stuck forever at one address lets it turn off.
    localparam integer ACTIVITY_HOLD_CYCLES = (CORE_CLK_HZ >= 20) ? (CORE_CLK_HZ / 20) : 1;
    reg [31:0] activity_timer;
    reg [31:0] last_bus_addr;

    always @(posedge HCLK or negedge HRESETn) begin
        if (!HRESETn) begin
            activity_timer <= 32'd0;
            last_bus_addr   <= 32'hFFFF_FFFF;
        end
        else begin
            if ((ahb_read || ahb_write) && ahb_ready && (ahb_addr != last_bus_addr)) begin
                last_bus_addr   <= ahb_addr;
                activity_timer <= ACTIVITY_HOLD_CYCLES;
            end
            else if (activity_timer != 0) begin
                activity_timer <= activity_timer - 1'b1;
            end
        end
    end

    assign led[0] = bench_led[0];
    assign led[1] = bench_led[1];
    assign led[2] = bench_led[2];
    assign led[3] = clock_locked;
    assign led[4] = HRESETn;
    assign led[5] = (activity_timer != 0);
    assign led[6] = bench_led[6];
    assign led[7] = bench_led[7];

endmodule
