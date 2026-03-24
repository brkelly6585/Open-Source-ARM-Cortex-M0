`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 03/02/2026 09:07:02 PM
// Design Name: 
// Module Name: tb_alu
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




module tb_alu;

    reg clk;
    reg [3:0] operation;
    reg [31:0] d0, d1;
    reg update_flags;

    wire [31:0] ALUResult;
    wire N, Z, C, V;
    wire [31:0] APSROut;

    // Instantiate DUT
    arthALU dut (
        .clk(clk),
        .operation(operation),
        .d0(d0),
        .d1(d1),
        .update_flags(update_flags),
        .ALUResult(ALUResult),
        .N(N), .Z(Z), .C(C), .V(V),
        .APSROut(APSROut)
    );
    parameter   AND = 4'h0,
                EOR = 4'h1,
                LSL = 4'h2,
                LSR = 4'h3,
                ASR = 4'h4,
                ADC = 4'h5,
                SBC = 4'h6,
                ROR = 4'h7,
                TST = 4'h8,
                RSBS = 4'h9,
                CMP = 4'hA, SUB = 4'hA,
                CMN = 4'hB, ADD = 4'hB,
                ORR = 4'hC,
                MUL = 4'hD,
                BIC = 4'hE,
                MVN = 4'hF;

    // Clock generation
    initial begin
        clk = 0;
        forever #5 clk = ~clk;   // 10ns period
    end

    // Task to apply an ALU operation
    task run_op(
        input [3:0] op,
        input [31:0] a,
        input [31:0] b,
        input flag_en
    );
    begin
        operation = op;
        d0 = a;
        d1 = b;
        update_flags = flag_en;

        @(posedge clk); #1;

        $display("OP=%h  A=%h  B=%h  |  Result=%h  N=%b Z=%b C=%b V=%b",
                 op, a, b, ALUResult, N, Z, C, V);
    end
    endtask

    // Test sequence
    initial begin
        $display("=== arthALU Testbench Start ===");

        // Default
        operation = 0;
        d0 = 0;
        d1 = 0;
        update_flags = 0;

        @(posedge clk);

        // ---------------------------------------------------------
        // ADD (example opcode 0)
        // ---------------------------------------------------------
        $display("\n-- Test ADD --");
        run_op(ADD, 32'h0000_0005, 32'h0000_0003, 1);

        // Overflow ADD
        run_op(ADD, 32'h7FFF_FFFF, 32'h0000_0001, 1);

        // ---------------------------------------------------------
        // SUB (example opcode 1)
        // ---------------------------------------------------------
        $display("\n-- Test SUB --");
        run_op(SUB, 32'h0000_0005, 32'h0000_0003, 1);

        // Negative result
        run_op(SUB, 32'h0000_0003, 32'h0000_0005, 1);

        // ---------------------------------------------------------
        // AND (example opcode 2)
        // ---------------------------------------------------------
        $display("\n-- Test AND --");
        run_op(AND, 32'hFFFF_0000, 32'h0F0F_F0F0, 0);

        // ---------------------------------------------------------
        // OR (example opcode 3)
        // ---------------------------------------------------------
        $display("\n-- Test OR --");
        run_op(EOR, 32'hAAAA_5555, 32'h0F0F_0F0F, 0);
        
        
        // ---------------------------------------------------------
        // Zero flag check
        // ---------------------------------------------------------
        $display("\n-- Test Zero Flag --");
        run_op(ADD, 32'h0000_0000, 32'h0000_0000, 1);

        // ---------------------------------------------------------
        // Randomized stress test
        // ---------------------------------------------------------
        $display("\n-- Random Stress Test --");
        repeat (10) begin
            run_op($random, $random, $random, 1);
        end

        $display("\n=== Testbench Complete ===");
        $finish;
    end

endmodule
