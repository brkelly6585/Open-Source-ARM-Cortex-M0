module arthALU (
    input  wire clk,
    input  wire [3:0] operation,// 0..F per decoder
    input  wire [31:0] d0, //data from rdn 
    input  wire [31:0] d1, //data from rm
    input  wire [4:0] shamt, // shamt for shift functions
    input  wire update_flags, // for adds and subs type ops
    output reg [31:0] ALUResult,
    output reg N,
    output reg Z,
    output reg C,
    output reg V,
    output wire [31:0] APSROut
);

    
    
    reg N_next, Z_next, C_next, V_next;
    
    always @(*) begin
        ALUResult = 32'h0000; 
        N_next = 0;
        Z_next = 0;
        C_next = 0;
        V_next = 0;
        case (operation)
          
            4'h0: begin // AND 
                ALUResult = d0 & d1;
                N_next = ALUResult[31]; 
                Z_next = (ALUResult==32'b0);
            end
              
            4'h1: begin // EOR
                ALUResult = d0 ^ d1;
                N_next = ALUResult[31]; 
                Z_next = (ALUResult==32'b0);
            end
            
            /* for all shifts, implement some change that allows for shifting without constant later IE LSL r4, r3 (r4 = r4 << r3) */
            4'h2: begin // LSL
                if (shamt == 0) ALUResult = d1; 
                else begin 
                    ALUResult = d1 << shamt; 
                    C_next = d1[32 - shamt];
                end
                N_next = ALUResult[31]; 
                Z_next = (ALUResult==32'b0);
            end
            
            
            4'h3: begin // LSR
                if (shamt == 0) ALUResult = d1; 
                else begin 
                    ALUResult = d1 >> shamt; 
                    C_next = d1[shamt - 1];
                end
                N_next = ALUResult[31]; 
                Z_next = (ALUResult==32'b0);
            end
            
            4'h4: begin // ASR
                if (shamt == 0) ALUResult = d1; 
                else begin
                    ALUResult = $signed(d1) >>> shamt; 
                    C_next = d1[shamt - 1];
                end
                N_next = ALUResult[31]; 
                Z_next = (ALUResult==32'b0);
            end
            
            //start here tomorrow
            4'h5: begin // ADC
                {C_next, ALUResult} = {1'b0,d0} + {1'b0,d1} + {32'b0,C};
                N_next = ALUResult[31]; 
                Z_next = (ALUResult==32'b0);
                V_next = ~(d0[31]^d1[31]) & (ALUResult[31]^d0[31]);
            end
              
            4'h6: begin // SBC  (d0 - d1 - ~C)
                {C_next, ALUResult} = {1'b0,d0} - {1'b0,d1} - {32'b0,~C};
                N_next = ALUResult[31]; 
                Z_next = (ALUResult == 32'b0);
                V_next = (d0[31]^d1[31]) & (ALUResult[31]^d0[31]);
            end
            
            4'h7: begin // ROR
                if (shamt==0) ALUResult = d1; 
                else begin
                  ALUResult = (d1 >> shamt) | (d1 << (32-shamt));
                  C_next = d1[shamt-1];
                end
                N_next = ALUResult[31]; 
                Z_next = (ALUResult==32'b0);
            end
            
            4'h8: begin // TST output not saved. dont wb
                ALUResult = d0 & d1;
                N_next = ALUResult[31]; 
                Z_next = (ALUResult==32'b0);
            end
              
            4'h9: begin // RSBS  normally rd = d1-d0 but thumb only negates d0 I guess
                {C_next, ALUResult} = 33'b0 - {1'b0, d0}; //1 no borrow, 0 borrow
                N_next = ALUResult[31];
                Z_next = (ALUResult==32'b0);
                V_next = d0[31] & ALUResult[31];
            end
              
            4'hA: begin // CMP  (d0 - d1)
                {C_next, ALUResult} = {1'b0,d0} - {1'b0,d1};
                N_next = ALUResult[31]; 
                Z_next = (ALUResult == 32'b0);
                V_next = (d0[31]^d1[31]) & (ALUResult[31]^d0[31]);
            end
              
            4'hB: begin // CMN  (d0 + d1)
                {C_next, ALUResult} = {1'b0,d0} + {1'b0,d1};
                N_next = ALUResult[31]; 
                Z_next = (ALUResult==32'b0);
                V_next = ~(d0[31]^d1[31]) & (ALUResult[31]^d0[31]);
            end
            
            4'hC: begin // ORR
                ALUResult = d0 | d1;
                N_next = ALUResult[31]; 
                Z_next = (ALUResult==32'b0);
            end
              
            4'hD: begin // MUL
                ALUResult = d0 * d1;
                N_next = ALUResult[31]; 
                Z_next = (ALUResult==32'b0);
            end
              
            4'hE: begin // BIC
                ALUResult = d0 & ~d1;
                N_next = ALUResult[31]; 
                Z_next = (ALUResult==32'b0);
            end
              
            4'hF: begin // MVN
                ALUResult = ~d1;
                N_next = ALUResult[31]; 
                Z_next = (ALUResult==32'b0);
            end
            
            default: begin 
                N_next = N; 
                Z_next = Z; 
                C_next = C; 
                V_next = V;
            end
        endcase
    end
    
    always @(posedge clk) begin
        if (update_flags) begin
            N <= N_next; 
            Z <= Z_next; 
            C <= C_next; 
            V <= V_next;
        end
    end
    
    assign APSROut = {N, Z, C, V, 28'b0};
    
endmodule
