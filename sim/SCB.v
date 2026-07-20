`timescale 1ns / 1ps
// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2025-2026 Dylan Thornburg and Bryce Kelly
//
// This file is part of the Open-Source ARM Cortex-M0 project.
// Licensed under the GNU General Public License v3.0 or later.
// See the LICENSE file at the root of this repository.
//////////////////////////////////////////////////////////////////////////////////
// Create Date: 03/09/2026 07:15:37 PM
// Module Name: SCB
// Description: System control block. Holds the system exception pending state and
// priorities, and the system control and reset registers.
//
// No debug aspects
// Address range: 0xE000ED00 - 0xE000ED8F
//////////////////////////////////////////////////////////////////////////////////

module SCB (
    input clk,
    input rst_n,

    // Register Interface (from core)
    input [11:0] reg_addr,
    input [31:0] reg_wdata,
    input reg_wr,
    output reg [31:0] scb_rdata,

    // External NMI input (synchronized internally)
    input nmi_i,

    // Core Interface
    input [5:0] IPSR,
    input exc_taken,
    input [5:0] exc_taken_num,
    input svcall_req, // SVC instr detected
    input fault_req, // fault condition

    // SysTick fire (from SysTick module)
    input systick_fire,

    // NVIC feedback (for ICSR read)
    input isrpending, // any enabled external IRQ pending
    input [8:0] vectpending, // highest priority pending exc number

    // System exception pending (to NVIC)
    output reg nmi_pend,
    output reg hardfault_pend,
    output reg svcall_pend,
    output reg pendsv_pend,
    output reg systick_pend,

    // System exception priorities (to NVIC)
    output reg [1:0] svcall_pri, // SHPR2[31:30]
    output reg [1:0] pendsv_pri, // SHPR3[23:22]
    output reg [1:0] systick_pri, // SHPR3[31:30]

    // VECTCLRACTIVE pulse (to NVIC)
    output reg VECTCLRACTIVE,

    // Core outputs
    output SYSRESETREQ, // AIRCR bit[2]
    output SLEEPONEXIT, // SCR bit[1]
    output SLEEPDEEP, // SCR bit[2]
    output SEVONPEND // SCR bit[4]
);

    //////////////////////////////////////////////////////////////////////////////////
    /* REGISTER OFFSETS | RELATIVE TO 0xE000E000 */
    //////////////////////////////////////////////////////////////////////////////////

    localparam A_CPUID = 12'hD00;
    localparam A_ICSR = 12'hD04;
    localparam A_AIRCR = 12'hD0C;
    localparam A_SCR = 12'hD10;
    localparam A_CCR = 12'hD14;
    localparam A_SHPR2 = 12'hD1C;
    localparam A_SHPR3 = 12'hD20;
    localparam A_SHCSR = 12'hD24;

    //////////////////////////////////////////////////////////////////////////////////
    /* REGS */
    //////////////////////////////////////////////////////////////////////////////////

    reg scr_sevonpend;
    reg scr_sleepdeep;
    reg scr_sleeponexit;
    reg sysresetreq_r;

    //////////////////////////////////////////////////////////////////////////////////
    /* NMI SYNCHRONIZATION */
    /* NMI is asynch. Use 2-flop synchronizer */
    //////////////////////////////////////////////////////////////////////////////////

    reg nmi_sync1, nmi_sync2, nmi_sync_prev;
    wire nmi_rising = nmi_sync2 & ~nmi_sync_prev;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            nmi_sync1 <= 1'b0;
            nmi_sync2 <= 1'b0;
            nmi_sync_prev <= 1'b0;
        end
        else begin
            nmi_sync1 <= nmi_i;
            nmi_sync2 <= nmi_sync1;
            nmi_sync_prev <= nmi_sync2;
        end
    end

    //////////////////////////////////////////////////////////////////////////////////
    /* WRITE DECODE */
    //////////////////////////////////////////////////////////////////////////////////

    wire wr_icsr = reg_wr & (reg_addr == A_ICSR);
    wire wr_aircr = reg_wr & (reg_addr == A_AIRCR);
    wire wr_scr = reg_wr & (reg_addr == A_SCR);
    wire wr_shpr2 = reg_wr & (reg_addr == A_SHPR2);
    wire wr_shpr3 = reg_wr & (reg_addr == A_SHPR3);
    wire wr_shcsr = reg_wr & (reg_addr == A_SHCSR);

    wire aircr_key_ok = (reg_wdata[31:16] == 16'h05FA); // Reg write is unpredictable otherwise

    //////////////////////////////////////////////////////////////////////////////////
    /* NMI PENDING */
    //////////////////////////////////////////////////////////////////////////////////

    wire nmi_set = nmi_rising | (wr_icsr & reg_wdata[31]);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) nmi_pend <= 1'b0;
        else if (exc_taken && exc_taken_num == 6'd2) nmi_pend <= nmi_set;
        else if (nmi_set) nmi_pend <= 1'b1;
    end

    //////////////////////////////////////////////////////////////////////////////////
    /* HARDFAULT PENDING */
    //////////////////////////////////////////////////////////////////////////////////

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) hardfault_pend <= 1'b0;
        else if (exc_taken && exc_taken_num == 6'd3) hardfault_pend <= fault_req;
        else if (fault_req) hardfault_pend <= 1'b1;
    end

    //////////////////////////////////////////////////////////////////////////////////
    /* SVCALL PENDING */
    //////////////////////////////////////////////////////////////////////////////////

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) svcall_pend <= 1'b0;
        else if (exc_taken && exc_taken_num == 6'd11) svcall_pend <= svcall_req;
        else if (svcall_req) svcall_pend <= 1'b1;
        else if (wr_shcsr) svcall_pend <= reg_wdata[15];
    end

    //////////////////////////////////////////////////////////////////////////////////
    /* PENDSV PENDING */
    //////////////////////////////////////////////////////////////////////////////////

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) pendsv_pend <= 1'b0;
        else if (exc_taken && exc_taken_num == 6'd14) pendsv_pend <= 1'b0;
        else if (wr_icsr && reg_wdata[28]) pendsv_pend <= 1'b1;
        else if (wr_icsr && reg_wdata[27]) pendsv_pend <= 1'b0;
    end

    //////////////////////////////////////////////////////////////////////////////////
    /* SYSTICK PENDING */
    //////////////////////////////////////////////////////////////////////////////////

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) systick_pend <= 1'b0;
        else if (exc_taken && exc_taken_num == 6'd15) systick_pend <= systick_fire;
        else if (systick_fire) systick_pend <= 1'b1;
        else if (wr_icsr && reg_wdata[26]) systick_pend <= 1'b1;
        else if (wr_icsr && reg_wdata[25]) systick_pend <= 1'b0;
    end

    //////////////////////////////////////////////////////////////////////////////////
    /* AIRCR VECTCLRACTIVE */
    //////////////////////////////////////////////////////////////////////////////////

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) VECTCLRACTIVE <= 1'b0;
        else begin
            VECTCLRACTIVE <= 1'b0;
            if (wr_aircr && aircr_key_ok && reg_wdata[1]) VECTCLRACTIVE <= 1'b1;
        end
    end

    //////////////////////////////////////////////////////////////////////////////////
    /* SCB REGISTER WRITES */
    //////////////////////////////////////////////////////////////////////////////////

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            scr_sevonpend <= 1'b0;
            scr_sleepdeep <= 1'b0;
            scr_sleeponexit <= 1'b0;
            sysresetreq_r <= 1'b0;
            svcall_pri <= 2'b00;
            pendsv_pri <= 2'b00;
            systick_pri <= 2'b00;
        end
        else begin
            if (wr_aircr && aircr_key_ok) sysresetreq_r <= reg_wdata[2];
            else sysresetreq_r <= 1'b0;

            if (wr_scr) begin
                scr_sevonpend <= reg_wdata[4];
                scr_sleepdeep <= reg_wdata[2];
                scr_sleeponexit <= reg_wdata[1];
            end

            if (wr_shpr2) svcall_pri <= reg_wdata[31:30];

            if (wr_shpr3) begin
                systick_pri <= reg_wdata[31:30];
                pendsv_pri <= reg_wdata[23:22];
            end
        end
    end

    //////////////////////////////////////////////////////////////////////////////////
    /* REGISTER READ MUX */
    //////////////////////////////////////////////////////////////////////////////////

    wire [8:0] vectactive = {3'b000, IPSR};

    always @(*) begin
        scb_rdata = 32'd0;

        if (reg_addr == A_CPUID) scb_rdata = 32'h410CC200; // Cortex-M0 r0p0

        else if (reg_addr == A_ICSR) scb_rdata = {nmi_pend, 2'b00, pendsv_pend, 1'b0,
                                                    systick_pend, 3'b000, isrpending, 1'b0,
                                                    vectpending, 3'b000, vectactive}; // 1'b0s are because of write-only behavior

        else if (reg_addr == A_AIRCR) scb_rdata = {16'hFA05, 1'b0, 15'd0}; // little endian system | [15] -> 1 to change | FA05 chosen arbitrarily

        else if (reg_addr == A_SCR) scb_rdata = {27'd0, scr_sevonpend, 1'b0, scr_sleepdeep, scr_sleeponexit, 1'b0};

        else if (reg_addr == A_CCR) scb_rdata = 32'h00000208; // always this

        else if (reg_addr == A_SHPR2) scb_rdata = {svcall_pri, 30'd0};

        else if (reg_addr == A_SHPR3) scb_rdata = {systick_pri, 6'd0, pendsv_pri, 22'd0};

        else if (reg_addr == A_SHCSR) scb_rdata = {16'd0, svcall_pend, 15'd0};
    end

    //////////////////////////////////////////////////////////////////////////////////
    /* OUTPUTS */
    //////////////////////////////////////////////////////////////////////////////////

    assign SYSRESETREQ = sysresetreq_r;
    assign SLEEPONEXIT = scr_sleeponexit;
    assign SLEEPDEEP = scr_sleepdeep;
    assign SEVONPEND = scr_sevonpend;

endmodule
