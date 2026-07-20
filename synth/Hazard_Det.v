`timescale 1ns / 1ps
// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2025-2026 Dylan Thornburg and Bryce Kelly
//
// This file is part of the Open-Source ARM Cortex-M0 project.
// Licensed under the GNU General Public License v3.0 or later.
// See the LICENSE file at the root of this repository.
//////////////////////////////////////////////////////////////////////////////////
// Module Name: Hazard_Det
// Load-use hazard detection.
//   * Single loads (type 00): the load target (INCLUDING r0) must not be a source
//     of the immediately following instruction.
//   * Multi loads (POP/LDM, type != 00): the destination set is the register-list
//     mask, not Rd_EX (which the sequencer overrides).  Stall if any low register
//     (r0-r7) read by the next instruction is in that list.
// Note: unread source indices default to 0 in decode, so a load into r0 followed by
// an instruction that does not read r0 yields a harmless bubble (result unchanged).
//////////////////////////////////////////////////////////////////////////////////


module Hazard_Det(
    input memread_EX,
    input [3:0] Rd_EX,
    input [1:0] type_EX,          // 00 = single access, else multi (POP/LDM/PUSH/STM)
    input [8:0] reglist_EX,       // Imm_EX[8:0]: register-list mask for multi accesses
    input [3:0] Rn_ID,
    input [3:0] Rm_ID,
    output haz_stall
    );

    // Single load: target (incl. r0) collides with a source read next cycle.
    wire single_haz = memread_EX && (type_EX == 2'b00) &&
                      ((Rd_EX == Rn_ID) || (Rd_EX == Rm_ID));

    // Multi load: a low register (r0-r7) read next cycle is in the loaded set.
    wire rn_hit = (Rn_ID < 4'd8) && reglist_EX[Rn_ID];
    wire rm_hit = (Rm_ID < 4'd8) && reglist_EX[Rm_ID];
    wire multi_haz = memread_EX && (type_EX != 2'b00) && (rn_hit || rm_hit);

    assign haz_stall = single_haz || multi_haz;

endmodule
