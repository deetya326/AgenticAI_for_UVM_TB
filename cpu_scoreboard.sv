// Each test case sets expected_regs[reg_index] = expected_value before
// starting the sequence. Once the monitor reports halted==1 for the
// first time, the scoreboard reads the debug register tap and checks
// every expected entry. Anything not listed in expected_regs is not
// checked -- this only verifies what the test case actually specified.
class cpu_scoreboard extends uvm_subscriber #(cpu_obs_item);
  `uvm_component_utils(cpu_scoreboard)
  virtual cpu_if vif;

  int  expected_regs[int];   // reg_index -> expected value, set by the test
  bit  checked;
  int  errors;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(virtual cpu_if)::get(this, "", "vif", vif))
      `uvm_fatal("NOVIF", "cpu_scoreboard: virtual interface not set")
  endfunction

  function void write(cpu_obs_item t);
    if (t.halted && !checked) begin
      checked = 1;
      foreach (expected_regs[idx]) begin
        int actual = vif.dbg_regs[idx];
        if (actual !== expected_regs[idx]) begin
          errors++;
          `uvm_error("REGMISMATCH",
            $sformatf("x%0d: expected %0d, got %0d", idx, expected_regs[idx], actual))
        end else begin
          `uvm_info("REGCHECK",
            $sformatf("x%0d == %0d (PASS)", idx, actual), UVM_LOW)
        end
      end
    end
  endfunction

  function void report_phase(uvm_phase phase);
    if (!checked)
      `uvm_error("NOHALT", "CPU never asserted halted -- test did not reach EBREAK")
    else if (errors == 0)
      `uvm_info("SCOREBOARD", "ALL CHECKS PASSED", UVM_NONE)
    else
      `uvm_error("SCOREBOARD", $sformatf("%0d check(s) FAILED", errors))
  endfunction
endclass
