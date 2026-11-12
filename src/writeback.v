// ============================================================================
// writeback.v -- CHOOSER: chooses WHAT value gets written into register rd
// ============================================================================
// OVERVIEW
//   Different instructions put different things into the destination reg:
//      ADD / SUB / MUL -> the ALU's answer
//      CONST           -> the number (8-bit constant) from the instruction
//      LDR             -> the value that came back from memory
//      STR / NOP / RET -> don't write a register (writes_reg = 0)
//
// HARDWARE IT BECOMES
//   A 3-input multiplexer ("railroad switch") steered by `op`, plus a few
//   gates that produce `writes_reg`. Combinational: no clock, no memory.
//   Note: all three candidate values exist at the same time; the mux only
//   decides which one is allowed through.

`timescale 1ns/1ps
module writeback #(
    parameter WIDTH = 8
) (
    input  wire [3:0]       op,
    input  wire [WIDTH-1:0] alu_y,       // from the ALU
    input  wire [7:0]       imm,         // from the decoder
    input  wire [WIDTH-1:0] mem_rdata,   // from data memory
    output reg  [WIDTH-1:0] wd,          // -> register file write data
    output reg              writes_reg   // 1 if this instruction writes rd
);
    `include "isa.vh"

    // always @(*) = combinational. Every path assigns BOTH outputs, so no
    // latches are created.
    always @(*) begin
        case (op)
            OP_ADD, OP_SUB, OP_MUL: begin wd = alu_y;          writes_reg = 1'b1; end
            OP_CONST:               begin wd = imm[WIDTH-1:0]; writes_reg = 1'b1; end
            OP_LDR:                 begin wd = mem_rdata;      writes_reg = 1'b1; end 
        
            default:                begin wd = alu_y;          writes_reg = 1'b0; end
        endcase
    end
endmodule
