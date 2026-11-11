import unittest
from pathlib import Path
from rtl_parser import parse_rtl

ROOT = Path(__file__).resolve().parents[1]
EX = ROOT / 'examples' / 'alu'

class ALUExampleStaticTests(unittest.TestCase):
    def test_interface_has_all_real_dut_signals(self):
        iface = parse_rtl((ROOT/'fixed_rtl'/'alu.sv').read_text(), top='alu')
        iftext=(EX/'alu_if.sv').read_text()
        tbtext=(EX/'tb_alu_uvm.sv').read_text()
        for p in iface.ports:
            self.assertIn(p.name, iftext)
            self.assertIn(f'.{p.name}(', tbtext)
        self.assertIn('logic [31:0] a, b;', iftext)
        self.assertIn('logic [3:0] alu_op;', iftext)
        self.assertIn('logic [31:0] y;', iftext)

    def test_sva_mentions_each_operation_code(self):
        sva=(EX/'alu_assertions.sv').read_text()
        for op in range(10): self.assertIn(f"4'd{op}", sva)
        self.assertIn('ap_zero', sva)
        self.assertIn('ap_lts', sva)
        self.assertIn('ap_ltu', sva)

    def test_coverage_has_operation_bins_and_cross(self):
        uvm=(EX/'alu_uvm_pkg.sv').read_text()
        self.assertIn('covergroup alu_cg', uvm)
        self.assertIn('default_ops', uvm)
        self.assertIn('operation_x_zero', uvm)

if __name__ == '__main__': unittest.main()
