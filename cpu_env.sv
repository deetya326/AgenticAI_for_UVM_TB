typedef uvm_sequencer #(cpu_program_item) cpu_sequencer;

class cpu_env extends uvm_env;
  `uvm_component_utils(cpu_env)

  cpu_driver     driver;
  cpu_sequencer  sequencer;
  cpu_monitor    monitor;
  cpu_scoreboard scoreboard;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    driver     = cpu_driver::type_id::create("driver", this);
    sequencer  = cpu_sequencer::type_id::create("sequencer", this);
    monitor    = cpu_monitor::type_id::create("monitor", this);
    scoreboard = cpu_scoreboard::type_id::create("scoreboard", this);
  endfunction

  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    driver.seq_item_port.connect(sequencer.seq_item_export);
    monitor.ap.connect(scoreboard.analysis_export);
  endfunction
endclass
