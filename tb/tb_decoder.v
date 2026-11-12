// tb_decoder.v -- feeds all 65,536 possible instructions into the decoder
// and checks every field. Also prints the vecadd instructions decoded.
`timescale 1ns/1ps
module tb_decoder;
    reg  [15:0] ir;
    wire [3:0]  op, rd, rs, rt;
    wire [7:0]  imm;
    integer i, errors;

    decoder dut (.ir(ir), .op(op), .rd(rd), .rs(rs), .rt(rt), .imm(imm));

    initial begin
        errors = 0;
        for (i = 0; i < 65536; i = i + 1) begin
            ir = i; #1;
            if (op !== i[15:12] || rd !== i[11:8] || rs !== i[7:4] ||
                rt !== i[3:0]   || imm !== i[7:0]) begin
                if (errors < 10)
                    $display("FAIL ir=%h -> op=%h rd=%h rs=%h rt=%h imm=%h",
                             ir, op, rd, rs, rt, imm);
                errors = errors + 1;
            end
        end

        // a few real instructions, so you can see the split
        ir = 16'h1645; #1;
        $display("ir=%b -> op=%0d rd=r%0d rs=r%0d rt=r%0d  (ADD r6, r4, r5)", ir, op, rd, rs, rt);
        ir = 16'h4310; #1;
        $display("ir=%b -> op=%0d rd=r%0d imm=%0d      (CONST r3, 16)", ir, op, rd, imm);
        ir = 16'h5440; #1;
        $display("ir=%b -> op=%0d rd=r%0d rs=r%0d      (LDR r4, r4)", ir, op, rd, rs);

        if (errors == 0) $display("PASS tb_decoder: 65536 instructions");
        else             $display("FAIL tb_decoder: %0d errors", errors);
        $finish;
    end
endmodule
