`timescale 1ns / 1ps
// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2025-2026 Dylan Thornburg and Bryce Kelly
//
// This file is part of the Open-Source ARM Cortex-M0 project.
// Licensed under the GNU General Public License v3.0 or later.
// See the LICENSE file at the root of this repository.
//////////////////////////////////////////////////////////////////////////////////
// Create Date: 03/01/2026 01:04:51 PM
// Module Name: NVIC
// Description: Nested vectored interrupt controller. Resolves pending and execution
// priority with a parallel tournament tree.
//
// No debug aspects
// Address range: 0xE000E100 - 0xE000ECFF
//////////////////////////////////////////////////////////////////////////////////


module NVIC (
    input clk,
    input rst_n,

    // Register Interface (from core)
    input [11:0] reg_addr,
    input [31:0] reg_wdata,
    input reg_wr,
    output reg [31:0] nvic_rdata,

    // External Interrupt Inputs
    input [31:0] irq_i, // GPIO will go here

    // Core Interface (inputs & handshakes)
    input PRIMASK,
    input exc_taken,
    input [5:0] exc_taken_num,
    input exc_return,
    input [5:0] exc_return_num,

    // System exception pending (from SCB)
    input nmi_pend,
    input hardfault_pend,
    input svcall_pend,
    input pendsv_pend,
    input systick_pend,

    // System exception priorities (from SCB)
    input [1:0] svcall_pri, // SHPR2[31:30]
    input [1:0] pendsv_pri, // SHPR3[23:22]
    input [1:0] systick_pri, // SHPR3[31:30]

    // VECTCLRACTIVE pulse (from SCB)
    input VECTCLRACTIVE,

    // Core Interface (outputs)
    output int_pend,
    output [5:0] int_pend_num,

    // Feedback to SCB (for ICSR read)
    output isrpending, // any enabled external IRQ pending
    output [8:0] vectpending // highest priority pending exc number
);

    //////////////////////////////////////////////////////////////////////////////////
    /* NVIC REGISTER OFFSETS | RELATIVE TO 0xE000E000 */
    //////////////////////////////////////////////////////////////////////////////////

    localparam A_ISER = 12'h100;
    localparam A_ICER = 12'h180;
    localparam A_ISPR = 12'h200;
    localparam A_ICPR = 12'h280;
    localparam A_IPR_BASE = 12'h400;
    localparam A_IPR_END = 12'h41C;

    // Internal priority encoding: lower = higher priority
    localparam [2:0] PRI_NMI = 3'd1; // NMI(-2)-> 1
    localparam [2:0] PRI_HF = 3'd2; // HardFault (-1)->2
    localparam [2:0] PRI_THREAD = 3'd7; // config 0->3, 1->4, 2->5, 3->6, Thread->7

    //////////////////////////////////////////////////////////////////////////////////
    /* REGS */
    //////////////////////////////////////////////////////////////////////////////////

    reg [31:0] irq_enable;
    reg [31:0] irq_pending;
    reg [1:0] irq_priority [0:31]; // M0 only uses 2 bit priority of 8-bit field ([7:6] of [7:0])

    reg [47:0] exc_active; // slot 0 unused, slot 1 reset, 2-47 are real

    reg [2:0] best_pend_pri;
    reg [5:0] best_pend_num;
    reg [2:0] exec_pri;
    integer i;

    //////////////////////////////////////////////////////////////////////////////////
    /* IRQ SYNCHRONIZATION */
    /* External interrupts asynch. Use 2-flop synchronizer */
    //////////////////////////////////////////////////////////////////////////////////

    reg [31:0] irq_sync1, irq_sync2, irq_sync_prev;

    wire [31:0] irq_sync = irq_sync2;
    wire [31:0] irq_rising = irq_sync2 & ~irq_sync_prev;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            irq_sync1 <= 32'd0;
            irq_sync2 <= 32'd0;
            irq_sync_prev <= 32'd0;
        end
        else begin
            irq_sync1 <= irq_i;
            irq_sync2 <= irq_sync1;
            irq_sync_prev <= irq_sync2;
        end
    end

    //////////////////////////////////////////////////////////////////////////////////
    /* WRITE DECODE */
    //////////////////////////////////////////////////////////////////////////////////

    wire wr_iser = reg_wr & (reg_addr == A_ISER);
    wire wr_icer = reg_wr & (reg_addr == A_ICER);
    wire wr_ispr = reg_wr & (reg_addr == A_ISPR);
    wire wr_icpr = reg_wr & (reg_addr == A_ICPR);
    wire wr_ipr = reg_wr & (reg_addr >= A_IPR_BASE) & (reg_addr <= A_IPR_END) & (reg_addr[1:0] == 2'b00);

    wire [2:0] ipr_idx = reg_addr[4:2];

    //////////////////////////////////////////////////////////////////////////////////
    /* EXTERNAL IRQ PENDING */
    //////////////////////////////////////////////////////////////////////////////////

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) irq_pending <= 32'd0;
        else begin
            for (i = 0; i < 32; i = i + 1) begin
                if (exc_taken && exc_taken_num == (6'd16 + i[5:0])) irq_pending[i] <= irq_rising[i] | (wr_ispr & reg_wdata[i]);
                else if (irq_rising[i] | // interrupt triggered off of synchronizer
                        (irq_sync[i] & exc_return & (exc_return_num == (6'd16 + i[5:0]))) | // interrupt still high after clearing
                        (irq_sync[i] & VECTCLRACTIVE) | // interrupt still high after bulk clearing with VECTCLRACTIVE
                        (wr_ispr & reg_wdata[i])) // Software writes set pending
                        irq_pending[i] <= 1'b1;
                else if (wr_icpr & reg_wdata[i] & ~irq_sync[i]) irq_pending[i] <= 1'b0; // clear pending
            end
        end
    end

    //////////////////////////////////////////////////////////////////////////////////
    /* IRQ ENABLE (ISER/ICER) */
    //////////////////////////////////////////////////////////////////////////////////

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) irq_enable <= 32'd0;
        else if (wr_iser) irq_enable <= irq_enable | reg_wdata;
        else if (wr_icer) irq_enable <= irq_enable & ~reg_wdata;
    end

    //////////////////////////////////////////////////////////////////////////////////
    /* EXCEPTION ACTIVE TRACKING */
    //////////////////////////////////////////////////////////////////////////////////

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) exc_active <= 48'd0;
        else begin
            if (VECTCLRACTIVE) exc_active <= 48'd0;
            else begin
                if (exc_taken) exc_active[exc_taken_num] <= 1'b1;
                if (exc_return) exc_active[exc_return_num] <= 1'b0;
            end
        end
    end

    //////////////////////////////////////////////////////////////////////////////////
    /* IPR REGISTER WRITES */
    //////////////////////////////////////////////////////////////////////////////////

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i = 0; i < 32; i = i + 1) irq_priority[i] <= 2'b00;
        end
        else begin
            if (wr_ipr) begin
                irq_priority[{ipr_idx, 2'd0}] <= reg_wdata[7:6]; // N
                irq_priority[{ipr_idx, 2'd1}] <= reg_wdata[15:14]; // N+1
                irq_priority[{ipr_idx, 2'd2}] <= reg_wdata[23:22]; // N+2
                irq_priority[{ipr_idx, 2'd3}] <= reg_wdata[31:30]; // N+3
            end
        end
    end

    //////////////////////////////////////////////////////////////////////////////////
    /* PRIORITY RESOLVER (PENDING) - parallel tournament tree                       */
    /*                                                                              */
    /* Replaces the serial 37-stage compare chain (the 46-logic-level critical      */
    /* path through hardfault_pend in the timing report) with a log-depth argmin    */
    /* tree. Semantics are identical to the serial scan for every input:            */
    /*   - candidates are ordered by exception number (NMI 2, HF 3, SVC 11,         */
    /*     PendSV 14, SysTick 15, IRQ0..31 = 16..47) with the reset default         */
    /*     (PRI_THREAD, num 0) as slot 0                                            */
    /*   - the serial scan's strict < update means the earliest candidate wins      */
    /*     ties; the tree reproduces this with left-preference (l_pri <= r_pri)     */
    /*   - invalid candidates carry priority 3'd7, which never beats the slot-0     */
    /*     default on a tie, so the no-candidate result is (PRI_THREAD, 0) exactly  */
    /* Valid candidate priorities are at most 3'd6 ({1'b0,2-bit}+3), so 3'd7 is a   */
    /* strict sentinel.                                                             */
    //////////////////////////////////////////////////////////////////////////////////

    wire [2:0] pend_pri_a [0:63];
    wire [5:0] pend_num_a [0:63];

    assign pend_pri_a[0] = PRI_THREAD;                                   assign pend_num_a[0] = 6'd0;
    assign pend_pri_a[1] = nmi_pend       ? PRI_NMI : 3'd7;              assign pend_num_a[1] = 6'd2;
    assign pend_pri_a[2] = hardfault_pend ? PRI_HF  : 3'd7;              assign pend_num_a[2] = 6'd3;
    assign pend_pri_a[3] = svcall_pend    ? ({1'b0, svcall_pri}  + 2'd3) : 3'd7; assign pend_num_a[3] = 6'd11;
    assign pend_pri_a[4] = pendsv_pend    ? ({1'b0, pendsv_pri}  + 2'd3) : 3'd7; assign pend_num_a[4] = 6'd14;
    assign pend_pri_a[5] = systick_pend   ? ({1'b0, systick_pri} + 2'd3) : 3'd7; assign pend_num_a[5] = 6'd15;

    genvar gi;
    generate
        for (gi = 0; gi < 32; gi = gi + 1) begin : g_pend_cand
            assign pend_pri_a[6+gi] = (irq_pending[gi] && irq_enable[gi])
                                      ? ({1'b0, irq_priority[gi]} + 2'd3) : 3'd7;
            assign pend_num_a[6+gi] = 6'd16 + gi[5:0];
        end
        for (gi = 38; gi < 64; gi = gi + 1) begin : g_pend_pad
            assign pend_pri_a[gi] = 3'd7;
            assign pend_num_a[gi] = 6'd0;
        end
    endgenerate

    // Tournament reduction: 64 -> 32 -> 16 -> 8 -> 4 -> 2 -> 1.
    // Left-preference on ties preserves the serial scan order exactly.
    wire [2:0] t1p [0:31]; wire [5:0] t1n [0:31];
    wire [2:0] t2p [0:15]; wire [5:0] t2n [0:15];
    wire [2:0] t3p [0:7];  wire [5:0] t3n [0:7];
    wire [2:0] t4p [0:3];  wire [5:0] t4n [0:3];
    wire [2:0] t5p [0:1];  wire [5:0] t5n [0:1];
    generate
        for (gi = 0; gi < 32; gi = gi + 1) begin : g_t1
            assign t1p[gi] = (pend_pri_a[2*gi] <= pend_pri_a[2*gi+1]) ? pend_pri_a[2*gi] : pend_pri_a[2*gi+1];
            assign t1n[gi] = (pend_pri_a[2*gi] <= pend_pri_a[2*gi+1]) ? pend_num_a[2*gi] : pend_num_a[2*gi+1];
        end
        for (gi = 0; gi < 16; gi = gi + 1) begin : g_t2
            assign t2p[gi] = (t1p[2*gi] <= t1p[2*gi+1]) ? t1p[2*gi] : t1p[2*gi+1];
            assign t2n[gi] = (t1p[2*gi] <= t1p[2*gi+1]) ? t1n[2*gi] : t1n[2*gi+1];
        end
        for (gi = 0; gi < 8; gi = gi + 1) begin : g_t3
            assign t3p[gi] = (t2p[2*gi] <= t2p[2*gi+1]) ? t2p[2*gi] : t2p[2*gi+1];
            assign t3n[gi] = (t2p[2*gi] <= t2p[2*gi+1]) ? t2n[2*gi] : t2n[2*gi+1];
        end
        for (gi = 0; gi < 4; gi = gi + 1) begin : g_t4
            assign t4p[gi] = (t3p[2*gi] <= t3p[2*gi+1]) ? t3p[2*gi] : t3p[2*gi+1];
            assign t4n[gi] = (t3p[2*gi] <= t3p[2*gi+1]) ? t3n[2*gi] : t3n[2*gi+1];
        end
        for (gi = 0; gi < 2; gi = gi + 1) begin : g_t5
            assign t5p[gi] = (t4p[2*gi] <= t4p[2*gi+1]) ? t4p[2*gi] : t4p[2*gi+1];
            assign t5n[gi] = (t4p[2*gi] <= t4p[2*gi+1]) ? t4n[2*gi] : t4n[2*gi+1];
        end
    endgenerate

    always @(*) begin
        best_pend_pri = (t5p[0] <= t5p[1]) ? t5p[0] : t5p[1];
        best_pend_num = (t5p[0] <= t5p[1]) ? t5n[0] : t5n[1];
    end

    //////////////////////////////////////////////////////////////////////////////////
    /* EXECUTION PRIORITY (ACTIVE) - parallel min tree                              */
    /*                                                                              */
    /* The serial scan computes the minimum over PRI_THREAD and every active        */
    /* exception's priority (only the value is used, so tie order is irrelevant).   */
    /* Inactive slots carry the 3'd7 sentinel; slot 0 carries PRI_THREAD, so the    */
    /* no-active result is PRI_THREAD exactly. The PRIMASK clamp is unchanged.      */
    //////////////////////////////////////////////////////////////////////////////////

    reg [2:0] active_pri;

    wire [2:0] act_pri_a [0:63];
    assign act_pri_a[0] = PRI_THREAD;
    assign act_pri_a[1] = exc_active[2]  ? PRI_NMI : 3'd7;
    assign act_pri_a[2] = exc_active[3]  ? PRI_HF  : 3'd7;
    assign act_pri_a[3] = exc_active[11] ? ({1'b0, svcall_pri}  + 2'd3) : 3'd7;
    assign act_pri_a[4] = exc_active[14] ? ({1'b0, pendsv_pri}  + 2'd3) : 3'd7;
    assign act_pri_a[5] = exc_active[15] ? ({1'b0, systick_pri} + 2'd3) : 3'd7;
    generate
        for (gi = 0; gi < 32; gi = gi + 1) begin : g_act_cand
            assign act_pri_a[6+gi] = exc_active[16+gi] ? ({1'b0, irq_priority[gi]} + 2'd3) : 3'd7;
        end
        for (gi = 38; gi < 64; gi = gi + 1) begin : g_act_pad
            assign act_pri_a[gi] = 3'd7;
        end
    endgenerate

    wire [2:0] a1 [0:31];
    wire [2:0] a2 [0:15];
    wire [2:0] a3 [0:7];
    wire [2:0] a4 [0:3];
    wire [2:0] a5 [0:1];
    generate
        for (gi = 0; gi < 32; gi = gi + 1) begin : g_a1
            assign a1[gi] = (act_pri_a[2*gi] <= act_pri_a[2*gi+1]) ? act_pri_a[2*gi] : act_pri_a[2*gi+1];
        end
        for (gi = 0; gi < 16; gi = gi + 1) begin : g_a2
            assign a2[gi] = (a1[2*gi] <= a1[2*gi+1]) ? a1[2*gi] : a1[2*gi+1];
        end
        for (gi = 0; gi < 8; gi = gi + 1) begin : g_a3
            assign a3[gi] = (a2[2*gi] <= a2[2*gi+1]) ? a2[2*gi] : a2[2*gi+1];
        end
        for (gi = 0; gi < 4; gi = gi + 1) begin : g_a4
            assign a4[gi] = (a3[2*gi] <= a3[2*gi+1]) ? a3[2*gi] : a3[2*gi+1];
        end
        for (gi = 0; gi < 2; gi = gi + 1) begin : g_a5
            assign a5[gi] = (a4[2*gi] <= a4[2*gi+1]) ? a4[2*gi] : a4[2*gi+1];
        end
    endgenerate

    always @(*) begin
        active_pri = (a5[0] <= a5[1]) ? a5[0] : a5[1];
        exec_pri = active_pri;
        if (PRIMASK && (2'd3 < exec_pri)) exec_pri = 2'd3;
    end

    //////////////////////////////////////////////////////////////////////////////////
    /* PREEMPTION OUTPUT */
    //////////////////////////////////////////////////////////////////////////////////

    assign int_pend = (best_pend_pri < exec_pri);
    assign int_pend_num = best_pend_num;

    //////////////////////////////////////////////////////////////////////////////////
    /* FEEDBACK TO SCB */
    //////////////////////////////////////////////////////////////////////////////////

    assign isrpending = ((irq_pending & irq_enable) != 0);
    assign vectpending = {3'b000, best_pend_num};

    //////////////////////////////////////////////////////////////////////////////////
    /* REGISTER READ MUX */
    //////////////////////////////////////////////////////////////////////////////////

    wire ipr_range = (reg_addr >= A_IPR_BASE) & (reg_addr <= A_IPR_END) & (reg_addr[1:0] == 2'b00);

    always @(*) begin
        nvic_rdata = 32'd0;

        if (reg_addr == A_ISER || reg_addr == A_ICER) nvic_rdata = irq_enable;

        else if (reg_addr == A_ISPR || reg_addr == A_ICPR) nvic_rdata = irq_pending;

        else if (ipr_range) begin
            nvic_rdata[7:6] = irq_priority[{reg_addr[4:2], 2'd0}];
            nvic_rdata[15:14] = irq_priority[{reg_addr[4:2], 2'd1}];
            nvic_rdata[23:22] = irq_priority[{reg_addr[4:2], 2'd2}];
            nvic_rdata[31:30] = irq_priority[{reg_addr[4:2], 2'd3}];
        end
    end
endmodule
