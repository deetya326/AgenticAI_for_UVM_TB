interface alu_if(input logic clk);
    logic [31:0] a, b;
    logic [3:0] alu_op;
    logic [31:0] y;
    logic zero, lt_signed, lt_unsigned;
    clocking drv_cb @(negedge clk);
        output a, b, alu_op;
    endclocking
    clocking mon_cb @(posedge clk);
        input a, b, alu_op, y, zero, lt_signed, lt_unsigned;
    endclocking
endinterface
