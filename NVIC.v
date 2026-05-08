`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 03/01/2026 01:04:51 PM
// Design Name: 
// Module Name: NVIC
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
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
    /* PRIORITY RESOLVER (PENDING) */
    //////////////////////////////////////////////////////////////////////////////////

    reg [2:0] pr_cand;
    always @(*) begin
        best_pend_pri = PRI_THREAD;
        best_pend_num = 6'd0;
        pr_cand = 3'd0;

        if (nmi_pend) begin
            best_pend_pri = PRI_NMI;
            best_pend_num = 6'd2;
        end

        if (hardfault_pend && (PRI_HF < best_pend_pri)) begin
            best_pend_pri = PRI_HF;
            best_pend_num = 6'd3;
        end

        pr_cand = {1'b0, svcall_pri} + 2'd3; // 2d'3 offset
        if (svcall_pend && (pr_cand < best_pend_pri)) begin
            best_pend_pri = pr_cand;
            best_pend_num = 6'd11;
        end

        pr_cand = {1'b0, pendsv_pri} + 2'd3; // 2d'3 offset
        if (pendsv_pend && (pr_cand < best_pend_pri)) begin
            best_pend_pri = pr_cand;
            best_pend_num = 6'd14;
        end

        pr_cand = {1'b0, systick_pri} + 2'd3; // 2d'3 offset
        if (systick_pend && (pr_cand < best_pend_pri)) begin
            best_pend_pri = pr_cand;
            best_pend_num = 6'd15;
        end

        for (i = 0; i < 32; i = i + 1) begin
            pr_cand = {1'b0, irq_priority[i]} + 2'd3; // 2d'3 offset
            if (irq_pending[i] && irq_enable[i] && (pr_cand < best_pend_pri)) begin
                best_pend_pri = pr_cand;
                best_pend_num = 6'd16 + i[5:0];
            end
        end
    end

    //////////////////////////////////////////////////////////////////////////////////
    /* EXECUTION PRIORITY (ACTIVE) */
    //////////////////////////////////////////////////////////////////////////////////

    reg [2:0] ep_cand;
    reg [2:0] active_pri;

    always @(*) begin
        active_pri = PRI_THREAD;
        ep_cand = 3'd0;

        if (exc_active[2]) active_pri = PRI_NMI;

        if (exc_active[3] && PRI_HF < active_pri) active_pri = PRI_HF;

        if (exc_active[11]) begin
            ep_cand = {1'b0, svcall_pri} + 2'd3;
            if (ep_cand < active_pri) active_pri = ep_cand;
        end

        if (exc_active[14]) begin
            ep_cand = {1'b0, pendsv_pri} + 2'd3;
            if (ep_cand < active_pri) active_pri = ep_cand;
        end

        if (exc_active[15]) begin
            ep_cand = {1'b0, systick_pri} + 2'd3;
            if (ep_cand < active_pri) active_pri = ep_cand;
        end

        for (i = 0; i < 32; i = i + 1) begin
            if (exc_active[16 + i]) begin
                ep_cand = {1'b0, irq_priority[i]} + 2'd3;
                if (ep_cand < active_pri) active_pri = ep_cand;
            end
        end

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
