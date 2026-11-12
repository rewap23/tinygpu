// tb_core.v -- the "host driver": plays the role of the CPU + CUDA runtime.
//
//   1. load the kernel into instruction memory        (module load)
//   2. copy A and B into data memory                  (cudaMemcpy H->D)
//   3. set num_threads, pulse start                   (kernel<<<...>>>)
//   4. wait for done                                  (cudaDeviceSynchronize)
//   5. read C back and check it                       (cudaMemcpy D->H)
//
// Run with +N=<threads> to change the problem size (default 8, max 8).
// Run with +KERNEL=vecadd|vecmul|vecsub to choose the assembled program.
// Try +N=7 to watch lane 3 get masked off in the second block.
// Example: make core N=7 or make core KERNEL=vecsub

`timescale 1ns/1ps
module tb_core;
    `include "isa.vh"

    localparam A_BASE = 0, B_BASE = 8, C_BASE = 16;

    reg         clk = 0, rst = 1;
    reg         host_we = 0, host_sel = 0;
    reg  [7:0]  host_addr = 0;
    reg  [15:0] host_wdata = 0;
    wire [7:0]  host_rdata;
    reg  [7:0]  num_threads;
    reg         start = 0;
    wire        done;

    always #5 clk = ~clk;

    core #(.WIDTH(8), .LANES(4)) dut (
        .clk(clk), .rst(rst),
        .host_we(host_we), .host_sel(host_sel), .host_addr(host_addr),
        .host_wdata(host_wdata), .host_rdata(host_rdata),
        .num_threads(num_threads), .start(start), .done(done)
    );

    // ---- host bus helpers ------------------------------------------------
    task host_write(input sel, input [7:0] addr, input [15:0] data);
        begin
            @(negedge clk);
            host_we = 1; host_sel = sel; host_addr = addr; host_wdata = data;
            @(negedge clk);
            host_we = 0;
        end
    endtask

    task host_read(input [7:0] addr, output [7:0] data);
        begin
            @(negedge clk); host_addr = addr; #1; data = host_rdata;
        end
    endtask

    // ---- instruction trace: print what every lane does each EXEC cycle ----
    reg [8*5-1:0] mnem;
    always @(*) case (dut.op)
        OP_NOP: mnem = "NOP";   OP_ADD: mnem = "ADD";   OP_SUB: mnem = "SUB";
        OP_MUL: mnem = "MUL";   OP_CONST: mnem = "CONST"; OP_LDR: mnem = "LDR";
        OP_STR: mnem = "STR";   OP_RET: mnem = "RET";   default: mnem = "???";
    endcase

    integer cycles = 0;
    always @(posedge clk) begin
        if (!rst) cycles <= cycles + 1;
        if (dut.exec)
            $display("t=%5t blk=%0d pc=%2d %-5s rd=r%-2d rs=r%-2d rt=r%-2d | mask=%b%b%b%b | rs val: %3d %3d %3d %3d",
                $time, dut.block_idx, dut.pc, mnem, dut.rd, dut.rs, dut.rt,
                dut.g_lane[3].active, dut.g_lane[2].active,
                dut.g_lane[1].active, dut.g_lane[0].active,
                dut.g_lane[0].u_lane.mem_addr, dut.g_lane[1].u_lane.mem_addr,
                dut.g_lane[2].u_lane.mem_addr, dut.g_lane[3].u_lane.mem_addr);
    end

    // ---- the test ---------------------------------------------------------
    reg [15:0] prog [0:31];
    reg [7:0]  A [0:7], B [0:7], got;
    reg [7:0]  expected;
    reg [8*8-1:0] kernel;
    integer i, n, plen, errors, timeout;

    initial begin
        $dumpfile("tb_core.vcd"); $dumpvars(0, tb_core);
        if (!$value$plusargs("N=%d", n)) n = 8;
        if (!$value$plusargs("KERNEL=%s", kernel)) kernel = "vecadd";
        errors = 0;

        // assembled kernel (produced by sw/asm.py)
        for (i = 0; i < 32; i = i + 1) prog[i] = 16'hxxxx;
        case (kernel)
            "vecadd": $readmemh("vecadd.hex", prog);
            "vecmul": $readmemh("vecmul.hex", prog);
            "vecsub": $readmemh("vecsub.hex", prog);
            default: begin
                $display("FAIL: unknown kernel %0s", kernel);
                $finish;
            end
        endcase
        plen = 0;
        while (plen < 32 && prog[plen] !== 16'hxxxx) plen = plen + 1;

        repeat (2) @(negedge clk);
        rst = 0;

        // 1. load kernel
        for (i = 0; i < plen; i = i + 1) host_write(0, i, prog[i]);
        $display("host: loaded %0d instructions", plen);

        // 2. copy inputs; pre-fill C with 0xEE so masked writes are visible
        for (i = 0; i < 8; i = i + 1) begin
            A[i] = 10 * (i + 1);        // 10 20 30 ...
            B[i] = i + 1;               //  1  2  3 ...
            host_write(1, A_BASE + i, A[i]);
            host_write(1, B_BASE + i, B[i]);
            host_write(1, C_BASE + i, 8'hEE);
        end

        // 3. launch
        num_threads = n;
        $display("host: launching %0s with %0d threads (%0d blocks of 4)",
                 kernel, n, (n + 3) / 4);
        @(negedge clk); start = 1; i = cycles;
        @(negedge clk); start = 0;

        // 4. wait
        timeout = 0;
        while (!done && timeout < 1000) begin
            @(posedge clk); timeout = timeout + 1;
        end
        if (!done) begin $display("FAIL: timeout"); $finish; end
        $display("host: kernel finished in %0d cycles", cycles - i);

        // 5. read back
        for (i = 0; i < 8; i = i + 1) begin
            host_read(C_BASE + i, got);
            if (i < n) begin
                case (kernel)
                    "vecadd": expected = A[i] + B[i];
                    "vecmul": expected = A[i] * B[i];
                    "vecsub": expected = A[i] - B[i];
                endcase
                if (got !== expected) begin
                    $display("FAIL C[%0d] = %0d, want %0d", i, got, expected);
                    errors = errors + 1;
                end else
                // display either addition, subtraction, multiplication
                    $display("  C[%0d] = %3d  (A=%0d, B=%0d)", i, got, A[i], B[i]);
            end else begin
                if (got !== 8'hEE) begin
                    $display("FAIL C[%0d] written by a masked lane!", i);
                    errors = errors + 1;
                end else
                    $display("  C[%0d] = 0x%h (untouched: lane was masked)", i, got);
            end
        end

        if (errors == 0) $display("PASS tb_core (N=%0d)", n);
        else             $display("FAIL tb_core: %0d errors", errors);
        $finish;
    end
endmodule
