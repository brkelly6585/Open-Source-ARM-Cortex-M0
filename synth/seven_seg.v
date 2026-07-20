`timescale 1ns / 1ps
// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2025-2026 Dylan Thornburg and Bryce Kelly
//
// This file is part of the Open-Source ARM Cortex-M0 project.
// Licensed under the GNU General Public License v3.0 or later.
// See the LICENSE file at the root of this repository.
//////////////////////////////////////////////////////////////////////////////////
// Module Name: seven_seg
// Description: 8-digit hexadecimal display driver for the Nexys A7 seven-segment
//              display.
//
//   The Nexys A7's eight digits share ONE set of seven cathodes. Only one digit
//   can physically be lit at a time, so the digits are time-multiplexed: light
//   digit 0, then 1, then 2 ... fast enough that persistence of vision makes all
//   eight look continuously on. That is the whole job of this module.
//
//   Both the anodes (an) and the cathodes (seg, dp) are ACTIVE LOW on this board.
//
//   REFRESH_HZ is the rate at which the whole 8-digit scan repeats. Anything from
//   roughly 60 Hz up is flicker-free; 500 Hz is a comfortable default and is well
//   below any ghosting threshold. The digit dwell time is 1 / (8 * REFRESH_HZ).
//
//   CLK_HZ must be the frequency of the clock actually driving this module. It is
//   only used to size the scan divider, so being off by a little is harmless.
//////////////////////////////////////////////////////////////////////////////////

module seven_seg #(
    parameter integer CLK_HZ     = 50_000_000,
    parameter integer REFRESH_HZ = 500
)(
    input             clk,
    input             rst_n,

    input      [31:0] value,      // displayed as 8 hex digits, digit 0 = LSB
    input      [7:0]  dp_mask,    // 1 = light that digit's decimal point
    input      [7:0]  blank,      // 1 = blank that digit entirely

    output reg [7:0]  an,         // active low digit enables
    output reg [6:0]  seg,        // active low, {g,f,e,d,c,b,a}
    output reg        dp          // active low
);

    // One tick per digit. 8 digits per full refresh.
    localparam integer DIV = CLK_HZ / (REFRESH_HZ * 8);

    reg [31:0] div_cnt;
    reg [2:0]  digit;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            div_cnt <= 32'd0;
            digit   <= 3'd0;
        end
        else if (div_cnt >= DIV - 1) begin
            div_cnt <= 32'd0;
            digit   <= digit + 3'd1;
        end
        else begin
            div_cnt <= div_cnt + 32'd1;
        end
    end

    // Select this digit's nibble
    reg [3:0] nib;
    always @(*) begin
        case (digit)
            3'd0: nib = value[3:0];
            3'd1: nib = value[7:4];
            3'd2: nib = value[11:8];
            3'd3: nib = value[15:12];
            3'd4: nib = value[19:16];
            3'd5: nib = value[23:20];
            3'd6: nib = value[27:24];
            3'd7: nib = value[31:28];
        endcase
    end

    // Hex to segments. Active low, bit order {g,f,e,d,c,b,a}.
    reg [6:0] seg_n;
    always @(*) begin
        case (nib)
            4'h0: seg_n = 7'b100_0000;
            4'h1: seg_n = 7'b111_1001;
            4'h2: seg_n = 7'b010_0100;
            4'h3: seg_n = 7'b011_0000;
            4'h4: seg_n = 7'b001_1001;
            4'h5: seg_n = 7'b001_0010;
            4'h6: seg_n = 7'b000_0010;
            4'h7: seg_n = 7'b111_1000;
            4'h8: seg_n = 7'b000_0000;
            4'h9: seg_n = 7'b001_0000;
            4'hA: seg_n = 7'b000_1000;
            4'hB: seg_n = 7'b000_0011;
            4'hC: seg_n = 7'b100_0110;
            4'hD: seg_n = 7'b010_0001;
            4'hE: seg_n = 7'b000_0110;
            4'hF: seg_n = 7'b000_1110;
            default: seg_n = 7'b111_1111;
        endcase
    end

    // Register the outputs so the anodes and cathodes switch on the same edge.
    // Driving them from combinational logic causes visible ghosting: the anode of
    // the next digit can turn on while the previous digit's segments are still
    // settling, so a faint image of one digit bleeds onto its neighbour.
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            an  <= 8'hFF;      // all digits off
            seg <= 7'h7F;      // all segments off
            dp  <= 1'b1;       // decimal point off
        end
        else begin
            an  <= blank[digit] ? 8'hFF : ~(8'b1 << digit);
            seg <= blank[digit] ? 7'h7F : seg_n;
            dp  <= ~dp_mask[digit];
        end
    end

endmodule
