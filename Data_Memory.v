module Data_Memory (
    input clk,
    input rst_n,

    input [31:0] eff_addr_i,
    input [31:0] store_data_i,
    input [3:0] Rd_i,
    input [1:0] size_i,        // 0=byte,1=half,2=word
    input load_i,
    input store_i,
    input valid_i, // Arb control

    input [1:0] type_i,        // 00=single, 01=LDM/STM, 10=PUSH/POP
    input [8:0] reg_list_i,

    input  [31:0]  rdata_i,
    input  ready_i,
    output reg [31:0] addr_o,
    output reg [31:0]  wdata_o,
    output reg read_req_o,
    output reg write_req_o,
    output reg [1:0] size_o,

    output reg [31:0] load_data_o,
    output reg [3:0] Rd_o, curr_reg,
    output reg wb_valid_o,
    output reg stall_o
);
    
    parameter IDLE = 3'd0, SINGLE = 3'd1,
    MULTI_START = 3'd2, MULTI_ISSUE = 3'd3, MULTI_WAIT = 3'd4, MULTI_WB = 3'd5, MULTI_NEXT = 3'd6;

    reg [2:0]  curr_state, next_state;
    
    reg multi;
    reg [8:0] reg_mask;       // stored reg list
    reg [31:0] base_addr;      // running address
    reg multi_load;  // 1 = load (LDM/POP), 0 = store (STM/PUSH)
    reg stack;     // 0 = LDM/STM, 1 = PUSH/POP
    reg dec;       // PUSH (pre-decrement)
    reg inc;       // LDM/STM/POP

    wire regs_done = (reg_mask == 9'b0);

    always @(posedge clk) begin
        if(!rst_n) curr_state <= IDLE;
        else curr_state <= next_state;
    end

    always @(*) begin
        next_state = curr_state;

        case (curr_state)
            IDLE: begin
                if (valid_i && (load_i || store_i)) begin
                    if (type_i == 2'b00)
                        // single
                        next_state = SINGLE;
                    else
                        // multi-register (PUSH/POP/LDM/STM)
                        next_state = MULTI_START;
                end
            end

            SINGLE: begin
                // wait for ready_i
                if (ready_i)
                    next_state = IDLE;
                else
                    next_state = SINGLE;
            end
            

            MULTI_START: 
                next_state = MULTI_ISSUE;

            MULTI_ISSUE: 
                next_state = MULTI_WAIT;

            MULTI_WAIT: begin
                //wait for ready
                if (ready_i) begin
                    if (multi_load)
                        next_state = MULTI_WB;
                    else
                        next_state = MULTI_NEXT;
                end
            end

            MULTI_WB: begin
                next_state = MULTI_NEXT;
            end

            MULTI_NEXT: begin
                if (regs_done)
                    next_state = IDLE;
                else
                    next_state = MULTI_ISSUE;
            end

            default: next_state = IDLE;
        endcase
    end

    integer i;

    always @(*) begin
        if (!rst_n) begin
            multi  <= 1'b0;
            reg_mask <= 9'b0;
            curr_reg <= 4'd0;
            base_addr <= 32'b0;
            multi_load <= 1'b0;
            stack <= 1'b0;
            dec <= 1'b0;
            inc <= 1'b0;

            addr_o <= 32'b0;
            wdata_o <= 32'b0;
            read_req_o  <= 1'b0;
            write_req_o <= 1'b0;
            size_o  <= 2'd2;

            load_data_o <= 32'b0;
            Rd_o  <= 4'd0;
            wb_valid_o  <= 1'b0;
            stall_o <= 1'b0;
        end else begin

            // defaults each cycle
            read_req_o <= 1'b0;
            write_req_o <= 1'b0;
            wb_valid_o <= 1'b0;
            stall_o <= 1'b0;
            size_o  <= 2'd2;

            case (curr_state)
                IDLE: begin
                    multi <= 1'b0;

                    if (valid_i) begin
                        if (type_i == 2'b00) begin
                            // single LDR/STR setup
                            addr_o <= eff_addr_i;
                            wdata_o <= store_data_i;
                            size_o <= size_i;

                            if (load_i) begin
                                read_req_o <= 1'b1;
                                stall_o    <= 1'b1; // stall until ready_i
                            end else if (store_i) begin
                                write_req_o <= 1'b1;
                                stall_o     <= 1'b1;
                            end
                        end else begin
                            // multi-register setup
                            multi  <= 1'b1;
                            reg_mask      <= reg_list_i;
                            base_addr     <= eff_addr_i;

                            stack    <= (type_i == 2'b10);
                            multi_load <= load_i;   // LDM/POP
                            dec      <= (type_i == 2'b10) && store_i; // PUSH
                            inc      <= (type_i == 2'b01) || ((type_i == 2'b10) && load_i); // LDM/STM/POP

                            // Find the current working reg
                            curr_reg <= 4'd0;
                            for (i = 8; i >= 0; i = i - 1) begin
                                if (reg_list_i[i]) begin
                                    curr_reg <= i[3:0];
                                end
                            end

                            stall_o <= 1'b1;
                        end
                    end
                end
                

                SINGLE: begin
                    stall_o <= load_i | store_i; //keep stalled until ready
                    
                    if (ready_i) begin
                        if (load_i) begin
                            load_data_o <= rdata_i;
                            Rd_o <= Rd_i;
                            wb_valid_o  <= 1'b1;
                        end
                        stall_o <= 1'b0;
                    end
                end

                MULTI_START: begin
                    stall_o <= 1'b1;
                    // Push needs to pre-dec
                    if (stack && dec) begin
                        base_addr <= eff_addr_i - 4;
                    end
                end

                MULTI_ISSUE: begin
                    stall_o <= 1'b1;

                    // Address for this transfer
                    addr_o <= base_addr;

                    if (multi_load) begin
                        read_req_o <= 1'b1;
                    end else begin
                        wdata_o <= store_data_i;
                        write_req_o<= 1'b1;
                    end
                end

                MULTI_WAIT: begin
                    stall_o <= 1'b1;

                    if (ready_i) begin
                        if (multi_load) begin
                            load_data_o <= rdata_i;
                        end

                        // inc all non push
                        if (inc)
                            base_addr <= base_addr + 4;
                        else if (dec)
                            base_addr <= base_addr - 4;
                    end
                end

                MULTI_WB: begin
                    stall_o <= 1'b1;
                    wb_valid_o <= 1'b1;
                    Rd_o  <= curr_reg;
                end

                MULTI_NEXT: begin
                    stall_o <= 1'b1;

                    // clear current bit
                    reg_mask[curr_reg] <= 1'b0;

                    if (!regs_done) begin
                        // find next set bit
                        for (i = 8; i >= 0; i = i - 1) begin
                            if (reg_mask[i]) begin
                                curr_reg <= i[3:0];
                            end
                        end
                    end else begin
                        multi <= 1'b0;
                    end
                end

                default: ;
            endcase
        end
    end

endmodule