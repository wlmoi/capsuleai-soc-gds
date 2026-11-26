`timescale 1ns/1ps
module tb_soc;
    reg clk = 0, rst_n = 0;
    always #20 clk = ~clk;                       // 25 MHz
    wire [31:0] gpio, dbg; wire stb, trap;
    capsoc_top #(.FW("fw/firmware.hex"), .WMEM("mem/weights.mem"), .QMEM("mem/requant.mem"),
                 .FRAME(`FRAME)) dut (.clk(clk), .rst_n(rst_n), .gpio_out(gpio), .dbg_out(dbg),
                 .gpio_stb(stb), .trap(trap));
    integer cyc = 0;
    always @(posedge clk) cyc <= cyc + 1;
    initial begin
        #200 rst_n = 1;
        wait (stb || trap);
        #100;
        $display("RESULT gpio=%08x cls=%0d exited=%0d engine_cycles=%0d total_cycles=%0d trap=%0d",
                 gpio, gpio[1:0], gpio[8], dbg, cyc, trap);
        $display("HEAD %0d %0d %0d %0d", dut.u_eng.head_lg[0], dut.u_eng.head_lg[1], dut.u_eng.head_lg[2], dut.u_eng.head_lg[3]);
        $display("EXIT %0d %0d", dut.u_eng.exit_lg[0], dut.u_eng.exit_lg[1]);
        $finish;
    end
    initial begin #400_000_000; $display("TIMEOUT"); $finish; end
endmodule
