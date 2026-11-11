// Assertions for the combinational ALU. Sampled on clk supplied by the bind/test harness.
// Each property maps to alu_spec.md and the corresponding RTL operation.
module alu_assertions (
    input logic        clk,
    input logic [31:0] a,
    input logic [31:0] b,
    input logic [3:0]  alu_op,
    input logic [31:0] y,
    input logic        zero,
    input logic        lt_signed,
    input logic        lt_unsigned
);
    default clocking cb @(posedge clk); endclocking

    // REQ-ADD: operation 0 computes 32-bit addition.
    ap_add: assert property (alu_op == 4'd0 |-> y == (a + b));
    // REQ-SUB: operation 1 computes 32-bit subtraction.
    ap_sub: assert property (alu_op == 4'd1 |-> y == (a - b));
    // REQ-AND/OR/XOR: bitwise operations.
    ap_and: assert property (alu_op == 4'd2 |-> y == (a & b));
    ap_or : assert property (alu_op == 4'd3 |-> y == (a | b));
    ap_xor: assert property (alu_op == 4'd4 |-> y == (a ^ b));
    // REQ-SLT/SLTU: comparison result is zero-extended 0 or 1.
    ap_slt: assert property (alu_op == 4'd5 |-> y == (($signed(a) < $signed(b)) ? 32'd1 : 32'd0));
    ap_sltu: assert property (alu_op == 4'd6 |-> y == ((a < b) ? 32'd1 : 32'd0));
    // REQ-SHIFT: shifts use the low five bits of b.
    ap_sll: assert property (alu_op == 4'd7 |-> y == (a << b[4:0]));
    ap_srl: assert property (alu_op == 4'd8 |-> y == (a >> b[4:0]));
    ap_sra: assert property (alu_op == 4'd9 |-> y == ($signed(a) >>> b[4:0]));
    // REQ-DEFAULT: unassigned operation codes produce zero.
    ap_default: assert property (alu_op inside {[4'd10:4'd15]} |-> y == 32'd0);
    // REQ-FLAGS: output flags are combinational functions of inputs/result.
    ap_zero: assert property (zero == (y == 32'd0));
    ap_lts: assert property (lt_signed == ($signed(a) < $signed(b)));
    ap_ltu: assert property (lt_unsigned == (a < b));

    // Useful scenario coverage; not a proof of completeness.
    cp_op: cover property (alu_op inside {[4'd0:4'd9]});
    cp_default: cover property (alu_op inside {[4'd10:4'd15]});
endmodule
