module dual_port_ram #(
    parameter integer DEPTH = 256
) (
    input  logic        clk,

    // Port A: instruction fetch (combinational read)
    input  logic [31:0] a_addr,
    output logic [31:0] a_rdata,

    // Port B: data access (combinational read, synchronous write)
    input  logic [31:0] b_addr,
    input  logic        b_we,
    input  logic [31:0] b_wdata,
    output logic [31:0] b_rdata
);

    logic [31:0] mem [0:DEPTH-1];

    wire [$clog2(DEPTH)-1:0] a_index = a_addr[2 +: $clog2(DEPTH)];
    wire [$clog2(DEPTH)-1:0] b_index = b_addr[2 +: $clog2(DEPTH)];

    assign a_rdata = mem[a_index];
    assign b_rdata = mem[b_index];

    always_ff @(posedge clk) begin
        if (b_we)
            mem[b_index] <= b_wdata;
    end

    // Zero memory at time 0 for deterministic simulation.
    // Replace with $readmemh(...) if you want to load a program image.
    integer i;
    initial begin
        for (i = 0; i < DEPTH; i = i + 1)
            mem[i] = 32'd0;
    end

endmodule
