module mini_cpu_top #(
    parameter integer MEM_DEPTH = 256
) (
    input  logic clk,
    input  logic rst_n,
    output logic halted
);

    logic [31:0] pc;
    logic [31:0] instr;

    logic [31:0] data_addr;
    logic        data_we;
    logic [31:0] data_wdata;
    logic [31:0] data_rdata;

    // Dual-port RAM:
    //   Port A = instruction fetch
    //   Port B = CPU data access
    dual_port_ram #(
        .DEPTH(MEM_DEPTH)
    ) mem (
        .clk      (clk),

        .a_addr   (pc),
        .a_rdata  (instr),

        .b_addr   (data_addr),
        .b_we     (data_we),
        .b_wdata  (data_wdata),
        .b_rdata  (data_rdata)
    );

    rv32i_cpu cpu (
        .clk       (clk),
        .rst_n     (rst_n),
        .pc        (pc),
        .instr     (instr),

        .data_addr (data_addr),
        .data_we   (data_we),
        .data_wdata(data_wdata),
        .data_rdata(data_rdata),

        .halted    (halted)
    );

endmodule
