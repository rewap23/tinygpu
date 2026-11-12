// ============================================================================
// isa.vh -- the tinygpu instruction set (shared by every module + assembler)
// ============================================================================
// The 8 opcodes (NOP, ADD, SUB, MUL, CONST, LDR, STR, RET) 
// + the special register numbers r13 to r15
// 
// Every instruction is 16 bits:
//
//    15    12 11     8 7      4 3      0
//   +--------+--------+--------+--------+
//   | opcode |   rd   |   rs   |   rt   |     R-type  (ADD/SUB/MUL/LDR/STR)
//   +--------+--------+--------+--------+
//   | opcode |   rd   |      imm8       |     I-type  (CONST)
//   +--------+--------+-----------------+
//
// There are 16 registers per lane (thread). r0..r12 are general purpose.
// r13..r15 are READ-ONLY "special registers" wired straight from the core,
// exactly like CUDA's built-ins:
//      r13 = blockIdx.x   r14 = blockDim.x   r15 = threadIdx.x
//
// `include this file *inside* a module so the names are local to it.

localparam [3:0] OP_NOP   = 4'h0;  // do nothing
localparam [3:0] OP_ADD   = 4'h1;  // rd = rs + rt
localparam [3:0] OP_SUB   = 4'h2;  // rd = rs - rt
localparam [3:0] OP_MUL   = 4'h3;  // rd = rs * rt   (low 8 bits)
localparam [3:0] OP_CONST = 4'h4;  // rd = imm8
localparam [3:0] OP_LDR   = 4'h5;  // rd = mem[rs]
localparam [3:0] OP_STR   = 4'h6;  // mem[rs] = rt
localparam [3:0] OP_RET   = 4'h7;  // this block is finished

localparam [3:0] REG_BLOCK_IDX  = 4'd13;
localparam [3:0] REG_BLOCK_DIM  = 4'd14;
localparam [3:0] REG_THREAD_IDX = 4'd15;
