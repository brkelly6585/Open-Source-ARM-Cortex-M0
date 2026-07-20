`timescale 1ns / 1ps
// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2025-2026 Dylan Thornburg and Bryce Kelly
//
// This file is part of the Open-Source ARM Cortex-M0 project.
// Licensed under the GNU General Public License v3.0 or later.
// See the LICENSE file at the root of this repository.
//////////////////////////////////////////////////////////////////////////////////
// Module Name: bench_io
// Description: CoreMark benchmark I/O peripheral, AHB slave region 2.
//
//   Address map (base 0x40000000, matches Core/Inc/fpga_coremark_mmio.h):
//     0x00  CYCLE       RO  free-running 32-bit cycle counter, +1 per HCLK
//     0x04  STATUS      RW  1=PASS 2=FAIL 3=UNKNOWN 4=DONE 0xA5=RUNNING
//     0x08  TOTAL_CYC   RW  elapsed cycles reported by CoreMark
//     0x0C  ITERATIONS  RW
//     0x10  SEEDCRC     RW
//     0x14  CRCLIST     RW
//     0x18  CRCMATRIX   RW
//     0x1C  CRCSTATE    RW
//     0x20  CRCFINAL    RW
//     0x40  CONSOLE     WO  one ee_printf character, pulses console_valid
//
//   Presents the same memory-style interface as ahb_mem so it drops straight
//   into an ahb_second wrapper. Read address is captured on the negative edge
//   and read data registered on the positive edge, mirroring ahb_mem exactly,
//   so the AHB data phase lines up and HREADYOUT can stay high (zero wait).
//
//   The constant read latency on CYCLE is harmless: it is the same at
//   start_time() and stop_time(), so it cancels in the subtraction.
//////////////////////////////////////////////////////////////////////////////////

module bench_io (
    input             HCLK,
    input             HRESETn,

    // Memory-style interface (from ahb_second)
    input             mem_write,
    input      [31:0] mem_raddr,
    input      [31:0] mem_raddr_ap,
    input      [31:0] mem_waddr,
    input      [31:0] mem_wdata,
    input      [3:0]  mem_byte_en,
    output     [31:0] mem_rdata,

    // Observation outputs
    output reg [31:0] cycle_o,
    output reg [31:0] status_o,
    output reg [31:0] total_cycles_o,
    output reg [31:0] iterations_o,
    output reg [31:0] seedcrc_o,
    output reg [31:0] crclist_o,
    output reg [31:0] crcmatrix_o,
    output reg [31:0] crcstate_o,
    output reg [31:0] crcfinal_o,
    output reg [7:0]  console_data_o,
    output reg        console_valid_o
);

    localparam [5:0] A_CYCLE   = 6'h00,
                     A_STATUS  = 6'h01,
                     A_TOTCYC  = 6'h02,
                     A_ITER    = 6'h03,
                     A_SEEDCRC = 6'h04,
                     A_CRCLIST = 6'h05,
                     A_CRCMTX  = 6'h06,
                     A_CRCSTAT = 6'h07,
                     A_CRCFIN  = 6'h08,
                     A_CONSOLE = 6'h10;

    wire [5:0] w_idx = mem_waddr[7:2];

    // ---- free-running cycle counter ----
    always @(posedge HCLK or negedge HRESETn) begin
        if (!HRESETn) cycle_o <= 32'd0;
        else          cycle_o <= cycle_o + 32'd1;
    end

    // ---- register writes (software does 32-bit stores only) ----
    always @(posedge HCLK or negedge HRESETn) begin
        if (!HRESETn) begin
            status_o        <= 32'd0;
            total_cycles_o  <= 32'd0;
            iterations_o    <= 32'd0;
            seedcrc_o       <= 32'd0;
            crclist_o       <= 32'd0;
            crcmatrix_o     <= 32'd0;
            crcstate_o      <= 32'd0;
            crcfinal_o      <= 32'd0;
            console_data_o  <= 8'd0;
            console_valid_o <= 1'b0;
        end
        else begin
            console_valid_o <= 1'b0;   // single-cycle strobe
            if (mem_write && (mem_byte_en != 4'b0000)) begin
                case (w_idx)
                    A_STATUS : status_o       <= mem_wdata;
                    A_TOTCYC : total_cycles_o <= mem_wdata;
                    A_ITER   : iterations_o   <= mem_wdata;
                    A_SEEDCRC: seedcrc_o      <= mem_wdata;
                    A_CRCLIST: crclist_o      <= mem_wdata;
                    A_CRCMTX : crcmatrix_o    <= mem_wdata;
                    A_CRCSTAT: crcstate_o     <= mem_wdata;
                    A_CRCFIN : crcfinal_o     <= mem_wdata;
                    A_CONSOLE: begin
                        console_data_o  <= mem_wdata[7:0];
                        console_valid_o <= 1'b1;
                    end
                    default  : ; // CYCLE is read-only; other offsets ignored
                endcase
            end
        end
    end

    // ---- reads: mirror ahb_mem timing exactly ----
    // Select from the ADDRESS-PHASE address so the registered output is valid
    // during the data phase (1-cycle latency, matches ahb_mem / zero wait state).
    wire [5:0] rd_idx = mem_raddr_ap[7:2];

    reg [31:0] rdata_reg;
    always @(posedge HCLK) begin
        case (rd_idx)
            A_CYCLE  : rdata_reg <= cycle_o;
            A_STATUS : rdata_reg <= status_o;
            A_TOTCYC : rdata_reg <= total_cycles_o;
            A_ITER   : rdata_reg <= iterations_o;
            A_SEEDCRC: rdata_reg <= seedcrc_o;
            A_CRCLIST: rdata_reg <= crclist_o;
            A_CRCMTX : rdata_reg <= crcmatrix_o;
            A_CRCSTAT: rdata_reg <= crcstate_o;
            A_CRCFIN : rdata_reg <= crcfinal_o;
            default  : rdata_reg <= 32'd0;
        endcase
    end

    assign mem_rdata = rdata_reg;

endmodule
