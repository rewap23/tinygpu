// ============================================================================
// thread_mask.v -- is this lane's thread real, or past the end of the array?
// ============================================================================
// OVERVIEW
//   Each lane works out its global thread id:
//        i = blockIdx * blockDim + threadIdx
//   and is "active" only if i < num_threads. With 7 threads and 4 lanes,
//   block 1 holds threads 4,5,6,7 -- thread 7 doesn't exist, so lane 3 is
//   switched off for that block.
//
// HARDWARE IT BECOMES
//   * "blockIdx * 4" is a shift left by 2       -> just wires, free
//   * "+ LANE_ID"    adds a constant            -> a small adder
//   * "< num_threads"                           -> one comparator
//   One copy of this per lane. LANE_ID is a constant baked in at build time.
//
// GPU ANALOGY
//   This is the hardware behind `if (i < n)` in a CUDA kernel. The masked
//   lane still exists and still spends the cycle; it just isn't allowed to
//   write anything (see the AND gates in lane.v).

`timescale 1ns/1ps
module thread_mask #(
    parameter WIDTH   = 8,
    parameter LANES   = 4,
    parameter LANE_ID = 0          // which lane this copy belongs to
) (
    input  wire [WIDTH-1:0] block_idx,
    input  wire [WIDTH-1:0] num_threads,
    output wire             active
);
    localparam LOG2_LANES = $clog2(LANES);

    // one extra bit so the math can't overflow
    wire [WIDTH:0] global_id = ({1'b0, block_idx} << LOG2_LANES) + LANE_ID;


    assign active = (global_id < ({1'b0, num_threads}));
endmodule
