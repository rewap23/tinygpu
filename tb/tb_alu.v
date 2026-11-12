// tb_alu.v -- testbench for ALU, checks the ALU: every op x every a x every b.
// A testbench is NOT hardware, it's a program that wiggles the inputs of
// the "device under test" (dut) and checks its outputs.
`timescale 1ns/1ps
module tb_alu;
    `include "isa.vh"
    reg  [3:0] op;
    reg  [7:0] a, b;
    wire [7:0] y;
    reg  [7:0] expect;
    integer ia, ib, io, errors;

    alu #(.WIDTH(8)) dut (.op(op), .a(a), .b(b), .y(y));

    initial begin
        errors = 0;
        for (io = 0; io < 4; io = io + 1) begin
            op = (io == 0) ? OP_ADD : (io == 1) ? OP_SUB :
                 (io == 2) ? OP_MUL : OP_NOP;
            for (ia = 0; ia < 256; ia = ia + 1)
                for (ib = 0; ib < 256; ib = ib + 1) begin
                    a = ia; b = ib;
                    #1;  // let the combinational logic "settle"
                    case (op)
                        OP_ADD:  expect = ia + ib;
                        OP_SUB:  expect = ia - ib;
                        OP_MUL:  expect = ia * ib;
                        default: expect = 0;
                    endcase
                    if (y !== expect) begin
                        if (errors < 10)
                            $display("FAIL op=%0d a=%0d b=%0d got=%0d want=%0d",
                                     op, a, b, y, expect);
                        errors = errors + 1;
                    end
                end
        end
        if (errors == 0) $display("PASS tb_alu: 262144 vectors");
        else             $display("FAIL tb_alu: %0d errors", errors);
        $finish;
    end
endmodule
