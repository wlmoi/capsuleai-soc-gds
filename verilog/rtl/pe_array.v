// -----------------------------------------------------------------------------
// pe_array.v  --  N x N output-stationary systolic array of pe_ps
//
// All N activation lanes and N weight lanes are presented in the same cycle
// (one reduction index k per cycle). Input skew buffers delay row i by i cycles
// and column j by j cycles, so PE(i,j) sees a[i][k] and w[k][j] in cycle
// k + i + j. After K valid cycles plus 2(N-1) drain cycles, every PE holds its
// output.
//
//   INT16 mode : tile = N x N outputs,   C[i][j]       = sum_k a[i][k] * w[k][j]
//   INT8 mode  : tile = 2N x 2N outputs, C[2i+u][2j+v] = sum_k a[i][k].u * w[k][j].v
// -----------------------------------------------------------------------------
`default_nettype none

module pe_array #(
    parameter N = 4
) (
    input  wire              clk,
    input  wire              rst_n,
    input  wire              mode,
    input  wire              clr,
    input  wire              in_valid,          // lanes carry reduction index k
    input  wire [N*16-1:0]   a_lanes,           // lane i -> row i
    input  wire [N*16-1:0]   w_lanes,           // lane j -> column j
    output wire [N*N*96-1:0] acc_flat           // PE(i,j) at [(i*N+j)*96 +: 96]
);

    // ---------------- input skew buffers ----------------
    wire [15:0] a_sk [0:N-1];
    wire        v_sk [0:N-1];
    wire [15:0] w_sk [0:N-1];

    genvar i, j;
    generate
        for (i = 0; i < N; i = i + 1) begin : g_skew
            if (i == 0) begin : g_nodelay
                assign a_sk[i] = a_lanes[i*16 +: 16];
                assign v_sk[i] = in_valid;
                assign w_sk[i] = w_lanes[i*16 +: 16];
            end else begin : g_delay
                reg [15:0] a_d [0:i-1];
                reg        v_d [0:i-1];
                reg [15:0] w_d [0:i-1];
                integer t;
                always @(posedge clk or negedge rst_n) begin
                    if (!rst_n) begin
                        for (t = 0; t < i; t = t + 1) begin
                            a_d[t] <= 16'd0; v_d[t] <= 1'b0; w_d[t] <= 16'd0;
                        end
                    end else begin
                        a_d[0] <= a_lanes[i*16 +: 16];
                        v_d[0] <= in_valid;
                        w_d[0] <= w_lanes[i*16 +: 16];
                        for (t = 1; t < i; t = t + 1) begin
                            a_d[t] <= a_d[t-1]; v_d[t] <= v_d[t-1]; w_d[t] <= w_d[t-1];
                        end
                    end
                end
                assign a_sk[i] = a_d[i-1];
                assign v_sk[i] = v_d[i-1];
                assign w_sk[i] = w_d[i-1];
            end
        end
    endgenerate

    // ---------------- PE mesh ----------------
    wire [15:0] a_h [0:N-1][0:N];   // horizontal a links
    wire        v_h [0:N-1][0:N];
    wire [15:0] w_v [0:N][0:N-1];   // vertical w links

    generate
        for (i = 0; i < N; i = i + 1) begin : g_row_in
            assign a_h[i][0] = a_sk[i];
            assign v_h[i][0] = v_sk[i];
            assign w_v[0][i] = w_sk[i];
        end
        for (i = 0; i < N; i = i + 1) begin : g_r
            for (j = 0; j < N; j = j + 1) begin : g_c
                pe_ps u_pe (
                    .clk    (clk),
                    .rst_n  (rst_n),
                    .mode   (mode),
                    .clr    (clr),
                    .a_in   (a_h[i][j]),
                    .v_in   (v_h[i][j]),
                    .w_in   (w_v[i][j]),
                    .a_out  (a_h[i][j+1]),
                    .v_out  (v_h[i][j+1]),
                    .w_out  (w_v[i+1][j]),
                    .acc_out(acc_flat[(i*N+j)*96 +: 96])
                );
            end
        end
    endgenerate

endmodule

`default_nettype wire
