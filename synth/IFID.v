`timescale 1ns / 1ps
// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2025-2026 Dylan Thornburg and Bryce Kelly
//
// This file is part of the Open-Source ARM Cortex-M0 project.
// Licensed under the GNU General Public License v3.0 or later.
// See the LICENSE file at the root of this repository.
//////////////////////////////////////////////////////////////////////////////////
// Create Date: 10/26/2025 05:12:19 PM
// Module Name: IFID
//////////////////////////////////////////////////////////////////////////////////
module IFID(
    input clk,
    input IFID_EN,
    input IFID_consume,
    input IFID_wipe,
    input [31:0] PC_in, Instr_in,
    output reg consumed,
    output reg [31:0] PC_out, Instr_out
);
    parameter [15:0] NOP = 16'hBF00;

    // Size of the instruction currently presented to ID. A 32-bit Thumb encoding is
    // 111x1 in its first halfword (DDI0419E A5.1): 11101, 11110 or 11111.
    wire [4:0] chk_id  = PC_out[1] ? Instr_out[31:27] : Instr_out[15:11];
    wire       is32_id = (chk_id == 5'b11101) || (chk_id[4:1] == 4'b1111);

    always @(negedge clk) begin
        if (IFID_wipe) begin
            PC_out    <= 32'hFFFF;
            Instr_out <= {NOP, NOP};
            consumed  <= 1'b1;
        end else if (IFID_EN && (PC_in != PC_out)) begin
            PC_out    <= PC_in;
            Instr_out <= Instr_in;
            consumed  <= 1'b0;
        end else if (IFID_consume && !consumed) begin
            // Tracks when the prefetched word has been fully consumed.
            //
            // The is32_id term is essential: a 32-bit instruction sitting in the LOW
            // halfword must advance PC by 4, not 2. Advancing by 2 would land in the
            // middle of it and decode its second halfword as a standalone instruction.
            if (PC_out[1] || is32_id) begin
                consumed <= 1'b1;
                Instr_out <= {NOP, NOP};
            end else begin
                // Low half consumed: the high half of the fetched word is
                // already buffered, so advance to it whether or not a new
                // fetch is ready. Gating this on IFID_EN left the low-half
                // instruction re-presented to EX when a preceding store held
                // the bus (if_ready low), executing it twice.
                PC_out   <= PC_out + 32'd2;
                consumed <= 1'b0;
            end
        end else if (consumed) begin
            // Wait for new fetch
            Instr_out <= {NOP, NOP};
        end
    end
endmodule
