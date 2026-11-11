class cpu_base_test extends uvm_test;
  `uvm_component_utils(cpu_base_test)
  cpu_env env;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    env = cpu_env::type_id::create("env", this);
  endfunction
endclass

class alu_reg_test extends cpu_base_test;
  `uvm_component_utils(alu_reg_test)
  function new(string name, uvm_component parent); super.new(name, parent); endfunction
  task run_phase(uvm_phase phase);
    alu_reg_sequence seq = alu_reg_sequence::type_id::create("seq");
    phase.raise_objection(this);
    env.scoreboard.expected_regs['{1:5, 2:7, 3:12, 4:2, 5:268435456, 6:20}];
    seq.start(env.sequencer);
    #200;
    phase.drop_objection(this);
  endtask
endclass

class load_store_test extends cpu_base_test;
  `uvm_component_utils(load_store_test)
  function new(string name, uvm_component parent); super.new(name, parent); endfunction
  task run_phase(uvm_phase phase);
    load_store_sequence seq = load_store_sequence::type_id::create("seq");
    phase.raise_objection(this);
    env.scoreboard.expected_regs['{1:5, 2:7, 3:12, 4:12}];
    seq.start(env.sequencer);
    #200;
    phase.drop_objection(this);
  endtask
endclass

class branch_test extends cpu_base_test;
  `uvm_component_utils(branch_test)
  function new(string name, uvm_component parent); super.new(name, parent); endfunction
  task run_phase(uvm_phase phase);
    branch_sequence seq = branch_sequence::type_id::create("seq");
    phase.raise_objection(this);
    env.scoreboard.expected_regs['{1:5, 2:5, 3:0, 4:1, 5:3, 6:4, 7:0, 8:1}];
    seq.start(env.sequencer);
    #200;
    phase.drop_objection(this);
  endtask
endclass

class illegal_opcode_test extends cpu_base_test;
  `uvm_component_utils(illegal_opcode_test)
  function new(string name, uvm_component parent); super.new(name, parent); endfunction
  task run_phase(uvm_phase phase);
    illegal_opcode_sequence seq = illegal_opcode_sequence::type_id::create("seq");
    phase.raise_objection(this);
    env.scoreboard.expected_regs['{1:42}];
    seq.start(env.sequencer);
    #200;
    phase.drop_objection(this);
  endtask
endclass

class x0_immutable_test extends cpu_base_test;
  `uvm_component_utils(x0_immutable_test)
  function new(string name, uvm_component parent); super.new(name, parent); endfunction
  task run_phase(uvm_phase phase);
    x0_immutable_sequence seq = x0_immutable_sequence::type_id::create("seq");
    phase.raise_objection(this);
    env.scoreboard.expected_regs['{0:0}];
    seq.start(env.sequencer);
    #200;
    phase.drop_objection(this);
  endtask
endclass

// NOT RUN BY DEFAULT -- see cpu_sequences.sv's jalr_sequence comment.
// Included so the shape exists once the encoding/RTL issue is resolved.
class jalr_test extends cpu_base_test;
  `uvm_component_utils(jalr_test)
  function new(string name, uvm_component parent); super.new(name, parent); endfunction
  task run_phase(uvm_phase phase);
    jalr_sequence seq = jalr_sequence::type_id::create("seq");
    phase.raise_objection(this);
    // expected_regs intentionally left empty -- outcome not yet trusted
    seq.start(env.sequencer);
    #200;
    phase.drop_objection(this);
  endtask
endclass
