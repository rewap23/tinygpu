// ============================================================================
// scheduler.v -- the control unit: decides what happens on every clock tick
// ============================================================================
// The scheduler contains a FINITE STATE MACHINE (FSM):
//    An FSM is a circuit that keeps of which step it's on and changes steps
//    based on inputs. FSM is a system with a limited set of states. It stays
//    in one state until an event or condition tells it to switch.
//    
// OVERVIEW
//   GPU's traffic controller:
//    It tracks which instruction is next, When the lanes
//    should execute it, and Which group (block) of threads is running:
//     IDLE  : wait for start, when it arrives reset pc and block_idx
//     FETCH : copy the instruction at pc into ir
//     EXEC  : the lanes execute the instruction; for a normal instruction
//             advance pc and repeat FETCH again 
//   When RET ("done"), run it again for the next group of
//   4 threads (next block). After the last block, mark the job as `done`.
//
//        start            always          not RET: pc = pc + 1
//   IDLE -----> FETCH ------------> EXEC ------------------------> FETCH
//                                     |  RET, more blocks: block_idx + 1, pc = 0
//                                     |  RET, last block : done = 1 -> IDLE
//
// HARDWARE IT BECOMES
//   Flip-flops: state (2), pc (8), ir (16), block_idx (8), done (1).
//   In front of them: muxes + an adder (pc+1, block_idx+1) + a comparator
//   that compute the NEXT value of each one. On each rising clock edge,
//   all of them update at the same instant.
//
// GPU ANALOGY
//   The warp scheduler + block dispatcher

`timescale 1ns/1ps
module scheduler #(
    parameter WIDTH = 8,
    parameter LANES = 4             // threads per block (power of two)
) (
    input  wire             clk,
    input  wire             rst,
    // from the host
    input  wire             start,
    input  wire [WIDTH-1:0] num_threads,
    // from instruction memory (the word at address pc)
    input  wire [15:0]      instr,
    // from the decoder (the op of the instruction currently in ir)
    input  wire [3:0]       op,
    // outputs
    output reg  [7:0]       pc,         // address of the next instruction
    output reg  [15:0]      ir,         // instruction register
    output reg  [WIDTH-1:0] block_idx,  // which block is running (blockIdx.x)
    output wire             exec,       // 1 during EXEC -> lanes may write
    output wire             idle,       // 1 while IDLE  -> host may write mems
    output reg              done        // kernel finished
);
    `include "isa.vh"

    // the three states, as 2-bit numbers
    localparam [1:0] S_IDLE  = 2'd0,
                     S_FETCH = 2'd1,
                     S_EXEC  = 2'd2;

    reg [1:0] state;                    // 2 flip-flops: "where are we?"

    // how many blocks? ceil(num_threads / LANES)
    // Because LANES is a power of two, "/ LANES" is a right shift = free wires.
    localparam LOG2_LANES = $clog2(LANES);
    wire [WIDTH:0]   threads_plus = {1'b0, num_threads} + (LANES - 1);
    wire [WIDTH-1:0] num_blocks   = threads_plus[WIDTH:LOG2_LANES];

    // simple status wires other modules use
    assign exec = (state == S_EXEC);
    assign idle = (state == S_IDLE);

    // ---------------------------------------------------------------------
    // The state machine. Read every `x <= y;` as:
    //   "at the next clock tick, flip-flop x becomes y"
    // ---------------------------------------------------------------------
    always @(posedge clk) begin
        if (rst) begin
            state     <= S_IDLE;
            pc        <= 8'd0;
            ir        <= 16'h0000;
            block_idx <= {WIDTH{1'b0}};
            done      <= 1'b0;
        end else begin
            case (state)

                S_IDLE: begin
                    if (start) begin
                        pc        <= 8'd0;
                        block_idx <= {WIDTH{1'b0}};
                        done      <= 1'b0;
                        state     <= S_FETCH;
                    end
                end

                S_FETCH: begin
                    ir    <= instr;            // grab the instruction at pc
                    state <= S_EXEC;
                end

                S_EXEC: begin                  // lanes write results on THIS tick
                    if (op == OP_RET) begin 
                        if (block_idx + 1'b1 < num_blocks) begin
                            block_idx <= block_idx + 1'b1;  // next block
                            pc <= 8'd0;                     // restart kernel
                            state <= S_FETCH;
                        end else begin
                            done  <= 1'b1;                  // all blocks done
                            state <= S_IDLE;
                        end
                    end else begin
                        pc <= pc + 1'b1;                   // next instruction
                        state <= S_FETCH;
                    end
                end

                default: state <= S_IDLE;
            endcase
        end
    end
endmodule
