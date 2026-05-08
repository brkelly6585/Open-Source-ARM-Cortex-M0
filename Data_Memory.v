`timescale 1ns / 1ps

module Data_Memory (
    input clk,
    input rst_n,

    input [31:0] base_addr_i,
    input [31:0] store_data_i,
    input [3:0] Rd_i,
    input [1:0] size_i,
    input sign_i,
    input load_i,
    input store_i,
    input valid_i,

    input [1:0] type_i,
    input [8:0] reg_list_i,

    input [31:0] rdata_i,
    input ready_i,

    output reg [31:0] addr_o, wdata_o,
    output reg read_req_o,
    output reg write_req_o,
    output reg [1:0] size_o,

    output reg [31:0] load_data_o,
    output reg [3:0]  Rd_o, curr_reg,
    output reg wb_valid_o,
    output reg stall_o,
    output reg exc_o
);

    parameter IDLE        = 3'd0,
          SINGLE      = 3'd1,
          SINGLE_DONE = 3'd2,
          MULTI_START = 3'd3,
          MULTI_WAIT  = 3'd4,
          MULTI_NEXT  = 3'd5;



    reg [2:0]  curr_state, next_state;

    reg [8:0]  reg_mask_r;
    reg [31:0] base_addr_r;
    reg        multi_load_r;
    reg        stack_r;
    reg        dec_r;
    reg        inc_r;
    reg [3:0]  curr_reg_r;

    // Capture inputs for use in SINGLE (held across cycles)
    reg        load_r, sign_r;
    reg [1:0] size_r;
    reg [3:0]  Rd_r;
	reg [31:0] load_data_r;
	
	wire [8:0] mask_cleared = reg_mask_r & ~(9'b1 << curr_reg_r);
    

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            curr_state <= IDLE;
        else
            curr_state <= next_state;
    end


    always @(*) begin
        next_state = curr_state;
        case (curr_state)
            IDLE: begin
                if (valid_i && (load_i || store_i))
                    next_state = (type_i == 2'b00) ? SINGLE : MULTI_START;
            end
            SINGLE: begin
                if (ready_i)
                    if(load_i || store_i) next_state = SINGLE;
                    else next_state = IDLE;  // don't go straight to IDLE
                else
                    next_state = SINGLE;
            end

            SINGLE_DONE: begin
                if(load_i || store_i) next_state = SINGLE;
                else    next_state = IDLE;   // one hold cycle, then release
                
            end
            MULTI_START: next_state = MULTI_WAIT;
            MULTI_WAIT: begin
                if (ready_i)
                    next_state = MULTI_NEXT;
            end
            MULTI_NEXT: next_state = (mask_cleared == 0) ? IDLE : MULTI_WAIT;
            default:    next_state = IDLE;
        endcase
    end


    integer i;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            reg_mask_r   <= 9'b0;
            base_addr_r  <= 32'b0;
            multi_load_r <= 1'b0;
            stack_r      <= 1'b0;
            dec_r        <= 1'b0;
            inc_r        <= 1'b0;
            curr_reg_r   <= 4'd0;
            load_r       <= 1'b0;
            Rd_r         <= 4'd0;
        end else begin
            case (curr_state)
                // ---- Latch everything needed for the upcoming operation ----
                IDLE: begin
                    if (valid_i && (load_i || store_i)) begin
                        load_r <= load_i;
                        Rd_r <= Rd_i;
                        size_r <= size_i;
                        sign_r <= sign_i;
                        if (type_i != 2'b00) begin
                            reg_mask_r   <= reg_list_i;
                            base_addr_r  <= base_addr_i;
                            multi_load_r <= load_i;
                            stack_r      <= (type_i == 2'b10);
                            dec_r        <= (type_i == 2'b10) &&  store_i;
                            inc_r        <= (type_i == 2'b01) || ((type_i == 2'b10) && load_i);

                            // Find set bit (lowest for POP, highest for PUSH)
                            curr_reg_r <= 4'd0;
							if((type_i == 2'b10) &&  store_i)begin
								for (i = 0; i <= 8; i = i + 1)
									if(reg_list_i[i]) curr_reg_r <= i[3:0];
							end else begin
								for (i = 8; i>=0; i = i - 1) 
									if (reg_list_i[i]) curr_reg_r <= i[3:0];
							end
                        end
                    end
                end
                
                SINGLE: begin
                    load_r <= load_i;
                    Rd_r <= Rd_i;
                    size_r <= size_i;
                    sign_r <= sign_i;
                end

                MULTI_START: begin
                    if (stack_r && dec_r)
                        base_addr_r <= base_addr_r - 4;
                end


                MULTI_WAIT: begin
                    if (ready_i) begin
                        if (inc_r)       base_addr_r <= base_addr_r + 4;
						if (multi_load_r) begin
							load_data_r <= rdata_i;
							Rd_r    <= curr_reg_r;
						end
                    end
                end

                MULTI_NEXT: begin
                    reg_mask_r[curr_reg_r] <= 1'b0;

                    if (dec_r) base_addr_r <= ((mask_cleared) != 0) ? base_addr_r - 4 : base_addr_r;
                    if (mask_cleared != 9'b0 && dec_r != 1) begin
                        curr_reg_r <= 4'd0;
                        for (i = 8; i >= 0; i = i - 1)
                            if (mask_cleared[i]) curr_reg_r <= i[3:0];
                    end
                    else if (mask_cleared != 9'b0) begin
                        curr_reg_r <= 4'd0;
                        for (i = 0; i <= 8; i = i + 1)
                            if(mask_cleared[i]) curr_reg_r <= i[3:0];
                    end
                end

                default: ;
            endcase
        end
    end


    always @(*) begin
        // Safe defaults
        addr_o      = 32'b0;
        wdata_o     = 32'b0;
        read_req_o  = 1'b0;
        write_req_o = 1'b0;
        size_o      = 2'd2;
        load_data_o = 32'b0;
        Rd_o        = 4'd0;
        curr_reg    = curr_reg_r;
        wb_valid_o  = 1'b0;
        exc_o = 1'b0;

        stall_o = (curr_state != IDLE);

        case (curr_state)
            IDLE: begin
                if (valid_i && (load_i || store_i) && (type_i == 2'b00)) begin
                    addr_o  = base_addr_i;
                    wdata_o = store_data_i;
                    size_o  = size_i;
                    read_req_o  = load_i;
                    write_req_o = store_i;
                end
            end

            SINGLE: begin
                  
                addr_o      = base_addr_i;       // hold address stable
                wdata_o = store_data_i;
                size_o      = size_i;
                read_req_o  = load_r  && !ready_i;
                write_req_o = !load_r && !ready_i;
                
            
                // Latch result when ready arrives, present it this cycle
                if (ready_i && load_r) begin
                    load_data_o = sign_r ? 
                    (size_r[0] ? {{16{rdata_i[15]}},rdata_i[15:0]} : {{24{rdata_i[7]}},rdata_i[7:0]})
                     :  rdata_i;
                    Rd_o        = Rd_r;
                    wb_valid_o  = 1'b1;
                end
                if(ready_i) stall_o = 1'b0;
            end
            
            SINGLE_DONE: begin
                load_data_o = sign_r ? 
                (size_r[0] ? {{16{rdata_i[15]}},rdata_i[15:0]} : {{24{rdata_i[7]}},rdata_i[7:0]})
                 :  rdata_i;   // rdata_i still valid from memory
                Rd_o        = Rd_r;
                wb_valid_o  = load_r;
            end 

            MULTI_WAIT: begin
                addr_o = base_addr_r;
                if (multi_load_r) begin
                    read_req_o = 1'b1;
                end else begin
                    wdata_o     = store_data_i;
                    write_req_o = 1'b1;
                end
                
                if (ready_i && multi_load_r) begin
                    load_data_o = rdata_i;
                    Rd_o       = curr_reg_r;
                    if(curr_reg_r == 4'hF) exc_o = load_data_o[31:4] == 28'hFFFFFF;
                    wb_valid_o = ~exc_o && ready_i;
                end
            end
            MULTI_NEXT: begin
                addr_o = base_addr_r;
                if (multi_load_r && (mask_cleared != 9'b0)) begin
                    read_req_o = 1'b1;
                end else if (mask_cleared == 9'b0) begin
                    wdata_o     = store_data_i;
                    write_req_o = 1'b1;
                end
                
				if (multi_load_r) begin
					Rd_o        = Rd_r;
					load_data_o = load_data_r;
					wb_valid_o  = 1'b1;
				end
                if(stack_r && (mask_cleared == 9'b0)) begin
                    Rd_o = 4'hD;
                    load_data_o = base_addr_r;
                    wb_valid_o = 1'b1;
                end
            end
            default: ;
        endcase
    end

endmodule