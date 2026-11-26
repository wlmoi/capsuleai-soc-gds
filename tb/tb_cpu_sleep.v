`timescale 1ns/1ps
module tb_cpu_sleep;
    reg clk = 0, rst_n = 0;
    always #20 clk = ~clk;
    wire [31:0] gpio0, gpio1, dbg0, dbg1;
    wire stb0, stb1, trap0, trap1;
    reg seen0 = 0, seen1 = 0;
    integer busy0 = 0, busy1 = 0;
    capsoc_top #(.FW("fw/firmware.hex"), .CPU_SLEEP(0)) baseline
        (clk, rst_n, gpio0, dbg0, stb0, trap0);
    capsoc_top #(.FW("fw/firmware.hex"), .CPU_SLEEP(1)) candidate
        (clk, rst_n, gpio1, dbg1, stb1, trap1);
    always @(posedge baseline.cpu_clk) if (baseline.engine_busy) busy0 <= busy0 + 1;
    always @(posedge candidate.cpu_clk) if (candidate.engine_busy) busy1 <= busy1 + 1;
    always @(posedge stb0) seen0 <= 1;
    always @(posedge stb1) seen1 <= 1;
    initial begin
        #191 rst_n = 1;
        wait (seen0 && seen1);
        #1;
        if (trap0 || trap1 || gpio0 !== 32'hCA000100 || gpio0 !== gpio1 ||
            dbg0 !== 172555 || dbg0 !== dbg1 || busy0 !== 172555 || busy1 !== 1)
            $fatal(1, "Mismatch: GPIO %h/%h, debug %d/%d, busy clocks %d/%d",
                   gpio0, gpio1, dbg0, dbg1, busy0, busy1);
        $display("PASS: GPIO=%h, CNN cycles=%d, CPU busy clocks %d -> %d",
                 gpio1, dbg1, busy0, busy1);
        $finish;
    end
    initial begin #8000000; $fatal(1, "CPU sleep regression timed out"); end
endmodule

// Fixed-latency register fixture. Exercises the real PicoRV32, firmware,
// and bus, without running the accelerator datapath.
module cnn_engine #(parameter WMEM="", QMEM="", FRAME="") (
    input wire clk, rst_n, reg_en, reg_we,
    input wire [7:0] reg_addr,
    input wire [31:0] reg_wdata,
    output reg [31:0] reg_rdata,
    output reg irq_done, busy
);
    integer remaining;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin busy <= 0; irq_done <= 0; remaining <= 0; end
        else if (reg_en && reg_we && reg_addr == 0 && reg_wdata[0]) begin
            busy <= 1; irq_done <= 0; remaining <= 172555;
        end else if (busy) begin
            remaining <= remaining - 1;
            if (remaining == 1) begin busy <= 0; irq_done <= 1; end
        end
    end
    always @* begin
        case (reg_addr)
            8'h04: reg_rdata = {30'b0, irq_done, busy};
            8'h08: reg_rdata = 172555;
            8'h80: reg_rdata = 32'd300000000;
            default: reg_rdata = 0;
        endcase
    end
endmodule
