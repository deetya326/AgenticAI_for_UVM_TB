module control_unit (
    input  logic [31:0] instr,

    // Current CPU control state.
    input  logic [1:0] state,

    output logic        reg_write,
    output logic        mem_write,
    output logic        mem_read,
    output logic        alu_src_imm,
    output logic        branch,
    output logic        branch_ne,
    output logic        jump,
    output logic        jalr,
    output logic        wb_mem,
    output logic        wb_pc4,
    output logic        wb_imm,
    output logic [3:0]  alu_op,
    output logic        halt,
    output logic [2:0]  load_funct3,
    output logic [2:0]  store_funct3
);

    localparam ST_RESET = 2'd0;
    localparam ST_RUN   = 2'd1;
    localparam ST_HALT  = 2'd2;

    localparam OP_LUI    = 7'b0110111;
    localparam OP_AUIPC  = 7'b0010111;
    localparam OP_JAL    = 7'b1101111;
    localparam OP_JALR   = 7'b1100111;
    localparam OP_BRANCH = 7'b1100011;
    localparam OP_LOAD   = 7'b0000011;
    localparam OP_STORE  = 7'b0100011;
    localparam OP_OPIMM  = 7'b0010011;
    localparam OP_OP     = 7'b0110011;
    localparam OP_SYSTEM = 7'b1110011;

    localparam ALU_ADD  = 4'd0;
    localparam ALU_SUB  = 4'd1;
    localparam ALU_AND  = 4'd2;
    localparam ALU_OR   = 4'd3;
    localparam ALU_XOR  = 4'd4;
    localparam ALU_SLT  = 4'd5;
    localparam ALU_SLTU = 4'd6;
    localparam ALU_SLL  = 4'd7;
    localparam ALU_SRL  = 4'd8;
    localparam ALU_SRA  = 4'd9;

    logic [6:0] opcode;
    logic [2:0] funct3;
    logic [6:0] funct7;

    assign opcode = instr[6:0];
    assign funct3 = instr[14:12];
    assign funct7 = instr[31:25];

    always_comb begin
        reg_write    = 1'b0;
        mem_write    = 1'b0;
        mem_read     = 1'b0;
        alu_src_imm  = 1'b0;
        branch       = 1'b0;
        branch_ne    = 1'b0;
        jump         = 1'b0;
        jalr         = 1'b0;
        wb_mem       = 1'b0;
        wb_pc4       = 1'b0;
        wb_imm       = 1'b0;
        alu_op       = ALU_ADD;
        halt         = 1'b0;
        load_funct3  = funct3;
        store_funct3 = funct3;

        if (state == ST_RUN) begin
            unique case (opcode)

                // LUI
                OP_LUI: begin
                    reg_write   = 1'b1;
                    wb_imm      = 1'b1;
                end

                // AUIPC
                OP_AUIPC: begin
                    reg_write   = 1'b1;
                    alu_src_imm = 1'b1;
                    alu_op      = ALU_ADD;
                end

                // JAL
                OP_JAL: begin
                    reg_write = 1'b1;
                    wb_pc4    = 1'b1;
                    jump      = 1'b1;
                end

                // JALR
                OP_JALR: begin
                    if (funct3 == 3'b000) begin
                        reg_write   = 1'b1;
                        wb_pc4      = 1'b1;
                        jump        = 1'b1;
                        jalr        = 1'b1;
                        alu_src_imm = 1'b1;
                        alu_op      = ALU_ADD;
                    end
                end

                // Conditional branches
                OP_BRANCH: begin
                    branch = 1'b1;
                    unique case (funct3)
                        3'b000: branch_ne = 1'b0; // BEQ
                        3'b001: branch_ne = 1'b1; // BNE
                        default: branch = 1'b0;   // Other branch types not implemented
                    endcase
                    alu_op = ALU_SUB;
                end

                // Loads: LB/LH/LW/LBU/LHU
                OP_LOAD: begin
                    alu_src_imm = 1'b1;
                    alu_op      = ALU_ADD;
                    mem_read    = 1'b1;
                    wb_mem      = 1'b1;
                    reg_write   = 1'b1;
                end

                // Stores: SB/SH/SW
                OP_STORE: begin
                    alu_src_imm = 1'b1;
                    alu_op      = ALU_ADD;
                    mem_write   = 1'b1;
                end

                // Immediate ALU operations
                OP_OPIMM: begin
                    alu_src_imm = 1'b1;
                    reg_write   = 1'b1;

                    unique case (funct3)
                        3'b000: alu_op = ALU_ADD;  // ADDI
                        3'b010: alu_op = ALU_SLT;  // SLTI
                        3'b011: alu_op = ALU_SLTU; // SLTIU
                        3'b100: alu_op = ALU_XOR;  // XORI
                        3'b110: alu_op = ALU_OR;   // ORI
                        3'b111: alu_op = ALU_AND;  // ANDI
                        3'b001: alu_op = ALU_SLL;  // SLLI
                        3'b101: begin
                            if (funct7[5])
                                alu_op = ALU_SRA;  // SRAI
                            else
                                alu_op = ALU_SRL;  // SRLI
                        end
                        default: reg_write = 1'b0;
                    endcase
                end

                // Register-register ALU operations
                OP_OP: begin
                    reg_write = 1'b1;

                    unique case ({funct7, funct3})
                        {7'b0000000,3'b000}: alu_op = ALU_ADD;
                        {7'b0100000,3'b000}: alu_op = ALU_SUB;
                        {7'b0000000,3'b001}: alu_op = ALU_SLL;
                        {7'b0000000,3'b010}: alu_op = ALU_SLT;
                        {7'b0000000,3'b011}: alu_op = ALU_SLTU;
                        {7'b0000000,3'b100}: alu_op = ALU_XOR;
                        {7'b0000000,3'b101}: alu_op = ALU_SRL;
                        {7'b0100000,3'b101}: alu_op = ALU_SRA;
                        {7'b0000000,3'b110}: alu_op = ALU_OR;
                        {7'b0000000,3'b111}: alu_op = ALU_AND;
                        default: reg_write = 1'b0;
                    endcase
                end

                // EBREAK is used as the demo halt instruction.
                OP_SYSTEM: begin
                    if (funct3 == 3'b000 && instr[31:20] == 12'h001)
                        halt = 1'b1;
                end

                default: begin
                    // Illegal/unsupported opcode: no side effects.
                end
            endcase
        end
    end

endmodule
