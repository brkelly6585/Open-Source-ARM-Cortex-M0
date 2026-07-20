`timescale 1ns / 1ps
// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2025-2026 Dylan Thornburg and Bryce Kelly
//
// This file is part of the Open-Source ARM Cortex-M0 project.
// Licensed under the GNU General Public License v3.0 or later.
// See the LICENSE file at the root of this repository.

//////////////////////////////////////////////////////////////////////////////////
// Create Date: 01/25/2026
// Module Name: ahb_default_slave.v
// Description: AHB-Lite default slave for unmapped addresses
//              Returns ERROR response for any access
//
// Dependencies: None
//////////////////////////////////////////////////////////////////////////////////

module ahb_default_second (
    input HCLK,
    input HRESETn,

    // AHB Slave Inputs
    input HSEL,
    input [1:0] HTRANS,
    input HREADY,

    // AHB Slave Outputs
    output [31:0] HRDATA,
    output reg HREADYOUT,
    output reg HRESP
);

    // LOCAL PARAMETERS
    localparam [1:0] HTRANS_IDLE = 2'b00;
    localparam [1:0] HTRANS_NONSEQ = 2'b10;

    localparam HRESP_OKAY = 1'b0;
    localparam HRESP_ERROR = 1'b1;

    // State machine
    localparam ST_IDLE = 1'b0;
    localparam ST_ERROR = 1'b1;

    reg state;
    wire valid_transfer = HSEL && HREADY && (HTRANS == HTRANS_NONSEQ);

    // STATE MACHINE
    always @(posedge HCLK or negedge HRESETn) begin
        if (!HRESETn) begin
            state <= ST_IDLE;
            HREADYOUT <= 1'b1;
            HRESP <= HRESP_OKAY;
        end
        else begin
            case (state)
                ST_IDLE: begin
                    if (valid_transfer) begin
                        // First cycle of error response
                        state <= ST_ERROR;
                        HREADYOUT <= 1'b0;
                        HRESP <= HRESP_ERROR;
                    end
                    else begin
                        HREADYOUT <= 1'b1;
                        HRESP <= HRESP_OKAY;
                    end
                end

                ST_ERROR: begin
                    // Second cycle of error response
                    state <= ST_IDLE;
                    HREADYOUT <= 1'b1;
                    HRESP <= HRESP_ERROR;
                end
            endcase
        end
    end
    assign HRDATA = 32'h0; // Read data is always zero for default slave
endmodule
