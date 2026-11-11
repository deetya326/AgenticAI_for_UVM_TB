// Each sequence below is one "test case" in the verification sense: a
// specific program plus the specific register values it should produce.
// Machine code was generated with a small Python RV32I encoder and each
// program's actual outcome was confirmed by running it through iverilog
// against the (fixed) RTL directly -- see EXPLANATION.md Part 7 for the
// ground-truth run log, including one open anomaly (jalr_test) that is
// NOT yet resolved -- do not treat that one's expected values as trusted
// until it's root-caused.

class cpu_base_sequence extends uvm_sequence #(cpu_program_item);
  `uvm_object_utils(cpu_base_sequence)
  logic [31:0] words[$];

  function new(string name = "cpu_base_sequence");
    super.new(name);
  endfunction

  task body();
    cpu_program_item item = cpu_program_item::type_id::create("item");
    start_item(item);
    item.instr_words = words;
    finish_item(item);
  endtask
endclass

// Test case 1: immediate + register-register ALU ops (ADDI/ADD/SUB/LUI/AUIPC)
// Verified outcome: x1=5 x2=7 x3=12 x4=2 x5=268435456 x6=20
class alu_reg_sequence extends cpu_base_sequence;
  `uvm_object_utils(alu_reg_sequence)
  function new(string name = "alu_reg_sequence");
    super.new(name);
    words = '{32'h00500093, 32'h00700113, 32'h002081b3, 32'h40110233,
              32'h100002b7, 32'h00000317, 32'h00100073};
  endfunction
endclass

// Test case 2: store then load roundtrip through data memory
// Verified outcome: x1=5 x2=7 x3=12 x4=12 MEM[0]=12
class load_store_sequence extends cpu_base_sequence;
  `uvm_object_utils(load_store_sequence)
  function new(string name = "load_store_sequence");
    super.new(name);
    words = '{32'h00500093, 32'h00700113, 32'h002081b3,
              32'h00302023, 32'h00002203, 32'h00100073};
  endfunction
endclass

// Test case 3: BEQ taken + BNE taken, each skipping one instruction
// Verified outcome: x1=5 x2=5 x3=0(skipped) x4=1 x5=3 x6=4 x7=0(skipped) x8=1
class branch_sequence extends cpu_base_sequence;
  `uvm_object_utils(branch_sequence)
  function new(string name = "branch_sequence");
    super.new(name);
    words = '{32'h00500093, 32'h00500113, 32'h00208463, 32'h06300193,
              32'h00100213, 32'h00300293, 32'h00400313, 32'h00629463,
              32'h06300393, 32'h00100413, 32'h00100073};
  endfunction
endclass

// Test case 4: illegal/unimplemented opcode must be a no-op
// Verified outcome: x1=42 (unchanged by the illegal word), no crash
class illegal_opcode_sequence extends cpu_base_sequence;
  `uvm_object_utils(illegal_opcode_sequence)
  function new(string name = "illegal_opcode_sequence");
    super.new(name);
    words = '{32'h02a00093, 32'h0000007f, 32'h00100073};
  endfunction
endclass

// Test case 5: x0 is hardwired to zero and cannot be written
// Verified outcome: x0=0 even after an ADDI targeting x0
class x0_immutable_sequence extends cpu_base_sequence;
  `uvm_object_utils(x0_immutable_sequence)
  function new(string name = "x0_immutable_sequence");
    super.new(name);
    words = '{32'h07b00013, 32'h00000093, 32'h00100073};
  endfunction
endclass

// Test case 6: JALR target alignment -- OPEN, NOT YET TRUSTED.
// This program timed out in ground-truth simulation instead of reaching
// EBREAK. Either the hand-assembled JALR encoding/offset here is wrong,
// or there's a real RTL bug in JALR handling -- undetermined. Do not
// wire this into a passing test until it's root-caused; it's included
// so the team has a starting point rather than silently missing JALR
// coverage.
class jalr_sequence extends cpu_base_sequence;
  `uvm_object_utils(jalr_sequence)
  function new(string name = "jalr_sequence");
    super.new(name);
    words = '{32'h01100093, 32'h00c08167, 32'h06f00493, 32'h0de00513, 32'h00100073};
  endfunction
endclass
