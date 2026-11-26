// -----------------------------------------------------------------------------
// requant.v  --  Fixed-point requantization, ReLU and saturation
//
//   y = clamp( round( (acc + bias) * M0 * 2^-(16+sh) ) )
//   M0  : unsigned Q0.16 multiplier, M0/2^16 in [0.5, 1)
//   sh  : extra right shift (0..31)
//   out16 = 1 -> clamp to [-32768, 32767] (next layer INT16)
//   out16 = 0 -> clamp to [-128, 127]     (next layer INT8), sign-extended
//   relu  = 1 -> negative results forced to zero
// Rounding is round-half-up (add 2^(s-1), arithmetic shift right).
// One register stage at the output.
// -----------------------------------------------------------------------------
`default_nettype none

module requant (
    input  wire               clk,
    input  wire               rst_n,
    input  wire               in_valid,
    input  wire signed [47:0] acc,
    input  wire signed [47:0] bias,
    input  wire        [15:0] m0,
    input  wire        [4:0]  sh,
    input  wire               out16,
    input  wire               relu,
    output reg                out_valid,
    output reg  signed [15:0] y
);
    wire signed [48:0] s      = acc + bias;                       // 49 b
    wire signed [65:0] prod   = s * $signed({1'b0, m0});          // 49 x 17
    wire        [5:0]  shamt  = 6'd16 + {1'b0, sh};
    wire signed [65:0] rnd    = 66'sd1 <<< (shamt - 6'd1);
    wire signed [65:0] shf    = (prod + rnd) >>> shamt;

    wire signed [65:0] hi     = out16 ? 66'sd32767  : 66'sd127;
    wire signed [65:0] lo     = relu  ? 66'sd0 : (out16 ? -66'sd32768 : -66'sd128);
    wire signed [65:0] clamped = (shf > hi) ? hi : ((shf < lo) ? lo : shf);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            out_valid <= 1'b0;
            y         <= 16'sd0;
        end else begin
            out_valid <= in_valid;
            y         <= clamped[15:0];
        end
    end
endmodule

`default_nettype wire
