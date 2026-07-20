`timescale 1ns / 1ps
// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2025-2026 Dylan Thornburg and Bryce Kelly
//
// This file is part of the Open-Source ARM Cortex-M0 project.
// Licensed under the GNU General Public License v3.0 or later.
// See the LICENSE file at the root of this repository.

//////////////////////////////////////////////////////////////////////////////////
// Create Date: 12/30/2025
// Module Name: ahb_master.v
// Description: ahb-lite master module
//
// Dependencies: None
//////////////////////////////////////////////////////////////////////////////////

module ahb_main (
    input HCLK,
    input HRESETn,

    // AHB Master Inputs (from slave/mux)
    input [31:0] HRDATA,
    input HREADY, //0=not ready, 1=ready
    input HRESP, // 0=ok, 1=error

    // AHB Master Outputs
    output reg [31:0] HADDR,
    output reg [2:0] HBURST,
    output reg HMASTLOCK,
    output reg [3:0] HPROT,
    output reg [2:0] HSIZE,
    output reg [1:0] HTRANS,
    output reg [31:0] HWDATA,
    output reg HWRITE,

    // CPU Connections
    input [31:0] addr_i,
    input [31:0] wdata_i,
    input read_req_i, //read request
    input write_req_i, //write request
    input [1:0] size_i, // 00=byte, 01=halfword, 10=word
    output reg [31:0] rdata_o,
    output ready_o,
    output error_o
);

    // LOCAL PARAMETERS
    localparam [1:0] HTRANS_IDLE = 2'b00; //only IDLE and NONSEQ supported by m0
    localparam [1:0] HTRANS_NONSEQ = 2'b10;

    localparam [2:0] HBURST_SINGLE = 3'b000; //only single supported by m0
    localparam [2:0] HSIZE_BYTE = 3'b000;
    localparam [2:0] HSIZE_HALFWORD = 3'b001;
    localparam [2:0] HSIZE_WORD = 3'b010;
    localparam HRESP_OKAY = 1'b0;
    localparam HRESP_ERROR = 1'b1;
    localparam [3:0] HPROT_DEFAULT = 4'b0011; //Default of non-cacheable, non-bufferable, privileged, data (all 4 never change)

    //State machine encodings
    localparam [1:0] ST_IDLE = 2'b00;
    localparam [1:0] ST_DATA = 2'b01;
    localparam [1:0] ST_ERROR = 2'b10;


    reg [1:0] curr_state;
    reg [1:0] next_state;
    // Latched address/control (used during wait state)
    reg [31:0] addr_lat;
    reg [2:0] size_lat;
    reg write_lat;

    // Data phase info
    reg [31:0] addr_data;
    reg [2:0] size_data;

    // Request detection
    wire request = read_req_i | write_req_i;

    // SIZE ENCODING FUCNTION
    function [2:0] encode_size;
        input [1:0] size;
        begin
            case (size)
                2'b00: encode_size = HSIZE_BYTE;
                2'b01: encode_size = HSIZE_HALFWORD;
                2'b10: encode_size = HSIZE_WORD;
                default: encode_size = HSIZE_WORD;
            endcase
        end
    endfunction


    // NEXT STATE LOGIC
    always @(*) begin
        next_state = curr_state;
        case (curr_state)
            ST_IDLE: if (request) next_state = ST_DATA;

            ST_DATA: begin
                if (!HREADY && (HRESP == HRESP_ERROR)) next_state = ST_ERROR;
                else if (HREADY && !request) next_state = ST_IDLE;
            end

            ST_ERROR: if (HREADY) next_state = ST_IDLE;

            default: next_state = ST_IDLE;
        endcase
    end


    always @(posedge HCLK or negedge HRESETn) begin
        if (!HRESETn) curr_state <= ST_IDLE;
        else if (curr_state == ST_IDLE && request) curr_state <= ST_DATA;
        else if (HREADY) curr_state <= next_state;
    end

    // LATCH ADDRESS/CONTROL (For wait states)
    always @(posedge HCLK or negedge HRESETn) begin
        if (!HRESETn) begin
            addr_lat <= 32'h0;
            size_lat <= HSIZE_WORD;
            write_lat <= 1'b0;
        end
        else if (curr_state == ST_IDLE && request) begin
            addr_lat <= addr_i;
            size_lat <= encode_size(size_i);
            write_lat <= write_req_i;
        end
        else if (curr_state == ST_DATA && HREADY && request) begin
            addr_lat <= addr_i;
            size_lat <= encode_size(size_i);
            write_lat <= write_req_i;
        end
    end

    // DATA PHASE INFO (For read extraction)
    always @(posedge HCLK or negedge HRESETn) begin
        if (!HRESETn) begin
            addr_data <= 32'h0;
            size_data <= HSIZE_WORD;
        end
        else if (curr_state == ST_IDLE && request) begin
            addr_data <= addr_i;
            size_data <= encode_size(size_i);
        end
        else if (curr_state == ST_DATA && HREADY && request) begin
            addr_data <= addr_i;
            size_data <= encode_size(size_i);
        end
    end


    // ADDRESS/CONTROL OUTPUTS
    always @(*) begin
        HBURST = HBURST_SINGLE;
        HMASTLOCK = 1'b0;
        HPROT = HPROT_DEFAULT;
        HADDR = 32'h0;
        HSIZE = HSIZE_WORD;
        HTRANS = HTRANS_IDLE;
        HWRITE = 1'b0;

        case (curr_state)
            ST_IDLE: begin
                if (request) begin
                    HADDR = addr_i;
                    HSIZE = encode_size(size_i);
                    HTRANS = HTRANS_NONSEQ;
                    HWRITE = write_req_i;
                end
            end

            ST_DATA: begin
                if (!HREADY) begin
                    HADDR = addr_lat;
                    HSIZE = size_lat;
                    HTRANS = HTRANS_NONSEQ;
                    HWRITE = write_lat;
                end
                else if (request) begin
                    HADDR = addr_i;
                    HSIZE = encode_size(size_i);
                    HTRANS = HTRANS_NONSEQ;
                    HWRITE = write_req_i;
                end
            end

            ST_ERROR: HTRANS = HTRANS_IDLE;
        endcase
    end

    // WRITE DATA
    reg [31:0] wdata_lat; //Latch to hold for b2b writes
    always @(posedge HCLK or negedge HRESETn) begin
        if (!HRESETn) wdata_lat <= 32'h0;
        else if (curr_state == ST_IDLE && write_req_i) wdata_lat <= wdata_i;
        else if (curr_state == ST_DATA && HREADY && write_req_i) wdata_lat <= wdata_i;
    end

    always @(*) HWDATA = wdata_lat;


    // READ DATA
    reg [31:0] rdata_extracted;
    reg [31:0] rdata_held;

    wire read_complete = (curr_state == ST_DATA) && HREADY && (HRESP == HRESP_OKAY);

    always @(*) begin
        case (size_data)
            HSIZE_BYTE: begin
                case (addr_data[1:0])
                    2'b00: rdata_extracted = {24'h0, HRDATA[7:0]};
                    2'b01: rdata_extracted = {24'h0, HRDATA[15:8]};
                    2'b10: rdata_extracted = {24'h0, HRDATA[23:16]};
                    2'b11: rdata_extracted = {24'h0, HRDATA[31:24]};
                endcase
            end

            HSIZE_HALFWORD: begin
                if (addr_data[1]) rdata_extracted = {16'h0, HRDATA[31:16]};
                else rdata_extracted = {16'h0, HRDATA[15:0]};
            end

            default: rdata_extracted = HRDATA;
        endcase
    end

    always @(*) begin
        if (read_complete) rdata_o = rdata_extracted; // Live data when completing read
        else rdata_o = rdata_held; // Held value otherwise
    end

    //Hold read data for after the deassertion
    always @(posedge HCLK or negedge HRESETn) begin
        if (!HRESETn) rdata_held <= 32'h0;
        else if (read_complete) rdata_held <= rdata_extracted;
    end

    // CPU STATUS OUTPUTS
    assign ready_o = (curr_state == ST_DATA) && HREADY && (HRESP == HRESP_OKAY);
    assign error_o = (curr_state == ST_DATA) && HREADY && (HRESP == HRESP_ERROR);

endmodule
