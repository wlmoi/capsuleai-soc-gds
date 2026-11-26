// -----------------------------------------------------------------------------
// capsoc_top.v  --  CapsuleAI SoC: PicoRV32 + CNN engine + firmware RAM + GPIO
//   0x0000_0000  16 KB RAM (firmware + stack, loaded from firmware.hex)
//   0x1000_0000  CNN engine registers (cnn_engine.v)
//   0x2000_0000  GPIO out [31:0] (triage result), 0x2000_0004 debug word
// -----------------------------------------------------------------------------
`default_nettype none
module capsoc_top #(
    parameter FW    = "firmware.hex",
    parameter WMEM  = "weights.mem",
    parameter QMEM  = "requant.mem",
    parameter FRAME = "frame.mem",
    parameter CPU_SLEEP = 1
) (
    input  wire        clk,
    input  wire        rst_n,
    output reg  [31:0] gpio_out,
    output reg  [31:0] dbg_out,
    output reg         gpio_stb,
    output wire        trap
);
    wire        mem_valid, mem_instr;
    reg         mem_ready;
    wire [31:0] mem_addr, mem_wdata;
    wire [3:0]  mem_wstrb;
    reg  [31:0] mem_rdata;

    wire engine_busy;
    wire cpu_clk;
    generate if (CPU_SLEEP) begin : sleep_clock
        wire keep_running = !rst_n || !engine_busy || mem_ready;
`ifdef SYNTH
        sg13g2_lgcp_1 gate (.CLK(clk), .GATE(keep_running), .GCLK(cpu_clk));
`else
        reg clock_enabled;
        // Let the CPU acknowledge start before sleeping. The low-phase
        // latch keeps enable changes from truncating a high clock pulse.
        always @*
            if (!clk)
                clock_enabled <= keep_running;
        assign cpu_clk = clk && clock_enabled;
`endif
    end else begin : running_clock
        assign cpu_clk = clk;
    end endgenerate

    picorv32 #(
        .ENABLE_MUL(1), .ENABLE_DIV(1), .COMPRESSED_ISA(1), .ENABLE_IRQ(0),
        .PROGADDR_RESET(32'h0000_0000), .STACKADDR(32'h0000_4000)
    ) u_cpu (
        .clk(cpu_clk), .resetn(rst_n), .trap(trap),
        .mem_valid(mem_valid), .mem_instr(mem_instr), .mem_ready(mem_ready),
        .mem_addr(mem_addr), .mem_wdata(mem_wdata), .mem_wstrb(mem_wstrb), .mem_rdata(mem_rdata),
        .mem_la_read(), .mem_la_write(), .mem_la_addr(), .mem_la_wdata(), .mem_la_wstrb(),
        .pcpi_valid(), .pcpi_insn(), .pcpi_rs1(), .pcpi_rs2(), .pcpi_wr(1'b0), .pcpi_rd(32'd0),
        .pcpi_wait(1'b0), .pcpi_ready(1'b0), .irq(32'd0), .eoi(),
        .trace_valid(), .trace_data());

    // firmware RAM (SRAM macro, 1-cycle read latency)
    wire sel_ram = mem_addr[31:28] == 4'h0;
    wire sel_eng = mem_addr[31:28] == 4'h1;
    wire sel_gp  = mem_addr[31:28] == 4'h2;
    wire        req = mem_valid && !mem_ready && (!CPU_SLEEP || !engine_busy);
    wire [31:0] ram_rdata, eng_rdata;
    sram32 #(.FILE(FW)) u_ram (.clk(clk), .en(req && sel_ram), .we(mem_wstrb), .addr(mem_addr[13:2]),
                               .wdata(mem_wdata), .rdata(ram_rdata));
    cnn_engine #(.WMEM(WMEM), .QMEM(QMEM), .FRAME(FRAME)) u_eng (
        .clk(clk), .rst_n(rst_n), .reg_en(req && sel_eng), .reg_we(|mem_wstrb),
        .reg_addr(mem_addr[7:0]), .reg_wdata(mem_wdata), .reg_rdata(eng_rdata),
        .irq_done(), .busy(engine_busy));

    reg        was_ram;
    reg [31:0] io_rdata;
    always @* mem_rdata = was_ram ? ram_rdata : io_rdata;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mem_ready <= 1'b0; gpio_out <= 0; dbg_out <= 0; gpio_stb <= 1'b0; was_ram <= 1'b0; io_rdata <= 0;
        end else begin
            mem_ready <= 1'b0; gpio_stb <= 1'b0;
            if (req) begin
                mem_ready <= 1'b1;
                was_ram   <= sel_ram;
                io_rdata  <= sel_eng ? eng_rdata : 32'd0;
                if (sel_gp && |mem_wstrb) begin
                    if (mem_addr[2]) dbg_out <= mem_wdata; else begin gpio_out <= mem_wdata; gpio_stb <= 1'b1; end
                end
            end
        end
    end
endmodule
`default_nettype wire
