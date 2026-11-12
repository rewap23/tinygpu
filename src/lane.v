// ============================================================================
// lane.v -- ONE lane: one thread's datapath (one "CUDA core")
// ============================================================================
// OVERVIEW
//   A lane is a pair of hands: it has its own registers and its own
//   calculator, but no brain. It does whatever op/rd/rs/rt the decoder
//   broadcasts. This file only WIRES its parts together:
//
//              rs, rt                      op
//                |                          |
//          +-----v------+   da, db   +------v---+   alu_y   +-----------+
//          |  regfile   |----------->|   alu    |---------->| writeback |
//          | (regfile.v)|            | (alu.v)  |   imm ---->|   mux     |
//          |            |<-----------+----------+-- wd -----| (writeback|
//          +------------+    write port         mem_rdata ->|    .v)    |
//               |  |                                        +-----------+
//          da --+  +-- db
//          v           v
//       mem_addr    mem_wdata    (to dmem.v: LDR/STR use rs as address,
//                                 STR uses rt as the data to store)
//
// HARDWARE IT BECOMES
//   Whatever its parts become, plus two 3-input AND gates (the mask gates
//   at the bottom of this file).

`timescale 1ns/1ps
module lane #(
    parameter WIDTH = 8
) (
    input  wire             clk,
    input  wire             rst,
    // from the decoder (identical for every lane)
    input  wire [3:0]       op,
    input  wire [3:0]       rd,
    input  wire [3:0]       rs,
    input  wire [3:0]       rt,
    input  wire [7:0]       imm,
    // from the scheduler
    input  wire             exec,        // 1 during the EXEC cycle
    // this lane's identity (special registers r13..r15)
    input  wire [WIDTH-1:0] block_idx,
    input  wire [WIDTH-1:0] block_dim,
    input  wire [WIDTH-1:0] thread_idx,
    // from thread_mask.v
    input  wire             active,
    // to / from data memory
    output wire [WIDTH-1:0] mem_addr,
    output wire [WIDTH-1:0] mem_wdata,
    output wire             mem_we,
    input  wire [WIDTH-1:0] mem_rdata
);
    `include "isa.vh"

    // internal wires connecting the parts
    wire [WIDTH-1:0] da, db;       // register values read out (rs, rt)
    wire [WIDTH-1:0] alu_y;        // ALU result
    wire [WIDTH-1:0] wd;           // value to write into rd
    wire             writes_reg;   // does this op write a register?
    wire             reg_we;       // final "write the register now" signal

    // ---- part 1: the registers -------------------------------------------
    regfile #(.WIDTH(WIDTH)) u_rf (
        .clk(clk), .rst(rst),
        .ra(rs), .rb(rt), .da(da), .db(db),
        .we(reg_we), .wa(rd), .wd(wd),
        .block_idx(block_idx), .block_dim(block_dim), .thread_idx(thread_idx)
    );

    // ---- part 2: the calculator -------------------------------------------
    alu #(.WIDTH(WIDTH)) u_alu (
        .op(op), .a(da), .b(db), .y(alu_y)
    );

    // ---- part 3: pick what to write back ----------------------------------
    writeback #(.WIDTH(WIDTH)) u_wb (
        .op(op), .alu_y(alu_y), .imm(imm), .mem_rdata(mem_rdata),
        .wd(wd), .writes_reg(writes_reg)
    );

    // ---- part 4: the mask gates -------------------------------------------
    // A register write happens only if ALL THREE are true:
    //   we're in EXEC  AND  this op writes a register  AND  this lane is active
    assign reg_we = (exec & writes_reg & active);

    // A memory store happens only during EXEC, for STR, in an active lane.
    assign mem_we = (exec & (op == OP_STR) & active);

    // ---- memory address/data come straight from the register reads -------
    assign mem_addr  = da;   // LDR rd, rs   /  STR rs, rt : address = rs
    assign mem_wdata = db;   // STR rs, rt                 : data    = rt
endmodule
