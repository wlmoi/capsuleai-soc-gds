// -----------------------------------------------------------------------------
// cnn_engine.v  --  Layer sequencer for the lesion-triage CNN (Table I)
//
// Runs the whole network on the verified datapath blocks:
//   dla_tile  (4x4 precision-scalable PE array, K+9 cycles per tile)
//   requant   (y = clamp(round((acc+b)*M0*2^-(16+sh))), ReLU, 8/16-bit out)
// Per conv layer:  for each output-channel group (8 in INT8, 4 in INT16)
//                    for each pixel tile (8 in INT8, 4 in INT16)
//                      stream K im2col operands -> dla_tile -> requant -> activation RAM
//                  then 2x2 max-pool when the layer has one.
// After C4: GAP + Exit-1 FC; after C6: GAP + head FC (both on the PE array in INT16).
//
// Memories live in mem_models.v (act_mem, wrom_m, qrom_m): behavioural for
// simulation, black boxes for logic synthesis. Weights and requant constants are
// the .mem images written by make_mem.py from the trained network.
// Register map (byte offsets):
//   0x00 CTRL   [w] bit0 = start          0x04 STATUS [r] {done, busy}
//   0x08 CYCLES [r] cycles of the last run
//   0x40 + 8j   head logit j  [31:0]     0x44 + 8j  head logit j [47:32] sign-extended
//   0x80 + 8j   exit logit j  [31:0]     0x84 + 8j  exit logit j [47:32] sign-extended
// -----------------------------------------------------------------------------
`default_nettype none
module cnn_engine #(
    parameter WMEM  = "weights.mem",
    parameter QMEM  = "requant.mem",
    parameter FRAME = "frame.mem"
) (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        reg_en,
    input  wire        reg_we,
    input  wire [7:0]  reg_addr,
    input  wire [31:0] reg_wdata,
    output reg  [31:0] reg_rdata,
    output wire        irq_done,
    output wire        busy
);
    `include "layers.vh"
    localparam N = 4;
    localparam S_IDLE = 4'd0, S_LSET = 4'd1, S_TILE = 4'd2, S_RQ = 4'd3, S_NEXT = 4'd4,
               S_POOL = 4'd5, S_GAP = 4'd6, S_FC = 4'd7, S_FCW = 4'd8, S_LEND = 4'd9, S_DONE = 4'd10;

    reg [3:0]  st;
    reg        busy_r, done_r;
    reg [31:0] cycles;
    reg [2:0]  layer;
    reg        cur;            // activation buffer holding the current layer input
    reg        fc_head;        // 0: exit branch, 1: head
    reg        l8;
    reg [9:0]  lK;
    reg [6:0]  lCin, lCout, lWin, lHin, lWo, lHo;
    reg [1:0]  lS;
    reg        lPool;
    reg [15:0] lWb;
    reg [7:0]  lQr;            // requant record base
    reg [3:0]  lGroups;
    reg [3:0]  g;
    reg [12:0] p0;
    reg [6:0]  oy0, ox0;
    reg [1:0]  kh, kw;
    reg [6:0]  ci;
    reg [6:0]  ridx;
    reg [6:0]  py, px, pc, gc, gp;
    reg signed [31:0] gsum;
    reg [15:0] gvec [0:47];
    reg signed [47:0] head_lg [0:3];
    reg signed [47:0] exit_lg [0:1];

    // ---------------- datapath: tile engine ----------------
    reg         t_start, t_mode;
    reg  [9:0]  t_k;
    wire [9:0]  k_addr;
    wire        rd_en, t_busy, t_done;
    reg  [63:0] a_lanes_q, w_lanes_q;
    wire [N*N*96-1:0] acc_flat;
    dla_tile #(.N(N), .KW(10)) u_tile (
        .clk(clk), .rst_n(rst_n), .start(t_start), .mode(t_mode), .k_len(t_k),
        .k_addr(k_addr), .rd_en(rd_en), .a_lanes(a_lanes_q), .w_lanes(w_lanes_q),
        .busy(t_busy), .done(t_done), .acc_flat(acc_flat));

    // ---------------- memories ----------------
    reg          am_we, am_wsel;
    reg  [13:0]  am_waddr;
    reg  [15:0]  am_wdata;
    reg  [7:0]   am_rsel;
    reg  [111:0] am_raddr;
    wire [127:0] am_rdata;
    act_mem #(.FRAME(FRAME)) u_act (.clk(clk), .we(am_we), .wsel(am_wsel), .waddr(am_waddr), .wdata(am_wdata),
                                    .rsel(am_rsel), .raddr(am_raddr), .rdata(am_rdata));
    reg  [59:0]  wr_addr4;
    wire [63:0]  w_data4;
    wrom_m #(.FILE(WMEM)) u_w (.raddr(wr_addr4), .rdata(w_data4));
    reg  [31:0]  q_rec4;
    wire [383:0] q_data4;
    qrom_m #(.FILE(QMEM)) u_q (.rrec(q_rec4), .rdata(q_data4));

    // ---------------- im2col address generation (8 pixel lanes) ----------------
    reg  [13:0] ic_addr [0:7];
    reg  [7:0]  ic_ok;
    integer r;
    always @* begin : im2col
        reg [7:0] x; reg [6:0] y; reg signed [9:0] iy, ix;
        for (r = 0; r < 8; r = r + 1) begin
            x = ox0 + r; y = oy0;                            // pixel r of the tile, <= 2 row wraps
            if (x >= lWo) begin x = x - lWo; y = y + 1; end
            if (x >= lWo) begin x = x - lWo; y = y + 1; end
            iy = $signed({3'd0, y}) * $signed({8'd0, lS}) + $signed({8'd0, kh}) - 10'sd1;
            ix = $signed({3'd0, x[6:0]}) * $signed({8'd0, lS}) + $signed({8'd0, kw}) - 10'sd1;
            ic_ok[r] = !(p0 + r >= lWo * lHo || iy < 0 || ix < 0 || iy >= $signed({3'd0, lHin}) ||
                         ix >= $signed({3'd0, lWin}));
            ic_addr[r] = (iy[6:0] * lWin + ix[6:0]) * lCin + ci;
        end
    end

    // pooling / GAP addresses
    wire [13:0] pool_a  = ((2 * py) * lWo + 2 * px) * lCout + pc;
    wire [13:0] pool_r  = lWo * lCout;
    wire [13:0] pool_wa = (py * (lWo >> 1) + px) * lCout + pc;
    wire [6:0]  gC  = fc_head ? 7'd48 : 7'd32;
    wire [6:0]  gP  = fc_head ? 7'd16 : 7'd64;
    wire [4:0]  gSh = fc_head ? HEAD_GSH : EXIT_GSH;
    wire [13:0] gap_a = gp * gC + gc;

    // read-port routing
    integer q;
    always @* begin
        for (q = 0; q < 8; q = q + 1) begin
            am_raddr[14*q +: 14] = ic_addr[q];
            am_rsel[q] = cur;
        end
        if (st == S_POOL) begin
            am_raddr[0 +: 14]  = pool_a;          am_raddr[14 +: 14] = pool_a + lCout;
            am_raddr[28 +: 14] = pool_a + pool_r; am_raddr[42 +: 14] = pool_a + pool_r + lCout;
            am_rsel = {8{~cur}};
        end else if (st == S_GAP) begin
            am_raddr[0 +: 14] = gap_a;
        end
        for (q = 0; q < 4; q = q + 1)
            wr_addr4[15*q +: 15] = (st == S_FC || st == S_FCW)
                ? (fc_head ? HEAD_WBASE : EXIT_WBASE) + k_addr * 4 + q
                : lWb + (g * lK + k_addr) * 4 + q;
    end
    wire [15:0] rd16 [0:7];
    genvar gi;
    generate for (gi = 0; gi < 8; gi = gi + 1) begin : g_rd
        assign rd16[gi] = ic_ok[gi] ? am_rdata[16*gi +: 16] : 16'd0;
    end endgenerate

    // operand registers (data valid one cycle after rd_en, as from an SRAM)
    integer j;
    always @(posedge clk) begin
        if (rd_en) begin
            if (st == S_FC || st == S_FCW) a_lanes_q <= {48'd0, gvec[k_addr]};
            else for (j = 0; j < 4; j = j + 1)
                a_lanes_q[16*j +: 16] <= l8 ? {rd16[2*j+1][7:0], rd16[2*j][7:0]} : rd16[j];
            w_lanes_q <= w_data4;
        end
    end

    // ---------------- requantisation ----------------
    reg         rq_v;
    reg  signed [47:0] rq_acc, rq_bias;
    reg  [15:0] rq_m0;
    reg  [4:0]  rq_sh;
    reg         rq_o16, rq_relu;
    wire        rq_ov;
    wire signed [15:0] rq_y;
    reg  [13:0] wr_addr_d, wr_addr_q;
    reg         wr_ok_d, wr_ok_q;
    requant u_rq (.clk(clk), .rst_n(rst_n), .in_valid(rq_v), .acc(rq_acc), .bias(rq_bias), .m0(rq_m0),
                  .sh(rq_sh), .out16(rq_o16), .relu(rq_relu), .out_valid(rq_ov), .y(rq_y));

    reg [12:0] o_pix; reg [6:0] o_ch; reg signed [47:0] o_acc;
    always @* begin : dec
        reg [3:0] pe; reg [1:0] qq;
        if (l8) begin
            pe = ridx[5:2]; qq = ridx[1:0];
            o_pix = p0 + 2 * pe[3:2] + qq[1];
            o_ch  = g * 8 + 2 * pe[1:0] + qq[0];
            o_acc = {{24{acc_flat[pe*96 + qq*24 + 23]}}, acc_flat[pe*96 + qq*24 +: 24]};
        end else begin
            pe = ridx[3:0]; qq = 2'd0;
            o_pix = p0 + pe[3:2];
            o_ch  = g * 4 + pe[1:0];
            o_acc = acc_flat[pe*96 +: 48];
        end
    end
    always @* begin
        q_rec4 = {8'd0, 8'd0, 8'd0, lQr + o_ch};
        if (st == S_FCW)
            for (q = 0; q < 4; q = q + 1) q_rec4[8*q +: 8] = (fc_head ? HEAD_QBASE : EXIT_QBASE) + q;
    end

    // activation write port: requant write-back or pooling
    wire signed [15:0] pv0 = am_rdata[0 +: 16],  pv1 = am_rdata[16 +: 16];
    wire signed [15:0] pv2 = am_rdata[32 +: 16], pv3 = am_rdata[48 +: 16];
    wire signed [15:0] pm01 = (pv0 > pv1) ? pv0 : pv1;
    wire signed [15:0] pm23 = (pv2 > pv3) ? pv2 : pv3;
    wire signed [15:0] pmax = (pm01 > pm23) ? pm01 : pm23;
    always @* begin
        am_we = 1'b0; am_wsel = ~cur; am_waddr = wr_addr_q; am_wdata = rq_y;
        if (rq_ov && wr_ok_q) am_we = 1'b1;
        else if (st == S_POOL) begin am_we = 1'b1; am_wsel = cur; am_waddr = pool_wa; am_wdata = pmax; end
    end

    // ---------------- main FSM ----------------
    wire [6:0] nPix = l8 ? 7'd8 : 7'd4;
    wire [6:0] nOut = l8 ? 7'd64 : 7'd16;
    reg  [7:0] ox_n; reg [6:0] oy_n;
    always @* begin
        ox_n = ox0 + nPix; oy_n = oy0;
        if (ox_n >= lWo) begin ox_n = ox_n - lWo; oy_n = oy_n + 1; end
        if (ox_n >= lWo) begin ox_n = ox_n - lWo; oy_n = oy_n + 1; end
    end
    wire signed [31:0] gsum_n = gsum + $signed(am_rdata[15:0]);
    wire        [31:0] gsh_n  = (gSh != 0) ? ((gsum_n + (32'd1 << (gSh - 1))) >>> gSh) : gsum_n;

    integer m;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            st <= S_IDLE; busy_r <= 1'b0; done_r <= 1'b0; cycles <= 0; t_start <= 1'b0; rq_v <= 1'b0;
            wr_ok_d <= 1'b0; wr_ok_q <= 1'b0; layer <= 0; cur <= 1'b0; fc_head <= 1'b0;
        end else begin
            rq_v <= 1'b0;
            wr_ok_q <= wr_ok_d; wr_addr_q <= wr_addr_d; wr_ok_d <= 1'b0;
            if (busy_r) cycles <= cycles + 1;
            case (st)
                S_IDLE: if (reg_en && reg_we && reg_addr == 8'h00 && reg_wdata[0]) begin
                    busy_r <= 1'b1; done_r <= 1'b0; cycles <= 0; layer <= 0; cur <= 1'b0; st <= S_LSET;
                end
                S_LSET: begin
                    l8 <= lp(F_BITS, layer) == 8; lK <= lp(F_K, layer); lCin <= lp(F_CIN, layer);
                    lCout <= lp(F_COUT, layer); lWin <= lp(F_WIN, layer); lHin <= lp(F_HIN, layer);
                    lWo <= lp(F_WO, layer); lHo <= lp(F_HO, layer); lS <= lp(F_STRIDE, layer);
                    lPool <= lp(F_POOL, layer); lWb <= lp(F_WBASE, layer); lQr <= lp(F_QBASE, layer);
                    lGroups <= lp(F_GROUPS, layer);
                    g <= 0; p0 <= 0; oy0 <= 0; ox0 <= 0; kh <= 0; kw <= 0; ci <= 0;
                    t_mode <= lp(F_BITS, layer) == 16; t_k <= lp(F_K, layer);
                    st <= S_TILE;
                end
                S_TILE: begin
                    t_start <= 1'b1;
                    if (rd_en) begin                         // (ci, kw, kh) follow k_addr
                        if (ci == lCin - 1) begin
                            ci <= 0;
                            if (kw == 2'd2) begin kw <= 0; kh <= kh + 1'b1; end else kw <= kw + 1'b1;
                        end else ci <= ci + 1'b1;
                    end
                    if (t_done) begin t_start <= 1'b0; ridx <= 0; kh <= 0; kw <= 0; ci <= 0; st <= S_RQ; end
                end
                S_RQ: begin
                    rq_v <= 1'b1;
                    rq_acc  <= o_acc;
                    rq_bias <= $signed(q_data4[47:0]);
                    rq_m0   <= q_data4[63:48];
                    rq_sh   <= q_data4[68:64];
                    rq_relu <= q_data4[69];
                    rq_o16  <= q_data4[70];
                    wr_addr_d <= o_pix * lCout + o_ch;
                    wr_ok_d   <= (o_ch < lCout) && (o_pix < lWo * lHo);
                    if (ridx == nOut - 1) st <= S_NEXT; else ridx <= ridx + 1'b1;
                end
                S_NEXT: if (!wr_ok_d && !wr_ok_q && !t_done) begin
                    if (p0 + nPix < lWo * lHo) begin
                        p0 <= p0 + nPix; ox0 <= ox_n[6:0]; oy0 <= oy_n; st <= S_TILE;
                    end else if (g + 1 < lGroups) begin
                        g <= g + 1'b1; p0 <= 0; ox0 <= 0; oy0 <= 0; st <= S_TILE;
                    end else if (lPool) begin
                        py <= 0; px <= 0; pc <= 0; st <= S_POOL;
                    end else begin
                        cur <= ~cur; st <= S_LEND;
                    end
                end
                S_POOL: begin                                  // write port driven combinationally
                    if (pc == lCout - 1) begin
                        pc <= 0;
                        if (px == (lWo >> 1) - 1) begin
                            px <= 0;
                            if (py == (lHo >> 1) - 1) st <= S_LEND; else py <= py + 1'b1;
                        end else px <= px + 1'b1;
                    end else pc <= pc + 1'b1;
                end
                S_LEND: begin
                    if (layer == 3 || layer == 5) begin
                        fc_head <= (layer == 5); gc <= 0; gp <= 0; gsum <= 0; st <= S_GAP;
                    end else begin
                        layer <= layer + 1'b1; st <= S_LSET;
                    end
                end
                S_GAP: begin
                    if (gp == gP - 1) begin
                        gvec[gc] <= ($signed(gsh_n) > 32767) ? 16'd32767 : gsh_n[15:0];
                        gsum <= 0; gp <= 0;
                        if (gc == gC - 1) begin t_mode <= 1'b1; t_k <= gC; st <= S_FC; end
                        else gc <= gc + 1'b1;
                    end else begin
                        gsum <= gsum_n; gp <= gp + 1'b1;
                    end
                end
                S_FC: begin
                    t_start <= 1'b1;
                    if (t_done) begin t_start <= 1'b0; st <= S_FCW; end
                end
                S_FCW: begin
                    for (m = 0; m < 4; m = m + 1) begin
                        if (fc_head)
                            head_lg[m] <= $signed(acc_flat[m*96 +: 48]) + $signed(q_data4[96*m +: 48]);
                        else if (m < 2)
                            exit_lg[m] <= $signed(acc_flat[m*96 +: 48]) + $signed(q_data4[96*m +: 48]);
                    end
                    if (fc_head) st <= S_DONE;
                    else begin layer <= layer + 1'b1; st <= S_LSET; end
                end
                S_DONE: begin busy_r <= 1'b0; done_r <= 1'b1; st <= S_IDLE; end
                default: st <= S_IDLE;
            endcase
        end
    end
    assign irq_done = done_r;
    assign busy = busy_r;

    always @* begin
        reg_rdata = 32'd0;
        case (reg_addr)
            8'h04: reg_rdata = {30'd0, done_r, busy_r};
            8'h08: reg_rdata = cycles;
            8'h40: reg_rdata = head_lg[0][31:0]; 8'h44: reg_rdata = {{16{head_lg[0][47]}}, head_lg[0][47:32]};
            8'h48: reg_rdata = head_lg[1][31:0]; 8'h4c: reg_rdata = {{16{head_lg[1][47]}}, head_lg[1][47:32]};
            8'h50: reg_rdata = head_lg[2][31:0]; 8'h54: reg_rdata = {{16{head_lg[2][47]}}, head_lg[2][47:32]};
            8'h58: reg_rdata = head_lg[3][31:0]; 8'h5c: reg_rdata = {{16{head_lg[3][47]}}, head_lg[3][47:32]};
            8'h80: reg_rdata = exit_lg[0][31:0]; 8'h84: reg_rdata = {{16{exit_lg[0][47]}}, exit_lg[0][47:32]};
            8'h88: reg_rdata = exit_lg[1][31:0]; 8'h8c: reg_rdata = {{16{exit_lg[1][47]}}, exit_lg[1][47:32]};
            default: reg_rdata = 32'd0;
        endcase
    end
endmodule
`default_nettype wire
