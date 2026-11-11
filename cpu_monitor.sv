// Analysis item broadcast by the monitor: one snapshot per cycle of
// what the CPU is doing on its two external interfaces.
class cpu_obs_item extends uvm_sequence_item;
  `uvm_object_utils(cpu_obs_item)
  logic [31:0] pc;
  logic [31:0] instr;
  logic        data_we;
  logic [31:0] data_addr;
  logic [31:0] data_wdata;
  logic        halted;

  function new(string name = "cpu_obs_item");
    super.new(name);
  endfunction
endclass

class cpu_monitor extends uvm_monitor;
  `uvm_component_utils(cpu_monitor)
  virtual cpu_if vif;
  uvm_analysis_port #(cpu_obs_item) ap;

  function new(string name, uvm_component parent);
    super.new(name, parent);
    ap = new("ap", this);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(virtual cpu_if)::get(this, "", "vif", vif))
      `uvm_fatal("NOVIF", "cpu_monitor: virtual interface not set")
  endfunction

  task run_phase(uvm_phase phase);
    forever begin
      @(posedge vif.clk);
      if (vif.rst_n) begin
        cpu_obs_item tx = cpu_obs_item::type_id::create("tx");
        tx.pc         = vif.pc;
        tx.instr      = vif.instr;
        tx.data_we    = vif.data_we;
        tx.data_addr  = vif.data_addr;
        tx.data_wdata = vif.data_wdata;
        tx.halted     = vif.halted;
        ap.write(tx);
      end
    end
  endtask
endclass
