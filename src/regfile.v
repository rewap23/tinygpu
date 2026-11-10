// ============================================================================
// regfile.v -- ONE thread's private registers
// ============================================================================
// HARDWARE: 13 registers x 8 bits = 104 D flip-flops, plus:
//   * a 16:1 read multiplexer for port A and another for port B (combinational)
//   * a 4->13 decoder that turns `wa` into a per-register write enable
// 
// OVERVIEW:
//  * Two read ports: read ra and rb at the same time; the outputs are da and db.
//  * One write port: when enabled, write wd to register wa on a rising clock edge.
//
// Reads are combinational (the value appears right away).
// Writes are synchronous: they only take effect on the rising clock edge.
// That split is what makes a CPU/GPU step cleanly: during a cycle you read
// old values, compute, and the result lands in a flip-flop at the edge.
//
// r13..r15 are not flip-flops at all -- they're wires from the core.
// That's  what threadIdx.x is in hardware: a hard-wired constant
// per lane, plus a counter (blockIdx) the scheduler bumps.

`timescale 1ns/1ps
module regfile #(
    parameter WIDTH = 8
) (
    input  wire             clk,
    input  wire             rst,
    // two read ports (instructions read rs and rt at the same time)
    input  wire [3:0]       ra,
    input  wire [3:0]       rb,
    output wire [WIDTH-1:0] da,
    output wire [WIDTH-1:0] db,
    // one write port
    input  wire             we,
    input  wire [3:0]       wa,
    input  wire [WIDTH-1:0] wd,
    // special registers, driven by the core
    input  wire [WIDTH-1:0] block_idx,
    input  wire [WIDTH-1:0] block_dim,
    input  wire [WIDTH-1:0] thread_idx
);
    `include "isa.vh"

    reg [WIDTH-1:0] regs [0:12];   // the actual flip-flops
    // register is storing r0-r12 in regs[0:12]

    // --- write port: sequential logic (flip-flops) -------------------------
    // always @(posedge clk) + non-blocking `<=`  ==>  D flip-flops.
    integer i;
    always @(posedge clk) begin
        if (rst) begin
            for (i = 0; i < 13; i = i + 1)
                regs[i] <= {WIDTH{1'b0}};
        end else begin
            if (we && wa < 4'd13)
                regs[wa] <= wd;
            // To write a register, 3 things must be true:
            // 1. we (write enable) is 1
            // 2. wa (the destination register number) is less than 13
        end
    end

    // --- read ports: combinational muxes -----------------------------------
    // HARDWARE: each `? :` chain is a mux. regs[ra] itself is a 13:1 mux
    // selected by ra; the three compares put the special registers in front.
    // (Gotcha: don't hide this in a `function` called from `assign` -- many
    // simulators then only re-evaluate when `ra` changes, not when `regs`
    // changes, and your sim disagrees with the real hardware.)
    assign da = (ra == REG_BLOCK_IDX)  ? block_idx  :
                (ra == REG_BLOCK_DIM)  ? block_dim  :
                (ra == REG_THREAD_IDX) ? thread_idx : regs[ra];

    // TODO 2b: port B is identical to port A above, but driven by `rb`.
    assign db = (rb == REG_BLOCK_IDX)  ? block_idx  :
                (rb == REG_BLOCK_DIM)  ? block_dim  :
                (rb == REG_THREAD_IDX) ? thread_idx : regs[rb];
endmodule
