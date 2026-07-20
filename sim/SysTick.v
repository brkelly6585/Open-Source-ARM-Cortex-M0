`timescale 1ns / 1ps
// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2025-2026 Dylan Thornburg and Bryce Kelly
//
// This file is part of the Open-Source ARM Cortex-M0 project.
// Licensed under the GNU General Public License v3.0 or later.
// See the LICENSE file at the root of this repository.
//////////////////////////////////////////////////////////////////////////////////
// Create Date: 03/09/2026 07:17:19 PM
// Module Name: SysTick
// Description: 24-bit system timer.
//
// No debug aspects
// Address range: 0xE000E010 - 0xE000E0FF
//////////////////////////////////////////////////////////////////////////////////
module SysTick (
    input clk,
    input rst_n,

    // Register Interface (from core)
    input [11:0] reg_addr,
    input [31:0] reg_wdata,
    input reg_wr,
    input reg_rd,
    output reg [31:0] syst_rdata,

    // Core Interface
    input core_halted, // freeze timer during debug halt

    // Output to SCB
    output systick_fire // 1-cycle pulse: counter wrapped with TICKINT enabled
);

    //////////////////////////////////////////////////////////////////////////////////
    /* REGISTER OFFSETS | RELATIVE TO 0xE000E000 */
    //////////////////////////////////////////////////////////////////////////////////

    localparam A_SYST_CSR = 12'h010;
    localparam A_SYST_RVR = 12'h014;
    localparam A_SYST_CVR = 12'h018;
    localparam A_SYST_CALIB = 12'h01C;

    //////////////////////////////////////////////////////////////////////////////////
    /* REGS */
    //////////////////////////////////////////////////////////////////////////////////

    reg syst_enable; // SYST_CSR[0]
    reg syst_tickint; // SYST_CSR[1]
    reg syst_clksource; // SYST_CSR[2]
    reg syst_countflag; // SYST_CSR[16]
    reg [23:0] syst_rvr;
    reg [23:0] syst_cvr;

    //////////////////////////////////////////////////////////////////////////////////
    /* WRITE DECODE */
    //////////////////////////////////////////////////////////////////////////////////

    wire wr_syst_csr = reg_wr & (reg_addr == A_SYST_CSR);
    wire wr_syst_rvr = reg_wr & (reg_addr == A_SYST_RVR);
    wire wr_syst_cvr = reg_wr & (reg_addr == A_SYST_CVR);
    wire rd_syst_csr = reg_rd & (reg_addr == A_SYST_CSR);

    wire syst_wrap = syst_enable & ~core_halted & (syst_cvr == 24'd1);

    //////////////////////////////////////////////////////////////////////////////////
    /* SYSTICK TIMER */
    //////////////////////////////////////////////////////////////////////////////////

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            syst_enable <= 1'b0;
            syst_tickint <= 1'b0;
            syst_clksource <= 1'b0;
            syst_countflag <= 1'b0;
            syst_rvr <= 24'd0;
            syst_cvr <= 24'd0;
        end
        else begin
            if (wr_syst_csr) begin
                syst_enable <= reg_wdata[0];
                syst_tickint <= reg_wdata[1];
                syst_clksource <= reg_wdata[2];
            end

            if (wr_syst_rvr) syst_rvr <= reg_wdata[23:0];

            if (wr_syst_cvr) begin
                syst_cvr <= 24'd0;
                syst_countflag <= 1'b0;
            end
            else begin
                if (syst_enable && !core_halted) begin // if core_halted, don't count down
                    if (syst_cvr == 24'd0) syst_cvr <= syst_rvr;
                    else begin
                        syst_cvr <= syst_cvr - 24'd1;
                        if (syst_cvr == 24'd1) syst_countflag <= 1'b1;
                    end
                end
                if (rd_syst_csr) syst_countflag <= 1'b0;
            end
        end
    end

    //////////////////////////////////////////////////////////////////////////////////
    /* OUTPUT */
    //////////////////////////////////////////////////////////////////////////////////

    assign systick_fire = syst_wrap & syst_tickint;

    //////////////////////////////////////////////////////////////////////////////////
    /* REGISTER READ MUX */
    //////////////////////////////////////////////////////////////////////////////////

    always @(*) begin
        syst_rdata = 32'd0;

        if (reg_addr == A_SYST_CSR) syst_rdata = {15'd0, syst_countflag, 13'd0, syst_clksource, syst_tickint, syst_enable};

        else if (reg_addr == A_SYST_RVR) syst_rdata = {8'd0, syst_rvr};

        else if (reg_addr == A_SYST_CVR) syst_rdata = {8'd0, syst_cvr};

        else if (reg_addr == A_SYST_CALIB) syst_rdata = 32'hC000_0000; // NOREF=1, SKEW=1, TENMS=0
    end

endmodule
