`timescale 1ns / 1ps
// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2025-2026 Dylan Thornburg and Bryce Kelly
//
// This file is part of the Open-Source ARM Cortex-M0 project.
// Licensed under the GNU General Public License v3.0 or later.
// See the LICENSE file at the root of this repository.
//////////////////////////////////////////////////////////////////////////////////
// Module Name: clock_gen
// Description: PLL-based clock generator for 7-series parts.
//   Simple, synthesizable AMD/Xilinx 7-series PLL clock generator.
//
//   Output frequency:
//
//     Fout = Fin * CLKFBOUT_MULT
//                / DIVCLK_DIVIDE
//                / CLKOUT0_DIVIDE
//
//   Nexys A7 exact 24 MHz defaults:
//
//     Fin = 100 MHz, DIVCLK_DIVIDE = 5,
//     CLKFBOUT_MULT = 48, CLKOUT0_DIVIDE = 48
//
//     100 MHz / 5 * 48 / 48 = 20 MHz
//
//   To change the output frequency, override the three integer divider/
//   multiplier parameters from M0_fpga_top. Keep the PLL PFD and VCO inside
//   the legal ranges for the selected 7-series speed grade.
//////////////////////////////////////////////////////////////////////////////////

module clock_gen #(
    parameter real    CLKIN_PERIOD_NS = 10.0,
    parameter integer DIVCLK_DIVIDE   = 5,
    parameter integer CLKFBOUT_MULT   = 48,
    parameter integer CLKOUT0_DIVIDE  = 48
)(
    input  wire clk_in,
    input  wire reset,
    output wire clk_out,
    output wire locked
);

    wire clkfb_pll;
    wire clkfb_global;
    wire clkout_pll;

    PLLE2_BASE #(
        .BANDWIDTH("OPTIMIZED"),
        .CLKFBOUT_MULT(CLKFBOUT_MULT),
        .CLKFBOUT_PHASE(0.0),
        .CLKIN1_PERIOD(CLKIN_PERIOD_NS),

        .CLKOUT0_DIVIDE(CLKOUT0_DIVIDE),
        .CLKOUT0_DUTY_CYCLE(0.5),
        .CLKOUT0_PHASE(0.0),

        .CLKOUT1_DIVIDE(1),
        .CLKOUT1_DUTY_CYCLE(0.5),
        .CLKOUT1_PHASE(0.0),

        .CLKOUT2_DIVIDE(1),
        .CLKOUT2_DUTY_CYCLE(0.5),
        .CLKOUT2_PHASE(0.0),

        .CLKOUT3_DIVIDE(1),
        .CLKOUT3_DUTY_CYCLE(0.5),
        .CLKOUT3_PHASE(0.0),

        .CLKOUT4_DIVIDE(1),
        .CLKOUT4_DUTY_CYCLE(0.5),
        .CLKOUT4_PHASE(0.0),

        .CLKOUT5_DIVIDE(1),
        .CLKOUT5_DUTY_CYCLE(0.5),
        .CLKOUT5_PHASE(0.0),

        .DIVCLK_DIVIDE(DIVCLK_DIVIDE),
        .REF_JITTER1(0.010),
        .STARTUP_WAIT("FALSE")
    ) pll_i (
        .CLKOUT0(clkout_pll),
        .CLKOUT1(),
        .CLKOUT2(),
        .CLKOUT3(),
        .CLKOUT4(),
        .CLKOUT5(),

        .CLKFBOUT(clkfb_pll),
        .LOCKED(locked),

        .CLKIN1(clk_in),
        .PWRDWN(1'b0),
        .RST(reset),
        .CLKFBIN(clkfb_global)
    );

    BUFG feedback_bufg_i (
        .I(clkfb_pll),
        .O(clkfb_global)
    );

    BUFG output_bufg_i (
        .I(clkout_pll),
        .O(clk_out)
    );

endmodule
