`timescale 1ns/1ps
module tb_alu_uvm;
    import uvm_pkg::*;
    import alu_uvm_pkg::*;
    bit clk=0;
    always #5 clk=~clk;
    alu_if vif(clk);
    alu dut(.a(vif.a),.b(vif.b),.alu_op(vif.alu_op),.y(vif.y),
            .zero(vif.zero),.lt_signed(vif.lt_signed),.lt_unsigned(vif.lt_unsigned));
    alu_assertions sva(.clk(clk),.a(vif.a),.b(vif.b),.alu_op(vif.alu_op),.y(vif.y),
                       .zero(vif.zero),.lt_signed(vif.lt_signed),.lt_unsigned(vif.lt_unsigned));
    initial begin
        vif.a='0; vif.b='0; vif.alu_op='0;
        uvm_config_db#(virtual alu_if)::set(null,"*","vif",vif);
        run_test("alu_test");
    end
endmodule
