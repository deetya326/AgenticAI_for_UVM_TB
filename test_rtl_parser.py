import unittest
from rtl_parser import parse_rtl

class ParserTests(unittest.TestCase):
    def test_ansi_and_shorthand_ports(self):
        rtl='''module dut #(parameter W=8) (input logic clk, rst_n, input logic [W-1:0] a, b, output logic [W:0] sum); endmodule'''
        x=parse_rtl(rtl)
        self.assertEqual(x.name,'dut')
        self.assertEqual([(p.name,p.direction,p.width) for p in x.ports], [
            ('clk','input','1'),('rst_n','input','1'),('a','input','8'),('b','input','8'),('sum','output','9')])
    def test_comments_not_ports(self):
        rtl='''// module fake(input bad);\nmodule real(input wire x, /* output fake */ output reg [3:0] y); // input nope\nassign y=0; endmodule'''
        x=parse_rtl(rtl)
        self.assertEqual(x.name,'real')
        self.assertEqual([p.name for p in x.ports],['x','y'])
        self.assertEqual([p.width for p in x.ports],['1','4'])
    def test_top_selection(self):
        rtl='module a(input x); endmodule module b(input [7:0] y); endmodule'
        self.assertEqual(parse_rtl(rtl,top='b').ports[0].name,'y')
    def test_unresolved_width_reported(self):
        x=parse_rtl('module d(input [N-1:0] data); endmodule')
        self.assertFalse(x.ports[0].width_is_resolved)
        self.assertTrue(any('Unresolved port widths' in a for a in x.ambiguities))
    def test_non_ansi(self):
        rtl='module d(a, q); input [7:0] a; output q; endmodule'
        x=parse_rtl(rtl)
        self.assertEqual([(p.name,p.direction,p.width) for p in x.ports],[('a','input','8'),('q','output','1')])

if __name__=='__main__': unittest.main()
