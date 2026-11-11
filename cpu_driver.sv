// The CPU is the bus master (it addresses memory, memory responds) --
// there's no external stimulus to "drive" onto the CPU's own control
// signals. So this driver's real job is playing the part of the memory:
// preload a program once per test (from the sequence item), then run a
// background responder that continuously supplies instr/data_rdata based
// on whatever pc/data_addr the DUT is currently driving, and commits
// writes on the clock edge -- exactly the timing described in
// SYSTEM_EXPLAINED.md Part 4.2.

class cpu_driver extends uvm_driver #(cpu_program_item);
  `uvm_component_utils(cpu_driver)
  virtual cpu_if vif;

  logic [31:0] imem [0:255];   // word-addressed instruction memory model
  logic [31:0] dmem [0:255];   // word-addressed data memory model

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(virtual cpu_if)::get(this, "", "vif", vif))
      `uvm_fatal("NOVIF", "cpu_driver: virtual interface not set")
  endfunction

  task run_phase(uvm_phase phase);
    fork
      load_program_loop();
      memory_responder();
      write_committer();
    join
  endtask

  // Pulls one program per sequence item and preloads both memory arrays.
  // Data memory always starts zeroed (matches dual_port_ram.sv's initial
  // block); only instruction memory is preloaded from the item.
  task load_program_loop();
    forever begin
      cpu_program_item item;
      seq_item_port.get_next_item(item);
      foreach (dmem[i]) dmem[i] = 32'd0;
      foreach (imem[i]) imem[i] = 32'd0;
      foreach (item.instr_words[i]) imem[i] = item.instr_words[i];
      seq_item_port.item_done();
    end
  endtask

  // Combinational fetch/read every cycle; synchronous write on posedge --
  // matches dual_port_ram.sv exactly so the standalone rv32i_cpu sees the
  // same timing it would see wired to the real RAM.
  task memory_responder();
    forever begin
      @(vif.pc or vif.data_addr);
      vif.instr      = imem[vif.pc[9:2]];
      vif.data_rdata = dmem[vif.data_addr[9:2]];
    end
  endtask

  // Separate always-block-style writer, since writes must commit strictly
  // on the clock edge regardless of what triggered the block above.
  task automatic write_committer();
    forever begin
      @(posedge vif.clk);
      if (vif.data_we)
        dmem[vif.data_addr[9:2]] <= vif.data_wdata;
    end
  endtask
endclass
