`timescale 1ns / 1ps
// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2025-2026 Dylan Thornburg and Bryce Kelly
//
// This file is part of the Open-Source ARM Cortex-M0 project.
// Licensed under the GNU General Public License v3.0 or later.
// See the LICENSE file at the root of this repository.
//////////////////////////////////////////////////////////////////////////////////
// Module Name: bench_leds
// Description: Front-panel status for the CoreMark run, driven off the bench_io
//              STATUS register at 0x40000004.
//
//   All sixteen Nexys A7 user LEDs are green, so "the green LED" is simply one of
//   them. led[7] is the one to watch: it FLASHES on a validated CRC pass.
//
//     led[0]  heartbeat, ~1 Hz. Proves the clock and reset are alive even if the
//             CPU is wedged. If this is dark, the problem is the clock, not the core.
//     led[1]  RUNNING   (STATUS = 0xA5)  -- portable_init has executed
//     led[2]  DONE      (STATUS = 1/2/3) -- CoreMark reached the end
//     led[6]  FAIL, solid   (STATUS = 2)
//     led[7]  PASS, flashing ~2 Hz (STATUS = 1)
//
//   Status encoding matches Core/Inc/fpga_coremark_mmio.h:
//     1 = PASS, 2 = FAIL, 3 = UNKNOWN, 0xA5 = RUNNING
//////////////////////////////////////////////////////////////////////////////////

module bench_leds #(
    parameter integer CLK_HZ = 50_000_000
)(
    input             clk,
    input             rst_n,
    input      [31:0] status,
    output reg [7:0]  led
);

    localparam [31:0] ST_PASS    = 32'd1;
    localparam [31:0] ST_FAIL    = 32'd2;
    localparam [31:0] ST_UNKNOWN = 32'd3;
    localparam [31:0] ST_RUNNING = 32'h000000A5;

    // ~1 Hz heartbeat and ~2 Hz flash from one free-running counter.
    localparam integer HALF_SEC = CLK_HZ / 2;
    localparam integer QTR_SEC  = CLK_HZ / 4;

    reg [31:0] cnt;
    reg        beat_1hz;
    reg        flash_2hz;
    reg [31:0] cnt2;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cnt <= 32'd0; beat_1hz <= 1'b0;
        end
        else if (cnt >= HALF_SEC - 1) begin
            cnt <= 32'd0; beat_1hz <= ~beat_1hz;
        end
        else cnt <= cnt + 32'd1;
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cnt2 <= 32'd0; flash_2hz <= 1'b0;
        end
        else if (cnt2 >= QTR_SEC - 1) begin
            cnt2 <= 32'd0; flash_2hz <= ~flash_2hz;
        end
        else cnt2 <= cnt2 + 32'd1;
    end

    wire running = (status == ST_RUNNING);
    wire done    = (status == ST_PASS) | (status == ST_FAIL) | (status == ST_UNKNOWN);
    wire passed  = (status == ST_PASS);
    wire failed  = (status == ST_FAIL);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) led <= 8'h00;
        else begin
            led[0] <= beat_1hz;
            led[1] <= running;
            led[2] <= done;
            led[3] <= 1'b0;
            led[4] <= 1'b0;
            led[5] <= 1'b0;
            led[6] <= failed;                  // solid
            led[7] <= passed & flash_2hz;      // FLASHING = CRC pass
        end
    end

endmodule
