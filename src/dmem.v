// ============================================================================
// dmem.v -- data memory, shared by all lanes (acts as the GPU's "global memory")
// ============================================================================
// OVERVIEW
//   A table of DEPTH bytes. Arrays A, B and C live here. The host fills it
//   before launch and reads results after. During the kernel, every lane can
//   read one address and write one address per cycle -- all at once.
// 
// FLOW
//   Lane supplies an address --> 
//   Memory returns the value or lane supplies an address and data --> 
//   Data memory stores it at the next clock edge
//
// HARDWARE IT BECOMES
//   * DEPTH x WIDTH flip-flops (64 x 8 = 512)
//   * one READ port per lane + one for the host. Each read port is a
//     64:1 mux, 8 bits wide. FIVE of them -- this is the most expensive
//     part of the whole chip (see README "Synthesis").
//   * one WRITE port per lane + one for the host.
//   Real GPUs can't afford a port per thread; they use banked shared memory
//   and "coalesce" a warp's accesses into one wide request instead.
//
// ABOUT THE "FLATTENED" BUSES
//   Verilog-2005 can't pass an array of buses through a port, so the four
//   lanes' 8-bit addresses are glued side by side into one 32-bit bus:
//
//       lane_addr = { lane3_addr, lane2_addr, lane1_addr, lane0_addr }
//                     bits 31:24  bits 23:16  bits 15:8   bits 7:0
//
//   `lane_addr[l*WIDTH +: WIDTH]` means "WIDTH bits starting at l*WIDTH",
//   i.e. lane l's slice.

`timescale 1ns/1ps
module dmem #(
    parameter WIDTH = 8,
    parameter DEPTH = 64,
    parameter LANES = 4
) (
    input  wire                   clk,
    // host port
    input  wire                   host_we,
    input  wire [7:0]             host_addr,
    input  wire [WIDTH-1:0]       host_wdata,
    output wire [WIDTH-1:0]       host_rdata,
    // lane ports (flattened, see above)
    input  wire [LANES*WIDTH-1:0] lane_addr,
    input  wire [LANES*WIDTH-1:0] lane_wdata,
    input  wire [LANES-1:0]       lane_we,
    output wire [LANES*WIDTH-1:0] lane_rdata
);
    localparam AW = $clog2(DEPTH);       // address bits actually used (6)

    reg [WIDTH-1:0] mem [0:DEPTH-1];

    // ---- read ports: one combinational mux per lane ----------------------
    genvar l;
    generate
        for (l = 0; l < LANES; l = l + 1) begin : g_read
            assign lane_rdata[l*WIDTH +: WIDTH] = mem[lane_addr[l*WIDTH +: AW]];
        end
    endgenerate

    assign host_rdata = mem[host_addr[AW-1:0]];

    // ---- write ports: sequential (on the clock edge) ----------------------
    // If two lanes store to the same address in the same cycle, the higher
    // lane number wins (it's assigned last). Real GPUs also leave this
    // undefined -- that's why atomic instructions exist.
    integer k;
    always @(posedge clk) begin
        if (host_we)
            mem[host_addr[AW-1:0]] <= host_wdata;
        for (k = 0; k < LANES; k = k + 1)
            if (lane_we[k])
                mem[lane_addr[k*WIDTH +: AW]] <= lane_wdata[k*WIDTH +: WIDTH];
    end 
endmodule
