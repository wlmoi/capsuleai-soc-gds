// -----------------------------------------------------------------------------
// dla_tile.v  --  Tile engine: controller FSM + operand fetch + pe_array
//
// Computes one output tile over a reduction length K. Operands are read from
// SRAM-style ports with one cycle of read latency (as in the baseline DLA):
// k_addr is issued in cycle t, a_lanes/w_lanes are valid in cycle t+1.
//   FSM: IDLE -> CLEAR -> COMPUTE (K reads) -> DRAIN (1 + 2(N-1) cycles) -> DONE
// -----------------------------------------------------------------------------
`default_nettype none
module dla_tile #(
    parameter N  = 4,
    parameter KW = 10                // reduction index width (K <= 1023)
) (
    input  wire              clk,
    input  wire              rst_n,
    input  wire              start,
    input  wire              mode,     // latched at start
    input  wire [KW-1:0]     k_len,    // K >= 1
    output reg  [KW-1:0]     k_addr,
    output reg               rd_en,
    input  wire [N*16-1:0]   a_lanes,  // SRAM read data (1-cycle latency)
    input  wire [N*16-1:0]   w_lanes,
    output reg               busy,
    output reg               done,
    output wire [N*N*96-1:0] acc_flat
);
    localparam S_IDLE = 3'd0, S_CLEAR = 3'd1, S_COMP = 3'd2, S_DRAIN = 3'd3, S_DONE = 3'd4;
    localparam DRAIN_CYC = 2*(N-1) + 1;

    reg [2:0]    st;
    reg          mode_q;
    reg [KW-1:0] k_q;
    reg [4:0]    dcnt;
    reg          clr;
    reg          vld_d;   // rd_en delayed by the SRAM latency

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            st <= S_IDLE; mode_q <= 1'b0; k_q <= {KW{1'b0}}; k_addr <= {KW{1'b0}};
            rd_en <= 1'b0; dcnt <= 5'd0; clr <= 1'b0; busy <= 1'b0; done <= 1'b0; vld_d <= 1'b0;
        end else begin
            vld_d <= rd_en;
            clr   <= 1'b0;
            case (st)
                S_IDLE: begin
                    done <= 1'b0;
                    if (start) begin
                        mode_q <= mode; k_q <= k_len; busy <= 1'b1; clr <= 1'b1; st <= S_CLEAR;
                    end
                end
                S_CLEAR: begin
                    k_addr <= {KW{1'b0}}; rd_en <= 1'b1; st <= S_COMP;
                end
                S_COMP: begin
                    if (k_addr == k_q - 1'b1) begin
                        rd_en <= 1'b0; dcnt <= 5'd0; st <= S_DRAIN;
                    end else begin
                        k_addr <= k_addr + 1'b1;
                    end
                end
                S_DRAIN: begin
                    if (dcnt == DRAIN_CYC[4:0]) begin
                        busy <= 1'b0; done <= 1'b1; st <= S_DONE;
                    end else dcnt <= dcnt + 1'b1;
                end
                S_DONE: begin
                    if (!start) begin done <= 1'b0; st <= S_IDLE; end
                end
                default: st <= S_IDLE;
            endcase
        end
    end

    pe_array #(.N(N)) u_array (
        .clk(clk), .rst_n(rst_n), .mode(mode_q), .clr(clr),
        .in_valid(vld_d), .a_lanes(a_lanes), .w_lanes(w_lanes), .acc_flat(acc_flat)
    );
endmodule
`default_nettype wire
