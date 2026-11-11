// Candidate assertions for the included rv32i_cpu RTL.
// Status: generated/reviewed against source; not compiled or simulated.
// Assertions target the actual internal names in rv32i_cpu.sv.

module rv32i_cpu_assertions (
    input logic        clk,
    input logic        rst_n,
    input logic [31:0] pc,
    input logic [31:0] instr,
    input logic [31:0] data_addr,
    input logic        data_we,
    input logic [31:0] data_wdata,
    input logic [31:0] data_rdata,
    input logic        halted,

    input logic [1:0]  state,
    input logic [31:0] next_pc,
    input logic        halt_cmd,
    input logic        mem_write,
    input logic        reg_write,
    input logic [4:0]  rs1,
    input logic [31:0] rs1_data
);

    localparam logic [1:0] ST_RESET = 2'd0;
    localparam logic [1:0] ST_RUN   = 2'd1;
    localparam logic [1:0] ST_HALT  = 2'd2;

    default clocking cb @(posedge clk); endclocking

    // [RTL-DERIVED] Synchronous active-low reset sets state and PC to zero.
    ap_reset_state_pc: assert property (
        !rst_n |=> (state == ST_RESET && pc == 32'd0)
    );

    // [RTL-DERIVED] One cycle after reset is released, reset state advances to RUN.
    ap_reset_to_run: assert property (
        rst_n && state == ST_RESET |=> state == ST_RUN
    );

    // [RTL-DERIVED] The public halted output reflects the internal state.
    ap_halted_matches_state: assert property (
        disable iff (!rst_n) halted == (state == ST_HALT)
    );

    // [SPEC/RTL-DERIVED] HALT is sticky and does not advance the PC.
    ap_halt_sticky: assert property (
        rst_n && state == ST_HALT |=> state == ST_HALT && $stable(pc)
    );

    // [RTL-DERIVED] A running non-halt instruction commits next_pc at the next edge.
    ap_running_pc_update: assert property (
        rst_n && state == ST_RUN && !halt_cmd |=> pc == $past(next_pc)
    );

    // [RTL-DERIVED] A halt command in RUN enters HALT and leaves PC unchanged.
    ap_halt_command: assert property (
        rst_n && state == ST_RUN && halt_cmd |=> state == ST_HALT && $stable(pc)
    );

    // [RTL-DERIVED] The CPU's externally visible data write enable is mem_write.
    ap_data_write_enable_matches_control: assert property (
        data_we == mem_write
    );

    // [RTL-DERIVED] Writes and register writes are disabled outside RUN.
    ap_no_side_effects_outside_run: assert property (
        rst_n && state != ST_RUN |-> !data_we && !reg_write
    );

    // [RTL-DERIVED] Register-file reads of x0 return zero.
    ap_x0_read_is_zero: assert property (
        rst_n && rs1 == 5'd0 |-> rs1_data == 32'd0
    );

    // [ENVIRONMENT-ASSUMPTION] The instruction/data-memory model returns known
    // values while active. Keep this property only when the testbench guarantees it.
    ap_outputs_known_in_run: assert property (
        rst_n && state == ST_RUN |-> !$isunknown({pc, instr, data_addr,
                                                  data_we, data_wdata,
                                                  data_rdata, halted})
    );

endmodule

// Bind to the actual DUT. Internal signal names were checked in rv32i_cpu.sv.
bind rv32i_cpu rv32i_cpu_assertions rv32i_cpu_assertions_i (
    .clk       (clk),
    .rst_n     (rst_n),
    .pc        (pc),
    .instr     (instr),
    .data_addr (data_addr),
    .data_we   (data_we),
    .data_wdata(data_wdata),
    .data_rdata(data_rdata),
    .halted    (halted),
    .state     (state),
    .next_pc   (next_pc),
    .halt_cmd  (halt_cmd),
    .mem_write (mem_write),
    .reg_write (reg_write),
    .rs1       (rs1),
    .rs1_data  (rs1_data)
);
