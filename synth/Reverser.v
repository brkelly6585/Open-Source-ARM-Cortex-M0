`timescale 1ns / 1ps
// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2025-2026 Dylan Thornburg and Bryce Kelly
//
// This file is part of the Open-Source ARM Cortex-M0 project.
// Licensed under the GNU General Public License v3.0 or later.
// See the LICENSE file at the root of this repository.
//////////////////////////////////////////////////////////////////////////////////
// Create Date: 03/23/2026 07:46:17 PM
// Module Name: Reverser
//////////////////////////////////////////////////////////////////////////////////


module Reverser(
    input clk,
    input reverse,
    input sign,
    input size,
    input [31:0] data_i,
    output reg [31:0] data_o
    );

    always @ (posedge clk) begin
        if (size) begin
            data_o[7:0] = data_i[31:24];
            data_o[15:8] = data_i[23:16];
            data_o[23:16] = data_i[15:8];
            data_o[31:24] = data_i[7:0];
        end
        else if(sign) begin
            data_o[7:0] = data_i[15:8];
            data_o[15:8] = data_i[7:0];
            data_o[23:16] = {8{data_i[7]}};
            data_o[31:24] = {8{data_i[7]}};
        end
        else begin
            data_o[7:0] = data_i[15:8];
            data_o[15:8] = data_i[7:0];
            data_o[23:16] = data_i[31:24];
            data_o[31:24] = data_i[23:16];
        end
    end


endmodule
