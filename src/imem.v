// ============================================================================
// imem.v -- instruction memory (holds the kernel)
// ============================================================================
// OVERVIEW
//   A shelf of 16-bit instructions. The host writes the kernel into
//   it before launch, essentially puts the program on the shelf. 
//   The scheduler picks an instruction from it to tell the GPU what to do next;
//   reads one instruction at address `pc`.
//
// HARDWARE IT BECOMES
//   * DEPTH x 16 flip-flops (on an FPGA: one block RAM)
//   * one write port  (host)  -> a decoder picking which row to write
//   * one read port   (pc)    -> a big DEPTH:1 mux choosing which row to output
//
// GPU ANALOGY
//   Loading the compiled kernel (cubin / SASS) onto the device.

`timescale 1ns/1ps
module imem #(
    parameter DEPTH = 32
) (
    input  wire        clk,
    // write port -- used by the host to load the program
    input  wire        we,
    input  wire [7:0]  waddr,
    input  wire [15:0] wdata,
    // read port -- used by the scheduler
    input  wire [7:0]  raddr,
    output wire [15:0] rdata
);
    localparam AW = $clog2(DEPTH);       // address bits actually used (5)

    reg [15:0] mem [0:DEPTH-1];          // the storage

    // write: happens at the clock edge (sequential)
    always @(posedge clk) begin
        if (we)
            mem[waddr[AW-1:0]] <= wdata;
    end

    // read: available right away (combinational)
    assign rdata = mem[raddr[AW-1:0]];
endmodule
