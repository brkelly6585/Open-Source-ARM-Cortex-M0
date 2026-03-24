`timescale 1ns/1ps

module tb_datamem;

    reg clk;
    reg rst_n;

    // Inputs to DUT
    reg [31:0] eff_addr_i;
    reg [31:0] store_data_i;
    reg [31:0] Rd_i;
    reg [1:0]  size_i;
    reg is_load_i;
    reg is_store_i;
    reg valid_i;

    // Outputs from DUT
    wire [31:0] addr_o;
    wire [31:0] wdata_o;
    wire read_req_o;
    wire write_req_o;
    wire [1:0] size_o;

    reg  [31:0] rdata_i;
    reg  ready_i;

    wire [31:0] load_data_o;
    wire [31:0] Rd_o;
    wire wb_valid_o;
    wire stall_o;
    
    integer error = 0;

    // Instantiate DUT
    Data_Memory dut (
        .clk(clk),
        .rst_n(rst_n),
        .eff_addr_i(eff_addr_i),
        .store_data_i(store_data_i),
        .Rd_i(Rd_i),
        .size_i(size_i),
        .is_load_i(is_load_i),
        .is_store_i(is_store_i),
        .valid_i(valid_i),
        .addr_o(addr_o),
        .wdata_o(wdata_o),
        .read_req_o(read_req_o),
        .write_req_o(write_req_o),
        .size_o(size_o),
        .rdata_i(rdata_i),
        .ready_i(ready_i),
        .load_data_o(load_data_o),
        .Rd_o(Rd_o),
        .wb_valid_o(wb_valid_o),
        .stall_o(stall_o)
    );

    // Clock
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    // Reset
    initial begin
        rst_n = 0;
        ready_i = 0;
        rdata_i = 32'hABCD_1234; // arbitrary load return value

        eff_addr_i = 0;
        store_data_i = 0;
        Rd_i = 0;
        size_i = 0;
        is_load_i = 0;
        is_store_i = 0;
        valid_i = 0;

        #20 rst_n = 1;
    end

    // Task: issue a load request
    task issue_load(input [31:0] addr, input [31:0] rd);
    begin
        eff_addr_i = addr;
        Rd_i = rd;
        size_i = 2; // word
        is_load_i = 1;
        valid_i = 1;

        @(posedge clk);
        is_load_i = 0;
        valid_i = 0;
    end
    endtask

    // Task: issue a store request
    task issue_store(input [31:0] addr, input [31:0] data);
    begin
        eff_addr_i = addr;
        store_data_i = data;
        size_i = 2;
        is_store_i = 1;
        valid_i = 1;

        @(posedge clk);
        #1
        is_store_i = 0;
        valid_i = 0;
    end
    endtask

    // Test sequence
    initial begin
        @(posedge rst_n);
        $display("=== Data Memory Control Test Start ===");

        // ---------------------------------------------------------
        // Test 1: Store request should NOT stall
        // ---------------------------------------------------------
        $display("\n-- Test 1: Store request --");
        issue_store(32'h1000_0000, 32'hDEAD_BEEF);

        @(posedge clk);
        if (!write_req_o) begin error = 1;
            $display("ERROR: write_req_o not asserted!");
        end

        if (addr_o != 32'h1000_0000) begin error = 1;
            $display("ERROR: addr_o inncorrect");
        end
        
        // Simulate ready
        ready_i = 1;
        @(posedge clk);
        ready_i = 0;
        
        if(error ==0)
            $display("PASS");

        // ---------------------------------------------------------
        // Test 2: Load request SHOULD stall until ready
        // ---------------------------------------------------------
        $display("\n-- Test 2: Load request stall behavior --");
        issue_load(32'h2000_0000, 5);

        @(posedge clk);
        if (!read_req_o) begin error = 1;
            $display("ERROR: read_req_o not asserted!");
        end
        
        if (!stall_o) begin error = 1;
            $display("ERROR: load should assert stall!");
        end
        
        // Hold stall for 3 cycles
        repeat (3) @(posedge clk);

        // Now release ready
        ready_i = 1;
        @(posedge clk);
        ready_i = 0;

        // After ready, stall must drop and wb_valid must assert
        @(posedge clk);
        if (stall_o) begin error = 1;
            $display("ERROR: stall_o did not clear after ready!");
        end

        if (!wb_valid_o) begin error = 1;
            $display("ERROR: wb_valid_o not asserted after load completion!");
        end
        
        if (Rd_o !== 5) begin error = 1;
            $display("ERROR: Rd_o mismatch!");
        end
            
        if(error ==0)
            $display("PASS");

        $display("\n=== Test Complete ===");
        $finish;
    end

endmodule