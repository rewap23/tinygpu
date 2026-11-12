// tb_regfile.v -- directed tests for the register file.
// Shows the core timing rule: a write is invisible until AFTER the clock edge.
`timescale 1ns/1ps
module tb_regfile;
    reg        clk = 0, rst = 1;
    reg  [3:0] ra = 0, rb = 0, wa = 0;
    reg        we = 0;
    reg  [7:0] wd = 0;
    wire [7:0] da, db;
    integer errors = 0;

    always #5 clk = ~clk;   // 10 ns period = 100 MHz

    regfile #(.WIDTH(8)) dut (
        .clk(clk), .rst(rst), .ra(ra), .rb(rb), .da(da), .db(db),
        .we(we), .wa(wa), .wd(wd),
        .block_idx(8'd3), .block_dim(8'd4), .thread_idx(8'd2)
    );

    task check(input [7:0] got, input [7:0] want, input [8*40-1:0] what);
        if (got !== want) begin
            $display("FAIL %0s: got %0d want %0d", what, got, want);
            errors = errors + 1;
        end
    endtask

    integer i;
    initial begin
        $dumpfile("tb_regfile.vcd"); $dumpvars(0, tb_regfile);
        @(negedge clk); rst = 0;

        // write r5 = 42. Before the edge, r5 still reads 0.
        ra = 5; we = 1; wa = 5; wd = 42; #1;
        check(da, 0, "r5 before clock edge");
        @(posedge clk); #1;
        check(da, 42, "r5 after clock edge");
        we = 0;

        // fill r0..r12, read back on both ports
        for (i = 0; i < 13; i = i + 1) begin
            @(negedge clk); we = 1; wa = i; wd = 8'd100 + i;
        end
        @(negedge clk); we = 0;
        for (i = 0; i < 13; i = i + 1) begin
            ra = i; rb = 12 - i; #1;
            check(da, 100 + i,      "port A");
            check(db, 100 + 12 - i, "port B");
        end

        // special registers are wires, and are not writable
        @(negedge clk); we = 1; wa = 15; wd = 99;
        @(negedge clk); we = 0;
        ra = 13; rb = 14; #1; check(da, 3, "blockIdx"); check(db, 4, "blockDim");
        ra = 15; #1;          check(da, 2, "threadIdx (write ignored)");

        if (errors == 0) $display("PASS tb_regfile");
        else             $display("FAIL tb_regfile: %0d errors", errors);
        $finish;
    end
endmodule
