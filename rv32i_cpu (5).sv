module rv32i_cpu #(
    parameter integer MEM_DEPTH = 256
) (
    input  logic        clk,
    input  logic        rst_n,

    output logic [31:0] pc,
    input  logic [31:0] instr,

    // Data-memory interface to dual-port RAM
    output logic [31:0] data_addr,
    output logic        data_we,
    output logic [31:0] data_wdata,
    input  logic [31:0] data_rdata,

    output logic        halted
);

    // ----------------------------------------------------------------
    // CPU state
    // ----------------------------------------------------------------
    typedef enum logic [1:0] {
        ST_RESET = 2'd0,
        ST_RUN   = 2'd1,
        ST_HALT  = 2'd2
    } state_t;

    state_t state, next_state;

    // ----------------------------------------------------------------
    // Instruction fields
    // ----------------------------------------------------------------
    logic [6:0] opcode;
    logic [4:0] rd, rs1, rs2;
    logic [2:0] funct3;
    logic [6:0] funct7;

    assign opcode = instr[6:0];
    assign rd     = instr[11:7];
    assign funct3 = instr[14:12];
    assign rs1    = instr[19:15];
    assign rs2    = instr[24:20];
    assign funct7 = instr[31:25];

    // ----------------------------------------------------------------
    // Immediate generation
    // ----------------------------------------------------------------
    logic [31:0] imm_i;
    logic [31:0] imm_s;
    logic [31:0] imm_b;
    logic [31:0] imm_u;
    logic [31:0] imm_j;

    always_comb begin
        imm_i = {{20{instr[31]}}, instr[31:20]};

        imm_s = {{20{instr[31]}},
                 instr[31:25],
                 instr[11:7]};

        imm_b = {{19{instr[31]}},
                 instr[31],
                 instr[7],
                 instr[30:25],
                 instr[11:8],
                 1'b0};

        imm_u = {instr[31:12], 12'b0};

        imm_j = {{11{instr[31]}},
                 instr[31],
                 instr[19:12],
                 instr[20],
                 instr[30:21],
                 1'b0};
    end

    // ----------------------------------------------------------------
    // Register file
    // ----------------------------------------------------------------
    logic [31:0] rs1_data;
    logic [31:0] rs2_data;
    logic        reg_write;
    logic [31:0] reg_wdata;

    register_file rf (
        .clk       (clk),
        .rst_n     (rst_n),
        .rs1       (rs1),
        .rs2       (rs2),
        .rd        (rd),
        .rd_we     (reg_write),
        .rd_wdata  (reg_wdata),
        .rs1_rdata (rs1_data),
        .rs2_rdata (rs2_data)
    );

    // ----------------------------------------------------------------
    // Control unit
    // ----------------------------------------------------------------
    logic        mem_write;
    logic        mem_read;
    logic        alu_src_imm;
    logic        branch;
    logic        branch_ne;
    logic        jump;
    logic        jalr;
    logic        wb_mem;
    logic        wb_pc4;
    logic        wb_imm;
    logic [3:0]  alu_op;
    logic        halt_cmd;
    logic [2:0]  load_funct3;
    logic [2:0]  store_funct3;

    control_unit cu (
        .instr        (instr),
        .state        (state),
        .reg_write    (reg_write),
        .mem_write    (mem_write),
        .mem_read     (mem_read),
        .alu_src_imm  (alu_src_imm),
        .branch       (branch),
        .branch_ne    (branch_ne),
        .jump         (jump),
        .jalr         (jalr),
        .wb_mem       (wb_mem),
        .wb_pc4       (wb_pc4),
        .wb_imm       (wb_imm),
        .alu_op       (alu_op),
        .halt         (halt_cmd),
        .load_funct3  (load_funct3),
        .store_funct3 (store_funct3)
    );

    // ----------------------------------------------------------------
    // ALU
    // ----------------------------------------------------------------
    logic [31:0] alu_a;
    logic [31:0] alu_b;
    logic [31:0] alu_y;
    logic        alu_zero;

    assign alu_a = (opcode == 7'b0010111) ? pc : rs1_data;
    assign alu_b = alu_src_imm ? imm_i : rs2_data;

    alu alu_inst (
        .a            (alu_a),
        .b            (alu_b),
        .alu_op       (alu_op),
        .y            (alu_y),
        .zero         (alu_zero),
        .lt_signed    (),
        .lt_unsigned  ()
    );

    // ----------------------------------------------------------------
    // Memory interface
    // ----------------------------------------------------------------
    // For this single-cycle core, memory reads are combinational.
    // Stores commit on the rising clock edge in dual_port_ram.
    assign data_addr  = alu_y;
    assign data_we    = mem_write;
    assign data_wdata = rs2_data;

    // ----------------------------------------------------------------
    // Load data formatting
    // ----------------------------------------------------------------
    logic [31:0] load_data;

    always_comb begin
        unique case (load_funct3)
            3'b000: load_data = {{24{data_rdata[7]}},  data_rdata[7:0]};   // LB
            3'b001: load_data = {{16{data_rdata[15]}}, data_rdata[15:0]};  // LH
            3'b010: load_data = data_rdata;                                // LW
            3'b100: load_data = {24'd0, data_rdata[7:0]};                  // LBU
            3'b101: load_data = {16'd0, data_rdata[15:0]};                 // LHU
            default: load_data = data_rdata;
        endcase
    end

    // ----------------------------------------------------------------
    // Writeback mux
    // ----------------------------------------------------------------
    always_comb begin
        if (wb_mem)
            reg_wdata = load_data;
        else if (wb_pc4)
            reg_wdata = pc + 32'd4;
        else if (wb_imm && opcode == 7'b0110111) // LUI
            reg_wdata = imm_u;
        else
            reg_wdata = alu_y;
    end

    // AUIPC requires PC + U-immediate.
    always_comb begin
        if (opcode == 7'b0010111)
            reg_wdata = pc + imm_u;
        else if (wb_mem)
            reg_wdata = load_data;
        else if (wb_pc4)
            reg_wdata = pc + 32'd4;
        else if (wb_imm && opcode == 7'b0110111)
            reg_wdata = imm_u;
        else
            reg_wdata = alu_y;
    end

    // ----------------------------------------------------------------
    // Next-PC logic
    // ----------------------------------------------------------------
    logic [31:0] next_pc;
    logic        branch_taken;

    always_comb begin
        branch_taken = 1'b0;

        if (branch) begin
            if (!branch_ne)
                branch_taken = (rs1_data == rs2_data); // BEQ
            else
                branch_taken = (rs1_data != rs2_data); // BNE
        end

        next_pc = pc + 32'd4;

        if (branch && branch_taken)
            next_pc = pc + imm_b;
        else if (jump && !jalr)
            next_pc = pc + imm_j;
        else if (jump && jalr)
            next_pc = (rs1_data + imm_i) & 32'hFFFFFFFE;
    end

    // ----------------------------------------------------------------
    // Simple FSM
    //
    // The datapath is single-cycle: every instruction executes while
    // the FSM is in ST_RUN and commits state at the next rising edge.
    // ST_RESET and ST_HALT provide explicit control states.
    // ----------------------------------------------------------------
    always_comb begin
        next_state = state;

        unique case (state)
            ST_RESET: next_state = ST_RUN;
            ST_RUN:   if (halt_cmd) next_state = ST_HALT;
            ST_HALT:  next_state = ST_HALT;
            default:  next_state = ST_RESET;
        endcase
    end

    // ----------------------------------------------------------------
    // Sequential state / PC
    // ----------------------------------------------------------------
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            state <= ST_RESET;
            pc    <= 32'd0;
        end
        else begin
            state <= next_state;

            if (state == ST_RESET)
                pc <= 32'd0;
            else if (state == ST_RUN && !halt_cmd)
                pc <= next_pc;
        end
    end

    assign halted = (state == ST_HALT);

endmodule
