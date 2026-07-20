# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2025-2026 Dylan Thornburg and Bryce Kelly
#
# This file is part of the Open-Source ARM Cortex-M0 project.
# Licensed under the GNU General Public License v3.0 or later.
# See the LICENSE file at the root of this repository.
## ============================================================================
## M0_fpga_top - Nexys A7-100T (xc7a100tcsg324-1)
## ============================================================================

## ---- Primary clock: 100 MHz board oscillator -------------------------------
## This constrains the OSCILLATOR, not the core clock. Leave the period matching
## your board's crystal even though clock_gen divides it down: Vivado derives the
## PLL output clock from this one automatically. Do not hand-write a create_clock
## for the PLL output, or you will end up with two conflicting definitions on the
## same net.
create_clock -period 10.000 -name sys_clk [get_ports clk]
set_property -dict { PACKAGE_PIN E3 IOSTANDARD LVCMOS33 } [get_ports clk]

## The core clock is set by the PLL ratios in M0_fpga_top.v, which default to
## 100 MHz / 5 * 48 / 48 = 20 MHz. To run at a different frequency, change those
## parameters rather than this constraint. Feeding the core straight from the
## 100 MHz oscillator will not close timing.

## ---- Reset: BTNC, active high ----------------------------------------------
set_property -dict { PACKAGE_PIN N17 IOSTANDARD LVCMOS33 } [get_ports rst]

## ---- User LEDs LD0..LD7 (all green on this board) ---------------------------
##   led[0] heartbeat ~1 Hz   led[1] RUNNING   led[2] DONE
##   led[6] FAIL solid        led[7] PASS flashing  <-- the one to watch
set_property -dict { PACKAGE_PIN H17 IOSTANDARD LVCMOS33 } [get_ports {led[0]}]
set_property -dict { PACKAGE_PIN K15 IOSTANDARD LVCMOS33 } [get_ports {led[1]}]
set_property -dict { PACKAGE_PIN J13 IOSTANDARD LVCMOS33 } [get_ports {led[2]}]
set_property -dict { PACKAGE_PIN N14 IOSTANDARD LVCMOS33 } [get_ports {led[3]}]
set_property -dict { PACKAGE_PIN R18 IOSTANDARD LVCMOS33 } [get_ports {led[4]}]
set_property -dict { PACKAGE_PIN V17 IOSTANDARD LVCMOS33 } [get_ports {led[5]}]
set_property -dict { PACKAGE_PIN U17 IOSTANDARD LVCMOS33 } [get_ports {led[6]}]
set_property -dict { PACKAGE_PIN U16 IOSTANDARD LVCMOS33 } [get_ports {led[7]}]

## ---- Seven-segment cathodes CA..CG (active low) ----------------------------
## seg[0]=CA  seg[1]=CB  seg[2]=CC  seg[3]=CD  seg[4]=CE  seg[5]=CF  seg[6]=CG
set_property -dict { PACKAGE_PIN T10 IOSTANDARD LVCMOS33 } [get_ports {seg[0]}]
set_property -dict { PACKAGE_PIN R10 IOSTANDARD LVCMOS33 } [get_ports {seg[1]}]
set_property -dict { PACKAGE_PIN K16 IOSTANDARD LVCMOS33 } [get_ports {seg[2]}]
set_property -dict { PACKAGE_PIN K13 IOSTANDARD LVCMOS33 } [get_ports {seg[3]}]
set_property -dict { PACKAGE_PIN P15 IOSTANDARD LVCMOS33 } [get_ports {seg[4]}]
set_property -dict { PACKAGE_PIN T11 IOSTANDARD LVCMOS33 } [get_ports {seg[5]}]
set_property -dict { PACKAGE_PIN L18 IOSTANDARD LVCMOS33 } [get_ports {seg[6]}]

## ---- Decimal point (active low) --------------------------------------------
set_property -dict { PACKAGE_PIN H15 IOSTANDARD LVCMOS33 } [get_ports dp]

## ---- Digit anodes AN0..AN7 (active low) ------------------------------------
set_property -dict { PACKAGE_PIN J17 IOSTANDARD LVCMOS33 } [get_ports {an[0]}]
set_property -dict { PACKAGE_PIN J18 IOSTANDARD LVCMOS33 } [get_ports {an[1]}]
set_property -dict { PACKAGE_PIN T9  IOSTANDARD LVCMOS33 } [get_ports {an[2]}]
set_property -dict { PACKAGE_PIN J14 IOSTANDARD LVCMOS33 } [get_ports {an[3]}]
set_property -dict { PACKAGE_PIN P14 IOSTANDARD LVCMOS33 } [get_ports {an[4]}]
set_property -dict { PACKAGE_PIN T14 IOSTANDARD LVCMOS33 } [get_ports {an[5]}]
set_property -dict { PACKAGE_PIN K2  IOSTANDARD LVCMOS33 } [get_ports {an[6]}]
set_property -dict { PACKAGE_PIN U13 IOSTANDARD LVCMOS33 } [get_ports {an[7]}]

## ---- Display select: SW0, SW1 ----------------------------------------------
##   00  total cycles reported by CoreMark  (the number to compare against silicon)
##   01  crclist . crcmatrix                (expect E714 . 1FD7)
##   10  crcstate . crcfinal                (expect 8E3A . ....)
##   11  live free-running cycle counter    (proves the core is executing)
set_property -dict { PACKAGE_PIN J15 IOSTANDARD LVCMOS33 } [get_ports {sw[0]}]
set_property -dict { PACKAGE_PIN L16 IOSTANDARD LVCMOS33 } [get_ports {sw[1]}]

## ---- The display and LEDs are slow and asynchronous to anything that matters.
## Do not let their long counter chains distort the timing report.
set_false_path -to [get_ports {seg[*]}]
set_false_path -to [get_ports {an[*]}]
set_false_path -to [get_ports dp]
set_false_path -to [get_ports {led[*]}]
set_false_path -from [get_ports {sw[*]}]
set_false_path -from [get_ports rst]

## ---- Timing closure additions (2026-07-19) ---------------------------------
## The port false paths above already exclude the pins. This also excludes the
## display's INTERNAL pipeline (refresh counter -> segment registers), whose
## only consumers are the false-pathed pins. Momentary display glitches are
## invisible at human timescales; nothing functional passes through seg_reg.
set_false_path -to [get_cells -hierarchical -filter {NAME =~ "*BENCH*seg_reg*"}]
set_false_path -to [get_cells -hierarchical -filter {NAME =~ "*BENCH*an_reg*"}]

## ---- Core clock frequency (set in the Clocking Wizard, NOT here) -----------
## Current worst path needs 20.833 + 8.056 = 28.9 ns of logic against the
## half-period budget of the dual-edge core. Closure therefore requires
##   period >= 2 x 28.9 = 57.8 ns  ->  core clock <= 17.3 MHz.
## Open CLOCK_GEN (Clocking Wizard IP), set CLKOUT0 requested frequency to
## 16.000 MHz, regenerate. The derived clock constraint updates automatically.
## Cycle counts and the CoreMark comparison against silicon are unaffected;
## only wall-clock speed changes. Keep the latch-fixed AHB_Arbitration.v: the
## previous build's better WNS was latch time-borrowing credit, not speed.


## ---- Configuration ---------------------------------------------------------
set_property CFGBVS VCCO        [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]
