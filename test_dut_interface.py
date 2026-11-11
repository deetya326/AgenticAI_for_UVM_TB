import unittest
from pathlib import Path
from rtl_parser import parse_rtl

ROOT = Path(__file__).resolve().parents[1]

class ActualDUTInterfaceTests(unittest.TestCase):
    def test_alu_interface_exact_ports_and_widths(self):
        rtl = (ROOT / 'fixed_rtl' / 'alu.sv').read_text()
        iface = parse_rtl(rtl, top='alu')
        got = [(p.name, p.direction, p.width) for p in iface.ports]
        self.assertEqual(got, [
            ('a','input','32'), ('b','input','32'), ('alu_op','input','4'),
            ('y','output','32'), ('zero','output','1'),
            ('lt_signed','output','1'), ('lt_unsigned','output','1')])
        self.assertEqual(iface.ambiguities, [])

    def test_cpu_interface_actual_instr_is_input(self):
        rtl = (ROOT / 'fixed_rtl' / 'rv32i_cpu.sv').read_text()
        iface = parse_rtl(rtl, top='rv32i_cpu')
        ports = {p.name: (p.direction, p.width) for p in iface.ports}
        self.assertEqual(ports['instr'], ('input','32'))
        self.assertEqual(ports['pc'], ('output','32'))
        self.assertEqual(ports['data_we'], ('output','1'))
        self.assertEqual(iface.ambiguities, [])

if __name__ == '__main__': unittest.main()
