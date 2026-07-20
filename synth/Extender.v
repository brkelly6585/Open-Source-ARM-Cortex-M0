`timescale 1ns / 1ps
// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2025-2026 Dylan Thornburg and Bryce Kelly
//
// This file is part of the Open-Source ARM Cortex-M0 project.
// Licensed under the GNU General Public License v3.0 or later.
// See the LICENSE file at the root of this repository.
//////////////////////////////////////////////////////////////////////////////////
// Create Date: 03/23/2026 07:30:21 PM
// Module Name: Extender
//////////////////////////////////////////////////////////////////////////////////


module Extender(
    input clk,
    input sign,
    input size,
    input [15:0] data_i,
    output reg [31:0] data_o
    );

    wire extend = sign ? (size ? data_i[15] : data_i[7]) : 1'b0;

    always @ (posedge clk)
        data_o = size ? {{16{extend}}, data_i} : {{24{extend}}, data_i[7:0]};


endmodule
