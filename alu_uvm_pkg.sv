package alu_uvm_pkg;
    import uvm_pkg::*;
    `include "uvm_macros.svh"

    class alu_item extends uvm_sequence_item;
        rand bit [31:0] a, b;
        rand bit [3:0] alu_op;
        `uvm_object_utils_begin(alu_item)
            `uvm_field_int(a, UVM_ALL_ON)
            `uvm_field_int(b, UVM_ALL_ON)
            `uvm_field_int(alu_op, UVM_ALL_ON)
        `uvm_object_utils_end
        function new(string name="alu_item"); super.new(name); endfunction
    endclass

    class alu_sequencer extends uvm_sequencer #(alu_item);
        `uvm_component_utils(alu_sequencer)
        function new(string name, uvm_component parent); super.new(name,parent); endfunction
    endclass

    class alu_basic_sequence extends uvm_sequence #(alu_item);
        `uvm_object_utils(alu_basic_sequence)
        function new(string name="alu_basic_sequence"); super.new(name); endfunction
        task body();
            alu_item tr;
            // Exercise all defined operations and default encodings.
            for (int op=0; op<16; op++) begin
                tr=alu_item::type_id::create($sformatf("tr_%0d",op));
                start_item(tr);
                if (!tr.randomize(a, b))
                    `uvm_fatal("RAND", "Could not randomize ALU operands")
                tr.alu_op = op[3:0];
                finish_item(tr);
            end
        endtask
    endclass

    class alu_driver extends uvm_driver #(alu_item);
        `uvm_component_utils(alu_driver)
        virtual alu_if vif;
        function new(string name, uvm_component parent); super.new(name,parent); endfunction
        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            if (!uvm_config_db#(virtual alu_if)::get(this,"","vif",vif))
                `uvm_fatal("NOVIF", "alu_if not configured")
        endfunction
        task run_phase(uvm_phase phase);
            alu_item tr;
            forever begin
                seq_item_port.get_next_item(tr);
                @(vif.drv_cb);
                vif.drv_cb.a <= tr.a;
                vif.drv_cb.b <= tr.b;
                vif.drv_cb.alu_op <= tr.alu_op;
                seq_item_port.item_done();
            end
        endtask
    endclass

    class alu_monitor extends uvm_component;
        `uvm_component_utils(alu_monitor)
        virtual alu_if vif;
        uvm_analysis_port #(alu_item) ap;
        covergroup alu_cg with function sample(bit [3:0] op, bit z);
            cp_operation: coverpoint op {
                bins add={0}; bins sub={1}; bins bitwise={2,3,4};
                bins compare={5,6}; bins shifts={7,8,9}; bins default_ops={[10:15]};
            }
            cp_zero: coverpoint z { bins zero={1}; bins nonzero={0}; }
            operation_x_zero: cross cp_operation, cp_zero;
        endgroup
        function new(string name, uvm_component parent); super.new(name,parent); ap=new("ap",this); alu_cg=new(); endfunction
        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            if (!uvm_config_db#(virtual alu_if)::get(this,"","vif",vif))
                `uvm_fatal("NOVIF", "alu_if not configured")
        endfunction
        task run_phase(uvm_phase phase);
            alu_item tr;
            forever begin
                @(vif.mon_cb);
                tr=alu_item::type_id::create("observed");
                tr.a=vif.mon_cb.a; tr.b=vif.mon_cb.b; tr.alu_op=vif.mon_cb.alu_op;
                alu_cg.sample(vif.mon_cb.alu_op, vif.mon_cb.zero);
                ap.write(tr);
            end
        endtask
    endclass

    class alu_scoreboard extends uvm_subscriber #(alu_item);
        `uvm_component_utils(alu_scoreboard)
        virtual alu_if vif;
        int checked=0;
        function new(string name, uvm_component parent); super.new(name,parent); endfunction
        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            if (!uvm_config_db#(virtual alu_if)::get(this,"","vif",vif))
                `uvm_fatal("NOVIF", "alu_if not configured")
        endfunction
        function bit [31:0] model(bit [31:0] a,b, bit [3:0] op);
            case(op)
                0:model=a+b; 1:model=a-b; 2:model=a&b; 3:model=a|b; 4:model=a^b;
                5:model=($signed(a)<$signed(b))?32'd1:32'd0;
                6:model=(a<b)?32'd1:32'd0;
                7:model=a<<b[4:0]; 8:model=a>>b[4:0]; 9:model=$signed(a)>>>b[4:0];
                default:model=32'd0;
            endcase
        endfunction
        function void write(alu_item t);
            bit [31:0] expected;
            expected=model(t.a,t.b,t.alu_op);
            checked++;
            if (vif.y !== expected)
                `uvm_error("ALU_MISMATCH", $sformatf("op=%0d a=%h b=%h expected=%h actual=%h",t.alu_op,t.a,t.b,expected,vif.y))
            if (vif.zero !== (expected==0))
                `uvm_error("ZERO_MISMATCH", "zero flag inconsistent with expected result")
            if (vif.lt_signed !== ($signed(t.a)<$signed(t.b)))
                `uvm_error("LTS_MISMATCH", "signed comparison flag mismatch")
            if (vif.lt_unsigned !== (t.a<t.b))
                `uvm_error("LTU_MISMATCH", "unsigned comparison flag mismatch")
        endfunction
        function void report_phase(uvm_phase phase);
            `uvm_info("ALU_SB",$sformatf("Checked %0d samples",checked),UVM_LOW)
        endfunction
    endclass

    class alu_env extends uvm_env;
        `uvm_component_utils(alu_env)
        alu_sequencer seqr; alu_driver drv; alu_monitor mon; alu_scoreboard sb;
        function new(string name, uvm_component parent); super.new(name,parent); endfunction
        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            seqr=alu_sequencer::type_id::create("seqr",this);
            drv=alu_driver::type_id::create("drv",this);
            mon=alu_monitor::type_id::create("mon",this);
            sb=alu_scoreboard::type_id::create("sb",this);
        endfunction
        function void connect_phase(uvm_phase phase);
            super.connect_phase(phase);
            drv.seq_item_port.connect(seqr.seq_item_export);
            mon.ap.connect(sb.analysis_export);
        endfunction
    endclass

    class alu_test extends uvm_test;
        `uvm_component_utils(alu_test)
        alu_env env;
        function new(string name, uvm_component parent); super.new(name,parent); endfunction
        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            env=alu_env::type_id::create("env",this);
        endfunction
        task run_phase(uvm_phase phase);
            alu_basic_sequence seq;
            phase.raise_objection(this);
            seq=alu_basic_sequence::type_id::create("seq");
            seq.start(env.seqr);
            repeat(2) @(posedge env.drv.vif.clk);
            phase.drop_objection(this);
        endtask
    endclass
endpackage
