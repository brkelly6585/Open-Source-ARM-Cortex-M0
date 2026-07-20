`timescale 1ns / 1ps
// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2025-2026 Dylan Thornburg and Bryce Kelly
//
// This file is part of the Open-Source ARM Cortex-M0 project.
// Licensed under the GNU General Public License v3.0 or later.
// See the LICENSE file at the root of this repository.
//////////////////////////////////////////////////////////////////////////////////
// Module Name: ahb_mem.v
// Description: Synchronous memory for AHB slave.
//   Revision 0.03 - Read is now a TRUE registered-output read so the array infers as
//   block RAM (BRAM requires a registered read; an async `wire = mem[addr]` can only map
//   to distributed RAM/LUTs). Latency is unchanged: the read port takes the ADDRESS-PHASE
//   address (mem_raddr_ap) and registers the output, so data still arrives in the data
//   phase exactly as the old registered-address + combinational-read did. The write port
//   still uses the data-phase address (mem_waddr). A RAW forward covers the same-cycle
//   write/read-launch collision to the same word (LDR immediately after STR to that word).
//////////////////////////////////////////////////////////////////////////////////
module ahb_mem#(
    parameter INIT_FILE = "",
    parameter WORDS = 1024
)(
    input HCLK,
    input mem_write,
    input [31:0] mem_raddr_ap,   // ADDRESS-PHASE read address (HADDR) -> registered read
    input [31:0] mem_waddr,      // data-phase write address (HADDR_reg)
    input [31:0] mem_wdata,
    input [3:0]  mem_byte_en,
    output [31:0] mem_rdata
);
    localparam AW = $clog2(WORDS);
    reg [31:0] mem [0:WORDS-1];

    wire [AW-1:0] wr_word_addr = mem_waddr[AW+1:2];
    wire [AW-1:0] rd_word_addr = mem_raddr_ap[AW+1:2];

    integer ii;
    initial begin
        for (ii = 0; ii < WORDS; ii = ii + 1) mem[ii] = 32'd0;
        if (INIT_FILE != "") $readmemh(INIT_FILE, mem);
    end

    // ---- byte-enable decode (combinational, unchanged from rev 0.02) ----
    reg [7:0] wdata_byte0, wdata_byte1, wdata_byte2, wdata_byte3;
    reg wen0, wen1, wen2, wen3;
    always @(*) begin
        wdata_byte0 = mem_wdata[7:0];
        wdata_byte1 = mem_wdata[7:0];
        wdata_byte2 = mem_wdata[7:0];
        wdata_byte3 = mem_wdata[7:0];
        wen0 = 1'b0; wen1 = 1'b0; wen2 = 1'b0; wen3 = 1'b0;
        if (mem_byte_en[0] & mem_byte_en[1] & mem_byte_en[2] & mem_byte_en[3]) begin
            wdata_byte0 = mem_wdata[7:0];  wdata_byte1 = mem_wdata[15:8];
            wdata_byte2 = mem_wdata[23:16]; wdata_byte3 = mem_wdata[31:24];
            wen0 = 1'b1; wen1 = 1'b1; wen2 = 1'b1; wen3 = 1'b1;
        end
        else if ((mem_byte_en[0] & mem_byte_en[1]) & ~(mem_byte_en[2] & mem_byte_en[3])) begin
            wdata_byte0 = mem_wdata[7:0]; wdata_byte1 = mem_wdata[15:8];
            wen0 = 1'b1; wen1 = 1'b1;
        end
        else if (~(mem_byte_en[0] & mem_byte_en[1]) & (mem_byte_en[2] & mem_byte_en[3])) begin
            wdata_byte2 = mem_wdata[7:0]; wdata_byte3 = mem_wdata[15:8];
            wen2 = 1'b1; wen3 = 1'b1;
        end
        else if (mem_byte_en[0]) begin wdata_byte0 = mem_wdata[7:0]; wen0 = 1'b1; end
        else if (mem_byte_en[1]) begin wdata_byte1 = mem_wdata[7:0]; wen1 = 1'b1; end
        else if (mem_byte_en[2]) begin wdata_byte2 = mem_wdata[7:0]; wen2 = 1'b1; end
        else if (mem_byte_en[3]) begin wdata_byte3 = mem_wdata[7:0]; wen3 = 1'b1; end
    end

    // ---- write (posedge, byte enabled) : unchanged ----
    always @(posedge HCLK) begin
        if (mem_write && wen0) mem[wr_word_addr][7:0]   <= wdata_byte0;
        if (mem_write && wen1) mem[wr_word_addr][15:8]  <= wdata_byte1;
        if (mem_write && wen2) mem[wr_word_addr][23:16] <= wdata_byte2;
        if (mem_write && wen3) mem[wr_word_addr][31:24] <= wdata_byte3;
    end

    // ---- registered read (infers BRAM) ----
    reg [31:0] mem_rdata_q;
    always @(posedge HCLK) mem_rdata_q <= mem[rd_word_addr];

    // ---- RAW forward: write (data phase) and read-launch (addr phase) hit same word
    //      on the same edge -> the registered read sees the OLD word, so forward the
    //      just-written bytes over it in the following (data-phase) cycle. ----
    wire raw_hit = mem_write && (wr_word_addr == rd_word_addr);
    reg f0, f1, f2, f3;
    reg [7:0] fb0, fb1, fb2, fb3;
    always @(posedge HCLK) begin
        f0 <= raw_hit && wen0;  fb0 <= wdata_byte0;
        f1 <= raw_hit && wen1;  fb1 <= wdata_byte1;
        f2 <= raw_hit && wen2;  fb2 <= wdata_byte2;
        f3 <= raw_hit && wen3;  fb3 <= wdata_byte3;
    end

    wire [7:0] out0 = f0 ? fb0 : mem_rdata_q[7:0];
    wire [7:0] out1 = f1 ? fb1 : mem_rdata_q[15:8];
    wire [7:0] out2 = f2 ? fb2 : mem_rdata_q[23:16];
    wire [7:0] out3 = f3 ? fb3 : mem_rdata_q[31:24];
    assign mem_rdata = {out3, out2, out1, out0};
endmodule
