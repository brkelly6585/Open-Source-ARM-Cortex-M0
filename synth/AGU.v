`timescale 1ns / 1ps
// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2025-2026 Dylan Thornburg and Bryce Kelly
//
// This file is part of the Open-Source ARM Cortex-M0 project.
// Licensed under the GNU General Public License v3.0 or later.
// See the LICENSE file at the root of this repository.
//////////////////////////////////////////////////////////////////////////////////
// Create Date: 02/09/2026 01:10:41 PM
// Module Name: AGU
//////////////////////////////////////////////////////////////////////////////////


module AGU(
    input src,
    input type,
    input [31:0] Rn,
    input [31:0] Rm,
    input [31:0] Imm,
    output [31:0] Addr
    );

    assign Addr = type ? Rn : src ? Rn + Imm : Rn + Rm;

endmodule
