// tb_scheduler.v -- tests the scheduler ON ITS OWN, with no lanes attached.
//
// We give it a fake 3-instruction program (ADD, ADD, RET) and 6 threads
// (= 2 blocks of 4) and print what it does every clock tick. You should see:
//   FETCH/EXEC alternate, pc go 0,1,2, block_idx go 0 -> 1 on RET,
//   then done = 1 after 3 instructions x 2 cycles x 2 blocks = 12 cycles.
`timescale 1ns/1ps
module tb_scheduler;
    `include "isa.vh"

    reg         clk = 0, rst = 1, start = 0;
    reg  [7:0]  num_threads = 8'd6;
    wire [7:0]  pc, block_idx;
    wire [15:0] ir;
    wire        exec, idle, done;

    // a tiny fake instruction memory (just a lookup on pc)
    reg  [15:0] instr;
    always @(*) case (pc)
        8'd0:    instr = {OP_ADD, 12'h000};
        8'd1:    instr = {OP_ADD, 12'h000};
        8'd2:    instr = {OP_RET, 12'h000};
        default: instr = {OP_NOP, 12'h000};
    endcase

    // the decoder's only job here is to pull op out of ir
    wire [3:0] op = ir[15:12];

    scheduler #(.WIDTH(8), .LANES(4)) dut (
        .clk(clk), .rst(rst), .start(start), .num_threads(num_threads),
        .instr(instr), .op(op),
        .pc(pc), .ir(ir), .block_idx(block_idx),
        .exec(exec), .idle(idle), .done(done)
    );

    always #5 clk = ~clk;

    // print the state after every rising edge
    reg [8*5-1:0] sname;
    always @(*) case (dut.state)
        2'd0: sname = "IDLE"; 2'd1: sname = "FETCH"; 2'd2: sname = "EXEC";
        default: sname = "???";
    endcase

    integer cycles = 0, errors = 0;
    always @(posedge clk) if (!rst) begin
        #1;
        cycles = cycles + 1;
        $display("tick %2d: state=%-5s pc=%0d block_idx=%0d ir.op=%0d done=%b",
                 cycles, sname, pc, block_idx, op, done);
    end

    initial begin
        $dumpfile("tb_scheduler.vcd"); $dumpvars(0, tb_scheduler);
        @(negedge clk); rst = 0;
        if (!idle) begin $display("FAIL not idle after reset"); errors = errors + 1; end
        start = 1; @(negedge clk); start = 0;
        cycles = 1;   // count the tick that saw `start`
        while (!done && cycles < 50) @(negedge clk);
        if (!done) begin
            $display("FAIL tb_scheduler: done never went high (stuck?)");
            $finish;
        end
        if (cycles != 13) begin   // 1 start tick + 12
            $display("FAIL expected 13 ticks incl. start, got %0d", cycles);
            errors = errors + 1;
        end
        if (block_idx != 1) begin
            $display("FAIL expected last block_idx = 1, got %0d", block_idx);
            errors = errors + 1;
        end
        if (!idle) begin $display("FAIL not idle at end"); errors = errors + 1; end

        if (errors == 0) $display("PASS tb_scheduler");
        else             $display("FAIL tb_scheduler: %0d errors", errors);
        $finish;
    end
endmodule
