module register_file (
    input  logic        clk,
    input  logic        rst_n,

    input  logic [4:0]  rs1,
    input  logic [4:0]  rs2,
    input  logic [4:0]  rd,

    input  logic        rd_we,
    input  logic [31:0] rd_wdata,

    output logic [31:0] rs1_rdata,
    output logic [31:0] rs2_rdata
);

    logic [31:0] regs [0:31];
    integer i;

    // Combinational reads. x0 is hard-wired to zero.
    always_comb begin
        rs1_rdata = (rs1 == 5'd0) ? 32'd0 : regs[rs1];
        rs2_rdata = (rs2 == 5'd0) ? 32'd0 : regs[rs2];
    end

    // Synchronous write. x0 can never be written.
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            for (i = 0; i < 32; i = i + 1)
                regs[i] <= 32'd0;
        end
        else if (rd_we && (rd != 5'd0)) begin
            regs[rd] <= rd_wdata;
        end
    end

endmodule
