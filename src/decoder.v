// ============================================================================
// decoder.v -- takes one 16-bit instruction and 
//              gives names to the groups of bits inside it
// ============================================================================
// OVERVIEW
//   The instruction register (IR) holds 16 bits like 0001 0110 0100 0101.
//   The decoder just gives each group of 4 bits a name:
//
//      bits 15..12  -> op   (which operation, ex. 0001 = ADD)
//      bits 11..8   -> rd   (which register to WRITE, ex. r6)
//      bits  7..4   -> rs   (first register to READ,  ex. r4)
//      bits  3..0   -> rt   (second register to READ, ex. r5)
//      bits  7..0   -> imm  (an 8-bit constant, used only by CONST)
// 
// VISUAL DIAGRAM
// bits: 15     12 11      8 7       4 3       0
//       +--------+---------+---------+---------+
//       |   op   |   rd    |   rs    |   rt    |
//       +--------+---------+---------+---------+
//
// HARDWARE IT BECOMES
//   Nothing but wires. No gates, no flip-flops (doesn't execute the instruction).
//  "ir[15:12]" means "take wires 15, 14, 13, 12 of the ir bundle". 
//   That's possible because every
//   instruction puts its fields in the SAME bit positions (a design choice).
//
// GPU ANALOGY
//   There is ONE decoder, and its outputs fan out to ALL lanes. Every lane
//   receives the same op/rd/rs/rt -- that's what makes it SIMT.

`timescale 1ns/1ps
module decoder (
    input  wire [15:0] ir,     // instruction register, from the scheduler
    output wire [3:0]  op,
    output wire [3:0]  rd,
    output wire [3:0]  rs,
    output wire [3:0]  rt,
    output wire [7:0]  imm
);
    assign op  = ir[15:12];
    assign rd = ir[11:8];
    assign rs  = ir[7:4];
    assign rt  = ir[3:0];
    assign imm = ir[7:0];
endmodule
