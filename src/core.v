// ============================================================================
// core.v -- ONLY WIRING: it connects the parts, nothing else.
// ============================================================================
// Read this file like a block diagram. Every module below lives in its own
// file:
//
//                 host (testbench)
//                   |  load program / data, start, wait for done
//                   v
//   +--------+   instr   +-------------+   ir   +-----------+
//   |  imem  |---------->|  scheduler  |------->|  decoder  |
//   |imem.v  |<--- pc ---|scheduler.v  |<- op --| decoder.v |
//   +--------+           +-------------+        +-----------+
//                          | exec, block_idx       | op rd rs rt imm
//                          v                       v   (same to every lane)
//              +-------------+-------------+-------------+-------------+
//              | thread_mask | thread_mask | thread_mask | thread_mask |
//              |   lane 0    |   lane 1    |   lane 2    |   lane 3    |
//              |  (lane.v)   |  (lane.v)   |  (lane.v)   |  (lane.v)   |
//              +-------------+-------------+-------------+-------------+
//                    ^ |           ^ |           ^ |           ^ |
//                    | v           | v           | v           | v
//              +---------------------------------------------------+
//              |                dmem (dmem.v)                      |
//              +---------------------------------------------------+
//
// Execution model (CUDA, minus everything hard):
//   host loads imem + dmem, sets num_threads, pulses start   (kernel launch)
//   -> blocks of LANES threads run one after another          (the grid)
//   -> each instruction = 2 clock cycles (FETCH, EXEC)
//   -> done goes high                                          (synchronize)

`timescale 1ns/1ps
module core #(
    parameter WIDTH      = 8,
    parameter LANES      = 4,     // threads per block, power of two
    parameter IMEM_DEPTH = 32,
    parameter DMEM_DEPTH = 64
) (
    input  wire             clk,
    input  wire             rst,
    // host interface (only works while the core is idle)
    input  wire             host_we,
    input  wire             host_sel,     // 0 = instruction mem, 1 = data mem
    input  wire [7:0]       host_addr,
    input  wire [15:0]      host_wdata,
    output wire [WIDTH-1:0] host_rdata,   // reads data memory
    // kernel launch
    input  wire [WIDTH-1:0] num_threads,
    input  wire             start,
    output wire             done
);
    localparam [WIDTH-1:0] BLOCK_DIM = LANES;

    // ---------------------------------------------------------------------
    // Wires between the blocks (named after what they carry)
    // ---------------------------------------------------------------------
    wire [7:0]       pc;
    wire [15:0]      instr;          // imem -> scheduler
    wire [15:0]      ir;             // scheduler -> decoder
    wire [3:0]       op, rd, rs, rt; // decoder -> lanes (and op -> scheduler)
    wire [7:0]       imm;
    wire             exec, idle;
    wire [WIDTH-1:0] block_idx;

    // the host may only write memories while nothing is running
    wire host_ok = host_we & idle;

    // ---- 1. instruction memory --------------------------------------------
    imem #(.DEPTH(IMEM_DEPTH)) u_imem (
        .clk(clk),
        .we(host_ok & ~host_sel), .waddr(host_addr), .wdata(host_wdata),
        .raddr(pc), .rdata(instr)
    );

    // ---- 2. scheduler ------------------------------------------------------
    scheduler #(.WIDTH(WIDTH), .LANES(LANES)) u_sched (
        .clk(clk), .rst(rst),
        .start(start), .num_threads(num_threads),
        .instr(instr), .op(op),
        .pc(pc), .ir(ir), .block_idx(block_idx),
        .exec(exec), .idle(idle), .done(done)
    );

    // ---- 3. decoder (ONE for all lanes) ------------------------------------
    decoder u_dec (
        .ir(ir), .op(op), .rd(rd), .rs(rs), .rt(rt), .imm(imm)
    );

    // ---- 4. the lanes: `generate for` builds LANES physical copies --------
    // Each lane's memory signals ride on a slice of these flattened buses
    // (see dmem.v for the picture).
    wire [LANES*WIDTH-1:0] lane_addr, lane_wdata, lane_rdata;
    wire [LANES-1:0]       lane_we;

    genvar l;
    generate
        for (l = 0; l < LANES; l = l + 1) begin : g_lane
            localparam [WIDTH-1:0] TID = l;   // this lane's threadIdx.x

            wire active;

            thread_mask #(.WIDTH(WIDTH), .LANES(LANES), .LANE_ID(l)) u_mask (
                .block_idx(block_idx), .num_threads(num_threads),
                .active(active)
            );

            lane #(.WIDTH(WIDTH)) u_lane (
                .clk(clk), .rst(rst),
                .op(op), .rd(rd), .rs(rs), .rt(rt), .imm(imm),
                .exec(exec),
                .block_idx(block_idx), .block_dim(BLOCK_DIM),
                .thread_idx(TID),             // a constant: 0, 1, 2 or 3
                .active(active),
                .mem_addr (lane_addr [l*WIDTH +: WIDTH]),
                .mem_wdata(lane_wdata[l*WIDTH +: WIDTH]),
                .mem_we   (lane_we[l]),
                .mem_rdata(lane_rdata[l*WIDTH +: WIDTH])
            );
        end
    endgenerate

    // ---- 5. data memory (shared by all lanes + host) ----------------------
    dmem #(.WIDTH(WIDTH), .DEPTH(DMEM_DEPTH), .LANES(LANES)) u_dmem (
        .clk(clk),
        .host_we(host_ok & host_sel), .host_addr(host_addr),
        .host_wdata(host_wdata[WIDTH-1:0]), .host_rdata(host_rdata),
        .lane_addr(lane_addr), .lane_wdata(lane_wdata),
        .lane_we(lane_we), .lane_rdata(lane_rdata)
    );
endmodule
