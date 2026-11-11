`timescale 1ns/1ps
import uvm_pkg::*;
`include "uvm_macros.svh"
import cpu_uvm_pkg::*;

module tb_top;
  logic clk;
  logic rst_n;

  initial clk = 0;
  always #5 clk = ~clk;

  cpu_if vif(.clk(clk), .rst_n(rst_n));

  // DUT: the FIXED rv32i_cpu (instr corrected to input -- see
  // EXPLANATION.md Part 7 for why the original wouldn't even compile).
  rv32i_cpu u_dut (
    .clk        (vif.clk),
    .rst_n      (vif.rst_n),
    .pc         (vif.pc),
    .instr      (vif.instr),
    .data_addr  (vif.data_addr),
    .data_we    (vif.data_we),
    .data_wdata (vif.data_wdata),
    .data_rdata (vif.data_rdata),
    .halted     (vif.halted)
  );

  // Debug tap -- NOT a real DUT port, just how the scoreboard reads
  // final register values without hierarchical refs scattered through
  // verification code. See cpu_if.sv's header comment.
  assign vif.dbg_regs = u_dut.rf.regs;

  initial begin
    rst_n = 0;
    uvm_config_db#(virtual cpu_if)::set(null, "*", "vif", vif);
  end

  // Reset release: rst_n must be held low across >=1 posedge clk for the
  // synchronous reset to take effect -- see EXPLANATION.md Part 7 (I/O
  // and protocol section) for why.
  initial begin
    rst_n = 0;
    repeat (2) @(posedge clk);
    rst_n = 1;
  end

  initial run_test();

  initial begin
    #10000;
    `uvm_fatal("TIMEOUT", "Test did not finish in time")
  end
endmodule
