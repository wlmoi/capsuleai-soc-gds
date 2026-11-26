// -----------------------------------------------------------------------------
// mem_models.v  --  memory macros of the CapsuleAI SoC.
// Behavioural models for simulation; with `SYNTH they become black boxes so that
// logic synthesis maps only the standard-cell logic (the macros come from the
// IHP SRAM generator / ROM, see Table II of the paper).
// -----------------------------------------------------------------------------
`default_nettype none
`ifdef SYNTH
(* blackbox *) module act_mem #(parameter FRAME = "") (input wire clk, input wire we, input wire wsel, input wire [13:0] waddr,
    input wire [15:0] wdata, input wire [7:0] rsel, input wire [111:0] raddr, output wire [127:0] rdata);
endmodule
(* blackbox *) module wrom_m #(parameter FILE = "") (input wire [59:0] raddr, output wire [63:0] rdata);
endmodule
(* blackbox *) module qrom_m #(parameter FILE = "") (input wire [31:0] rrec, output wire [383:0] rdata);
endmodule
(* blackbox *) module sram32 #(parameter FILE = "") (input wire clk, input wire en, input wire [3:0] we,
    input wire [11:0] addr, input wire [31:0] wdata, output wire [31:0] rdata);
endmodule
`else
// two 16384 x 16 activation buffers (ping-pong), 8 read ports, 1 write port
module act_mem #(parameter FRAME = "frame.mem") (input wire clk, input wire we, input wire wsel,
    input wire [13:0] waddr, input wire [15:0] wdata, input wire [7:0] rsel, input wire [111:0] raddr,
    output reg [127:0] rdata);
    reg [15:0] b0 [0:16383];
    reg [15:0] b1 [0:16383];
    initial $readmemh(FRAME, b0);
    integer i;
    always @* for (i = 0; i < 8; i = i + 1)
        rdata[16*i +: 16] = rsel[i] ? b1[raddr[14*i +: 14]] : b0[raddr[14*i +: 14]];
    always @(posedge clk) if (we) begin if (wsel) b1[waddr] <= wdata; else b0[waddr] <= wdata; end
endmodule
// 18608 x 16 weight ROM, 4 read ports (one per PE column lane)
module wrom_m #(parameter FILE = "weights.mem") (input wire [59:0] raddr, output reg [63:0] rdata);
    reg [15:0] m [0:18607];
    initial $readmemh(FILE, m);
    integer i;
    always @* for (i = 0; i < 4; i = i + 1) rdata[16*i +: 16] = m[raddr[15*i +: 15]];
endmodule
// requant constants: 174 records of 6 x 16 bits {0, flags, M0, bias[47:0]}, 4 record ports
module qrom_m #(parameter FILE = "requant.mem") (input wire [31:0] rrec, output reg [383:0] rdata);
    reg [15:0] m [0:1043];
    initial $readmemh(FILE, m);
    integer i, k;
    always @* for (i = 0; i < 4; i = i + 1) for (k = 0; k < 6; k = k + 1)
        rdata[96*i + 16*k +: 16] = m[rrec[8*i +: 8] * 6 + k];
endmodule
// 4096 x 32 firmware RAM with byte enables
module sram32 #(parameter FILE = "firmware.hex") (input wire clk, input wire en, input wire [3:0] we,
    input wire [11:0] addr, input wire [31:0] wdata, output reg [31:0] rdata);
    reg [31:0] m [0:4095];
    initial $readmemh(FILE, m);
    always @(posedge clk) if (en) begin
        rdata <= m[addr];
        if (we[0]) m[addr][7:0]   <= wdata[7:0];
        if (we[1]) m[addr][15:8]  <= wdata[15:8];
        if (we[2]) m[addr][23:16] <= wdata[23:16];
        if (we[3]) m[addr][31:24] <= wdata[31:24];
    end
endmodule
`endif
`default_nettype wire
