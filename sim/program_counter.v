`timescale 1ns / 1ps
// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2025-2026 Dylan Thornburg and Bryce Kelly
//
// This file is part of the Open-Source ARM Cortex-M0 project.
// Licensed under the GNU General Public License v3.0 or later.
// See the LICENSE file at the root of this repository.
//////////////////////////////////////////////////////////////////////////////////
// Create Date: 10/26/2025 04:00:06 PM
// Module Name: program_counter
//////////////////////////////////////////////////////////////////////////////////


module program_counter(
    input clk, reset,
    input [31:0] PC_in,
    output reg [31:0] PC_out
    );

    always @ (negedge clk) begin
        if (!reset) PC_out <= 0;
        else begin
            PC_out <= PC_in;
        end
    end

endmodule
