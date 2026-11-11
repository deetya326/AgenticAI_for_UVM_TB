class cpu_program_item extends uvm_sequence_item;
  `uvm_object_utils(cpu_program_item)

  // Raw instruction words, one per 32-bit-aligned memory location, i.e.
  // instr_words[i] lives at byte address i*4.
  rand logic [31:0] instr_words[$];

  function new(string name = "cpu_program_item");
    super.new(name);
  endfunction
endclass
