`timescale 1ns / 1ps
// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2025-2026 Dylan Thornburg and Bryce Kelly
//
// This file is part of the Open-Source ARM Cortex-M0 project.
// Licensed under the GNU General Public License v3.0 or later.
// See the LICENSE file at the root of this repository.

//////////////////////////////////////////////////////////////////////////////////
// Create Date: 01/19/2026
// Module Name: ahb_decoder.v
// Description: AHB-Lite address decoder module
//
// Dependencies: None
//
// Memory Map (ARMv6-M aligned):
// 0x00000000 - 0x1FFFFFFF: Slave 0, Code region   (Instruction Memory, vectors at 0x0)
// 0x20000000 - 0x3FFFFFFF: Slave 1, SRAM region   (Data Memory, stack)
// All other addresses: Default Slave (Error)
//////////////////////////////////////////////////////////////////////////////////

module ahb_decoder (
    input [31:0] HADDR,

    // Slave selects
    output HSEL0,
    output HSEL1,
    output HSEL2,
    output HSEL3,
    output HSEL_DEFAULT

);

    // Region select per the ARMv6-M system address map (512MB regions on [31:29])
    assign HSEL0 = (HADDR[31:29] == 3'b000); // Code region 0x00000000-0x1FFFFFFF -> IMEM
    assign HSEL1 = (HADDR[31:29] == 3'b001); // SRAM region 0x20000000-0x3FFFFFFF -> DMEM
    assign HSEL2 = 1'b0;                      // unused: this system has one data slave
    assign HSEL3 = 1'b0;                      // retired (single DMEM now)

    // Default: Everything else (Peripheral, PPB handled in the core, etc.)
    assign HSEL_DEFAULT = ~(HSEL0 | HSEL1);

endmodule
