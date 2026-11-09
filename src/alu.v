// ============================================================================
// alu.v -- the arithmetic unit inside ONE lane (one "CUDA core")
// ============================================================================
// HARDWARE: this is pure combinational logic -- no clock, no memory.
// Think of it as a box of gates where the output settles a few
// nanoseconds after the inputs change.
//
// The synthesizer turns this into:
//   * an 8-bit ripple/carry adder         (for ADD)
//   * an 8-bit subtractor (adder + invert) (for SUB)  -- often shares the adder
//   * an 8x8 multiplier array              (for MUL)  -- by far the biggest part
//   * a 4:1 multiplexer on the output, steered by `op`
// All three units compute EVERY cycle; the mux just picks which answer
// leaves the box. That is the key mental shift from software: hardware
// doesn't "run the ADD branch" -- every branch exists physically at once.

`timescale 1ns/1ps
module alu #(
    parameter WIDTH = 8
) (
    input  wire [3:0]       op,   // which operation (from the shared decoder)
    input  wire [WIDTH-1:0] a,    // value of register rs
    input  wire [WIDTH-1:0] b,    // value of register rt
    output reg  [WIDTH-1:0] y     // result
);
    `include "isa.vh"

    // always @(*) = "re-evaluate whenever any input changes" = combinational.
    // `y` is declared `reg` only because it's assigned in an always block;
    // it does NOT become a flip-flop. (No clock edge => no flip-flop.)
    always @(*) begin
        case (op)
            // TODO 1a: add three case items: OP_ADD, OP_SUB, OP_MUL.
            //   Each is one line, e.g.   OP_ADD: y = ... ;
            //   Test: make alu SRC=starter
            default: y = {WIDTH{1'b0}};  // a default prevents an inferred latch
        endcase
    end
endmodule
