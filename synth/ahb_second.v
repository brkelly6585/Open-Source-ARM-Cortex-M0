`timescale 1ns / 1ps
// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2025-2026 Dylan Thornburg and Bryce Kelly
//
// This file is part of the Open-Source ARM Cortex-M0 project.
// Licensed under the GNU General Public License v3.0 or later.
// See the LICENSE file at the root of this repository.

//////////////////////////////////////////////////////////////////////////////////
// Create Date: 01/19/2026
// Module Name: ahb_slave.v
// Description: AHB-Lite Second
//
// Dependencies: None
//
// Revision 0.02 - read address and write address separated
//                 to avoid conflicts after implementing proper synchronous read
//////////////////////////////////////////////////////////////////////////////////

module ahb_second (
    input wire HCLK,
    input wire HRESETn,

    // AHB Slave Inputs
    input wire HSEL,
    input wire [31:0] HADDR,
    input wire [1:0] HTRANS,
    input wire HWRITE,
    input wire [2:0] HSIZE,
    input wire [31:0] HWDATA,
    input wire HREADY,

    // AHB Slave Outputs
    output wire [31:0] HRDATA,
    output wire HREADYOUT,
    output wire HRESP,

    // Memory Interface
    output wire mem_write, // 1 = write
    output wire [31:0] mem_raddr,
    output wire [31:0] mem_raddr_ap,  // ADDRESS-PHASE read address (for registered-read BRAM)
    output wire [31:0] mem_waddr,
    output wire [31:0] mem_wdata,
    output wire [3:0] mem_byte_en,
    input wire [31:0] mem_rdata
);

    // LOCAL PARAMETERS
    localparam [1:0] HTRANS_IDLE = 2'b00;
    localparam [1:0] HTRANS_NONSEQ = 2'b10;

    localparam [2:0] HSIZE_BYTE = 3'b000;
    localparam [2:0] HSIZE_HALFWORD = 3'b001;
    localparam [2:0] HSIZE_WORD = 3'b010;

    // INTERNALS
    reg [31:0] HADDR_reg;
    reg [2:0] HSIZE_reg;
    reg HWRITE_reg;
    reg [31:0] HWDATA_reg;
    reg valid_reg;

    // Valid transfer detection
    wire valid_transfer = HSEL && HREADY && (HTRANS == HTRANS_NONSEQ);

    // ADDRESS PHASE REGISTER
    always @(posedge HCLK or negedge HRESETn) begin
        if (!HRESETn) begin
            HADDR_reg <= 32'h0;
            HWDATA_reg <= 32'h0;
            HSIZE_reg <= HSIZE_WORD;
            HWRITE_reg <= 1'b0;
            valid_reg <= 1'b0;
        end
        else if (HREADY) begin
            if (valid_transfer) begin
                HADDR_reg <= HADDR;
                HSIZE_reg <= HSIZE;
                HWRITE_reg <= HWRITE;
                HWDATA_reg <= HWDATA;
            end
            valid_reg <= valid_transfer;
        end
    end

    // Byte enabling for writes
    reg [3:0] byte_en;

    always @(*) begin
        byte_en = 4'b0000;
        if (valid_reg && HWRITE_reg) begin
            case (HSIZE_reg)
                HSIZE_BYTE: begin
                    case (HADDR_reg[1:0])
                        2'b00: byte_en = 4'b0001;
                        2'b01: byte_en = 4'b0010;
                        2'b10: byte_en = 4'b0100;
                        2'b11: byte_en = 4'b1000;
                    endcase
                end
                HSIZE_HALFWORD: begin
                    case (HADDR_reg[1])
                        1'b0: byte_en = 4'b0011;
                        1'b1: byte_en = 4'b1100;
                    endcase
                end
                HSIZE_WORD: byte_en = 4'b1111;
                default: byte_en = 4'b1111;
            endcase
        end
    end

    // MEMORY OUTPUTS
    assign mem_raddr = HADDR_reg;
    assign mem_raddr_ap = HADDR;   // address-phase: registered inside ahb_mem, same 1-cycle latency
    assign mem_waddr = HADDR_reg;// was mem_addr
    assign mem_wdata = valid_reg ? HWDATA : HWDATA_reg;
    assign mem_byte_en = byte_en;
    assign mem_write = valid_reg && HWRITE_reg;

    // AHB OUTPUTS
    assign HRDATA = mem_rdata;
    assign HREADYOUT = 1'b1;  // always one because mem is zero wait state
    assign HRESP = 1'b0;  // These slaves dont give errors
endmodule
