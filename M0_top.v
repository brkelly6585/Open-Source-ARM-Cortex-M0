`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 02/09/2026 04:33:07 PM
// Design Name: 
// Module Name: M0_top
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
// 
//////////////////////////////////////////////////////////////////////////////////


module M0_top(
    );
    
    reg HCLK, HRESETn;
    
    wire        ahb_ready, ahb_error;
    wire [31:0] ahb_rdata;
    
    wire        ahb_read, ahb_write;
    wire [1:0]  ahb_size;
    wire [31:0] ahb_addr;
    wire [31:0] ahb_wdata;
    
    wire [31:0] cpu_addr;
    wire [31:0] cpu_wdata;
    wire        cpu_wr, cpu_rd;
    wire [31:0] nvic_rdata, scb_rdata, syst_rdata;
    
    wire ppb_sel      = (cpu_addr[31:12] == 20'hE000E);
    wire systick_sel  = ppb_sel && (cpu_addr[11:8] == 4'h0) && (cpu_addr[7:4] != 4'h0); // 0x010-0x0FF
    wire nvic_sel     = ppb_sel && (cpu_addr[11:8] >= 4'h1) && (cpu_addr[11:8] < 4'hD);
    wire scb_sel      = ppb_sel && (cpu_addr[11:8] == 4'hD);

    wire [31:0] ppb_rdata = nvic_sel     ? nvic_rdata :
                            scb_sel      ? scb_rdata  :
                            systick_sel  ? syst_rdata :
                                           32'b0;
                                       
    wire        nmi_pend, hardfault_pend;
    wire        svcall_pend, pendsv_pend, systick_pend;
    wire [1:0]  svcall_pri, pendsv_pri, systick_pri;
    wire        vectclractive;
    wire        isrpending;
    wire [8:0]  vectpending;
    
    wire        exc_taken,     exc_return;
    wire [5:0]  exc_taken_num, exc_return_num;
    wire        svcall_req;
    wire        fault_req;
    wire [5:0]  IPSR;
    wire        PRIMASK;
    wire        core_halted;
    wire        systick_fire;
    
    wire        int_pend;
    wire [5:0]  int_pend_num;
    
    wire nmi_i;
    wire [31:0] gpio_irq;
    wire SLEEPONEXIT, SLEEPDEEP, SEVONPEND, SYSRESETREQ;
    
    initial begin
        HCLK = 0;
        forever #5 HCLK = ~HCLK;
    end
    
    core core_dut(
                .HCLK(HCLK),
                .HRESETn(HRESETn),
                
                .rdata_i(ahb_rdata),
                .ready_i(ahb_ready),
                .error_i(ahb_error),
                
                .addr_o(ahb_addr),
                .wdata_o(ahb_wdata),
                .read_req_o(ahb_read),
                .write_req_o(ahb_write),
                .size_o(ahb_size),
                
                .ppb_addr_o     (cpu_addr),
                .ppb_wdata_o    (cpu_wdata),
                .ppb_wr_o       (cpu_wr),
                .ppb_rd_o       (cpu_rd),
                .ppb_rdata_i    (ppb_rdata),
                
                .exc_taken_o    (exc_taken),
                .exc_taken_num_o(exc_taken_num),
                .exc_return_o   (exc_return),
                .exc_return_num_o(exc_return_num),
                .svcall_req_o   (svcall_req),
                .fault_req_o    (fault_req),
                .IPSR_o         (IPSR),
                .PRIMASK_o      (PRIMASK),
                .core_halted_o  (core_halted),
                
                .int_pend_i     (int_pend),
                .int_pend_num_i (int_pend_num),
                
                .SLEEPONEXIT_i  (SLEEPONEXIT),
                .SLEEPDEEP_i    (SLEEPDEEP),
                .SEVONPEND_i    (SEVONPEND)
              );
    
    ahb_top ahb(
                .HCLK(HCLK),
                .HRESETn(HRESETn),
                
                .addr_i(ahb_addr),
                .wdata_i(ahb_wdata),
                .read_req_i(ahb_read),
                .write_req_i(ahb_write),
                .size_i(ahb_size),
                
                .rdata_o(ahb_rdata),
                .ready_o(ahb_ready),
                .error_o(ahb_error)
               );
               
    NVIC NVIC_Unit(
        .clk                (HCLK),
        .rst_n              (HRESETn),
        
        .reg_addr           (cpu_addr[11:0]),
        .reg_wdata          (cpu_wdata),
        .reg_wr             (cpu_wr & nvic_sel),
        .nvic_rdata         (nvic_rdata),
        
        .irq_i              (gpio_irq),
        
        .PRIMASK            (PRIMASK),
        .exc_taken          (exc_taken),
        .exc_taken_num      (exc_taken_num),
        .exc_return         (exc_return),
        .exc_return_num     (exc_return_num),
        
        .nmi_pend           (nmi_pend),
        .hardfault_pend     (hardfault_pend),
        .svcall_pend        (svcall_pend),
        .pendsv_pend        (pendsv_pend),
        .systick_pend       (systick_pend),
        .svcall_pri         (svcall_pri),
        .pendsv_pri         (pendsv_pri),
        .systick_pri        (systick_pri),
        .VECTCLRACTIVE      (vectclractive),
        
        .int_pend           (int_pend),
        .int_pend_num       (int_pend_num),
        
        .isrpending         (isrpending),
        .vectpending        (vectpending)
    );
    
    SysTick SysTick_Unit (
        .clk                (HCLK),
        .rst_n              (HRESETn),

        .reg_addr           (cpu_addr[11:0]),
        .reg_wdata          (cpu_wdata),
        .reg_wr             (cpu_wr & systick_sel),
        .reg_rd             (cpu_rd & systick_sel),
        .syst_rdata         (syst_rdata),

        .core_halted        (core_halted),

        .systick_fire       (systick_fire)
    );
    
    SCB SCB_Unit (
        .clk                (HCLK),
        .rst_n              (HRESETn),
        
        .reg_addr           (cpu_addr[11:0]),
        .reg_wdata          (cpu_wdata),
        .reg_wr             (cpu_wr & scb_sel),
        .scb_rdata          (scb_rdata),
        
        .nmi_i              (nmi_i),
        
        .IPSR               (IPSR),
        .exc_taken          (exc_taken),
        .exc_taken_num      (exc_taken_num),
        .svcall_req         (svcall_req),
        .fault_req          (fault_req),
        .systick_fire       (systick_fire),
        
        .isrpending         (isrpending),
        .vectpending        (vectpending),
        .nmi_pend           (nmi_pend),
        .hardfault_pend     (hardfault_pend),
        .svcall_pend        (svcall_pend),
        .pendsv_pend        (pendsv_pend),
        .systick_pend       (systick_pend),
        .svcall_pri         (svcall_pri),
        .pendsv_pri         (pendsv_pri),
        .systick_pri        (systick_pri),
        .VECTCLRACTIVE      (vectclractive),
        
        .SYSRESETREQ        (SYSRESETREQ),
        .SLEEPONEXIT        (SLEEPONEXIT),
        .SLEEPDEEP          (SLEEPDEEP),
        .SEVONPEND          (SEVONPEND)
    );
        
    initial begin
        HRESETn = 1'b0;
        #10
        HRESETn = 1'b1;
        #2000
        $finish;
    end
    
endmodule
