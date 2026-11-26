// -----------------------------------------------------------------------------
// pe_ps.v  --  Precision-scalable processing element (INT8 x4 / INT16 x1)
//
// One 16-bit activation lane (a) and one 16-bit weight lane (w) enter the PE.
//   mode = 0 (INT8) : each lane carries two signed bytes  {x1, x0}
//                     four independent MACs  acc[2u+v] += a_u * w_v  (u,v in {0,1})
//                     acc0:(a0,w0) acc1:(a0,w1) acc2:(a1,w0) acc3:(a1,w1)
//   mode = 1 (INT16): each lane carries one signed 16-bit word
//                     x*w = xH*wH*2^16 + (xH*wL + xL*wH)*2^8 + xL*wL
//                     acc1:acc0 form one 48-bit accumulator (carry-chained)
//
// Four 9x9 signed multipliers are shared by both modes. The high bytes are
// always sign-extended; the low bytes are zero-extended in INT16 mode and
// sign-extended in INT8 mode.
//
// Output-stationary systolic PE: a is forwarded to the right, w downwards,
// together with the valid bit that travels with a.
// -----------------------------------------------------------------------------
`default_nettype none

module pe_ps (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        mode,      // 0: INT8x4, 1: INT16x1
    input  wire        clr,       // synchronous clear of all accumulators
    input  wire [15:0] a_in,
    input  wire        v_in,      // a_in/w_in valid at this PE
    input  wire [15:0] w_in,
    output reg  [15:0] a_out,
    output reg         v_out,
    output reg  [15:0] w_out,
    output wire [95:0] acc_out    // {acc3, acc2, acc1, acc0}, 24 b each
);

    // ---------------- operand extension (9-bit signed) ----------------
    wire signed [8:0] aH = {a_in[15], a_in[15:8]};
    wire signed [8:0] wH = {w_in[15], w_in[15:8]};
    wire signed [8:0] aL = {mode ? 1'b0 : a_in[7], a_in[7:0]};
    wire signed [8:0] wL = {mode ? 1'b0 : w_in[7], w_in[7:0]};

    // ---------------- four 9x9 signed multipliers ----------------
    wire signed [17:0] pHH = aH * wH;   // INT8: a1*w1
    wire signed [17:0] pHL = aH * wL;   // INT8: a1*w0
    wire signed [17:0] pLH = aL * wH;   // INT8: a0*w1
    wire signed [17:0] pLL = aL * wL;   // INT8: a0*w0

    // ---------------- INT16 combiner (shift-add) ----------------
    wire signed [47:0] p16 = ({{30{pHH[17]}}, pHH} <<< 16)
                           + ({{30{pHL[17]}}, pHL} <<< 8)
                           + ({{30{pLH[17]}}, pLH} <<< 8)
                           +  {{30{pLL[17]}}, pLL};

    // ---------------- accumulators ----------------
    reg [23:0] acc0, acc1, acc2, acc3;

    // adder 0: low half of the 48-bit sum (INT16) or acc0 += a0*w0 (INT8)
    wire [23:0] op0  = mode ? p16[23:0]  : {{6{pLL[17]}}, pLL};
    wire [24:0] sum0 = {1'b0, acc0} + {1'b0, op0};
    wire        cy0  = mode & sum0[24];
    // adder 1: high half with carry (INT16) or acc1 += a0*w1 (INT8)
    wire [23:0] op1  = mode ? p16[47:24] : {{6{pLH[17]}}, pLH};
    wire [23:0] sum1 = acc1 + op1 + {23'd0, cy0};

    wire [23:0] sum2 = acc2 + {{6{pHL[17]}}, pHL};
    wire [23:0] sum3 = acc3 + {{6{pHH[17]}}, pHH};

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            acc0 <= 24'd0; acc1 <= 24'd0; acc2 <= 24'd0; acc3 <= 24'd0;
        end else if (clr) begin
            acc0 <= 24'd0; acc1 <= 24'd0; acc2 <= 24'd0; acc3 <= 24'd0;
        end else if (v_in) begin
            acc0 <= sum0[23:0];
            acc1 <= sum1;
            if (!mode) begin              // acc2/acc3 idle (clock-gateable) in INT16
                acc2 <= sum2;
                acc3 <= sum3;
            end
        end
    end

    // ---------------- systolic forwarding ----------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            a_out <= 16'd0; w_out <= 16'd0; v_out <= 1'b0;
        end else begin
            a_out <= a_in;
            w_out <= w_in;
            v_out <= v_in;
        end
    end

    assign acc_out = {acc3, acc2, acc1, acc0};

endmodule

`default_nettype wire
