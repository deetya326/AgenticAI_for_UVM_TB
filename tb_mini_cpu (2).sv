`timescale 1ns/1ps

module tb_mini_cpu;

    logic clk;
    logic rst_n;
    logic halted;

    mini_cpu_top dut (
        .clk    (clk),
        .rst_n  (rst_n),
        .halted (halted)
    );

    // 10 ns clock
    initial clk = 1'b0;
    always #5 clk = ~clk;

    initial begin
        rst_n = 1'b0;

        // Program:
        //
        // x1 = 5
        // x2 = 7
        // x3 = x1 + x2       => 12
        // MEM[0] = x3
        // x4 = MEM[0]       => 12
        // if (x3 == x4) skip next ADDI
        // EBREAK
        //
        // 0: ADDI x1, x0, 5
        // 4: ADDI x2, x0, 7
        // 8: ADD  x3, x1, x2
        // 12: SW x3, 0(x0)
        // 16: LW x4, 0(x0)
        // 20: BEQ x3, x4, +8
        // 24: ADDI x5, x0, 1       (should be skipped)
        // 28: EBREAK

        dut.mem.mem[0] = 32'h00500093;
        dut.mem.mem[1] = 32'h00700113;
        dut.mem.mem[2] = 32'h002081B3;
        dut.mem.mem[3] = 32'h00302023;
        dut.mem.mem[4] = 32'h00002203;
        dut.mem.mem[5] = 32'h00418463;
        dut.mem.mem[6] = 32'h00100293;
        dut.mem.mem[7] = 32'h00100073;

        // Hold reset for two cycles.
        repeat (2) @(posedge clk);
        rst_n = 1'b1;

        // Wait for EBREAK.
        wait (halted);

        #1;

        $display("========================================");
        $display(" MINI RV32I CPU DEMO COMPLETE");
        $display(" x1 = %0d", dut.cpu.rf.regs[1]);
        $display(" x2 = %0d", dut.cpu.rf.regs[2]);
        $display(" x3 = %0d", dut.cpu.rf.regs[3]);
        $display(" x4 = %0d", dut.cpu.rf.regs[4]);
        $display(" x5 = %0d", dut.cpu.rf.regs[5]);
        $display(" MEM[0] = %0d", dut.mem.mem[0]);
        $display("========================================");

        if (dut.cpu.rf.regs[1] !== 32'd5)
            $fatal(1, "FAIL: x1 incorrect");

        if (dut.cpu.rf.regs[2] !== 32'd7)
            $fatal(1, "FAIL: x2 incorrect");

        if (dut.cpu.rf.regs[3] !== 32'd12)
            $fatal(1, "FAIL: x3 incorrect");

        if (dut.mem.mem[0] !== 32'd12)
            $fatal(1, "FAIL: memory write incorrect");

        if (dut.cpu.rf.regs[4] !== 32'd12)
            $fatal(1, "FAIL: x4 load incorrect");

        if (dut.cpu.rf.regs[5] !== 32'd0)
            $fatal(1, "FAIL: branch did not skip ADDI");

        $display("PASS: all demo checks passed.");
        $finish;
    end

    initial begin
        #1000;
        $fatal(1, "TIMEOUT: CPU did not reach EBREAK.");
    end

endmodule
