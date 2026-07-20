`timescale 1ns / 1ps
// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2025-2026 Dylan Thornburg and Bryce Kelly
//
// This file is part of the Open-Source ARM Cortex-M0 project.
// Licensed under the GNU General Public License v3.0 or later.
// See the LICENSE file at the root of this repository.

//////////////////////////////////////////////////////////////////////////////////
// Create Date: 01/19/2026
// Module Name: ahb_mux.v
// Description: AHB-Lite second multiplexer module
//
// Dependencies: None
//////////////////////////////////////////////////////////////////////////////////

module ahb_mux (
    input HCLK,
    input HRESETn,
    input [1:0] HTRANS,
    // Select inputs (from decoder)
    input HSEL0,
    input HSEL1,
    input HSEL2,
    input HSEL3,

    // HREADY feedback (for registering select)
    input HREADYOUT,

    // Slave 0 inputs
    input [31:0] HRDATA0,
    input HREADYOUT0,
    input HRESP0,

    // Slave 1 inputs
    input [31:0] HRDATA1,
    input HREADYOUT1,
    input HRESP1,

    // Slave 2 inputs
    input [31:0] HRDATA2,
    input HREADYOUT2,
    input HRESP2,

    // Slave 3 inputs
    input [31:0] HRDATA3,
    input HREADYOUT3,
    input HRESP3,

    // Default second inputs
    input [31:0] HRDATA_DEFAULT,
    input HREADYOUT_DEFAULT,
    input HRESP_DEFAULT,

    // Muxed outputs to master
    output reg [31:0] HRDATA,
    output reg HREADY,
    output reg HRESP
);

    reg [3:0] HSEL_reg;
    localparam SEL_SECOND0 = 2'd0;
    localparam SEL_SECOND1 = 2'd1;
    localparam SEL_SECOND2 = 2'd2;
    localparam SEL_SECOND3 = 2'd3;
    localparam SEL_DEFAULT = 3'd4;

    always @(posedge HCLK or negedge HRESETn) begin
        if (!HRESETn) HSEL_reg <= SEL_SECOND0;
        else if (HREADYOUT && (HTRANS != 2'b00)) begin
            if (HSEL0) HSEL_reg <= SEL_SECOND0;
            else if (HSEL1) HSEL_reg <= SEL_SECOND1;
            else if (HSEL2) HSEL_reg <= SEL_SECOND2;
            else if (HSEL3) HSEL_reg <= SEL_SECOND3;
            else HSEL_reg <= SEL_DEFAULT;
        end
    end

    always @(*) begin
        case (HSEL_reg)
            SEL_SECOND0: begin
                HRDATA = HRDATA0;
                HREADY = HREADYOUT0;
                HRESP = HRESP0;
            end

            SEL_SECOND1: begin
                HRDATA = HRDATA1;
                HREADY = HREADYOUT1;
                HRESP = HRESP1;
            end

            SEL_SECOND2: begin
                HRDATA = HRDATA2;
                HREADY = HREADYOUT2;
                HRESP = HRESP2;
            end

            SEL_SECOND3: begin
                HRDATA = HRDATA3;
                HREADY = HREADYOUT3;
                HRESP = HRESP3;
            end

            default: begin
                HRDATA = HRDATA_DEFAULT;
                HREADY = HREADYOUT_DEFAULT;
                HRESP  = HRESP_DEFAULT;
            end
        endcase
    end

endmodule
