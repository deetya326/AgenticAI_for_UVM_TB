// Formal protocol definition for rv32i_cpu, standalone (memory external).
// Timing per SYSTEM_EXPLAINED.md Part 4:
//   - instruction fetch: combinational read, zero wait states
//   - data read:         combinational, same cycle as data_addr
//   - data write:        synchronous, commits next posedge clk if data_we=1
//   - reset:             synchronous, active-low, must hold >=1 posedge clk
// No valid/ready/ack anywhere -- this is NOT a handshook bus.
//
// dbg_regs is not part of the real DUT interface -- it's a debug tap bound
// in tb_top.sv (assign cpu_if.dbg_regs = dut.rf.regs;) purely so the
// scoreboard can check final register values without hierarchical
// references scattered through verification code. Remove for a DUT that
// exposes registers through a real port/debug bus instead.

interface cpu_if (input logic clk, input logic rst_n);
  logic [31:0] pc;
  logic [31:0] instr;
  logic [31:0] data_addr;
  logic        data_we;
  logic [31:0] data_wdata;
  logic [31:0] data_rdata;
  logic        halted;

  logic [31:0] dbg_regs [0:31];   // debug tap, see note above

  modport DUT (
    input  clk, rst_n, instr, data_rdata,
    output pc, data_addr, data_we, data_wdata, halted
  );

  modport TB (
    input  clk, rst_n, pc, data_addr, data_we, data_wdata, halted, dbg_regs,
    output instr, data_rdata
  );
endinterface
