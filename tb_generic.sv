`timescale 1ns/1ps
module tb_generic;
    logic clk, rst_n, halted;
    mini_cpu_top dut(.clk(clk), .rst_n(rst_n), .halted(halted));
    initial clk = 0;
    always #5 clk = ~clk;

    string prog_file;
    initial begin
        if (!$value$plusargs("PROG=%s", prog_file)) prog_file = "";
        rst_n = 0;
        $readmemh(prog_file, dut.mem.mem);
        repeat (2) @(posedge clk);
        rst_n = 1;
        wait(halted);
        #1;
        for (int i = 0; i < 11; i++)
            $display("x%0d=%0d", i, dut.cpu.rf.regs[i]);
        $display("MEM0=%0d", dut.mem.mem[0]);
        $finish;
    end
    initial begin #2000; $display("TIMEOUT"); $finish; end
endmodule
