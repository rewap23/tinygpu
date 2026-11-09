# tinygpu — a 4-lane SIMT core in Verilog, end to end

A deliberately tiny GPU core that runs a real "CUDA-style" kernel
(`C[i] = A[i] + B[i]`) so you can follow every step from **assembly →
machine code → flip-flops and gates**, and explain what each line of
Verilog physically becomes.

```
vecadd.asm ──asm.py──► vecadd.hex ──host driver (tb_core.v)──► core.v
                                                                │
          ┌──────────── core (the "SM") ────────────────────────┤
          │ imem ─► IR ─► ONE decoder ──broadcast──► lane0..lane3│
          │ PC + FSM + blockIdx counter + mask logic            │
          │ dmem (shared, 1 port per lane + 1 for the host)     │
          └─────────────────────────────────────────────────────┘
                     │ yosys
                     ▼
            ~10k generic gates  /  ~5.4k iCE40 LUTs
```

| Real GPU / CUDA concept          | Where it is here                                   |
|----------------------------------|----------------------------------------------------|
| CUDA core                        | `lane.v` (ALU + private registers)                 |
| Warp / SIMT                      | 4 lanes driven by one decoder in `core.v`          |
| `threadIdx.x`                    | r15 — a hard-wired constant per lane               |
| `blockIdx.x`, `blockDim.x`       | r13 (a counter in the scheduler), r14 (constant)   |
| `if (i < n)` / divergence mask   | `active` signal gating writes in `lane.v`          |
| Grid of blocks                   | FSM re-runs the kernel, bumping blockIdx, on `RET` |
| SASS / ptxas                     | `sw/asm.py` → 16-bit words                          |
| cudaMemcpy, kernel launch, sync  | host bus + `start`/`done` in `tb_core.v`           |
| Global memory                    | `dmem` (64 bytes)                                   |

---

## 0. Setup (macOS)

```bash
brew install icarus-verilog yosys graphviz
# waveform viewer: either `brew install --cask gtkwave`, or Surfer
# (surfer-project.org, also runs in the browser), or the VS Code
# "WaveTrace" extension.
make help
```

Everything below runs on your laptop — no FPGA or GPU required.

## How to work through it

There are two copies of the RTL:

* `starter/` — the same design with key lines replaced by **TODOs**.
* `rtl/` — the finished reference.

Do each stage in `starter/`, test with `SRC=starter`, and only peek at
`rtl/` when stuck:

```bash
make alu      SRC=starter     # stage 1  (TODO 1a)
make regfile  SRC=starter     # stage 2  (TODO 2a, 2b)
make core     SRC=starter     # stage 3+4 (TODO 3a-c, 4a-b)
make core     SRC=starter N=7 # masking
make synth    SRC=starter     # stage 5
```

---

## 1. The one idea that makes Verilog click

Verilog is not a program that runs. It's a **description of a circuit**,
and every construct maps to one of exactly two kinds of hardware:

| You write                                 | You get                          | When does it "happen"?          |
|-------------------------------------------|----------------------------------|---------------------------------|
| `assign x = ...;` or `always @(*)`        | **combinational logic** (gates, muxes, adders) | continuously; output settles ns after inputs change |
| `always @(posedge clk)` with `<=`         | **flip-flops** (+ logic feeding their D input) | only at the rising clock edge   |

Corollaries you should be able to say out loud:

* **`reg` doesn't mean register.** `y` in `alu.v` is a `reg` but it's
  combinational — there's no clock edge, so no flip-flop.
* **Every branch of an `if`/`case` exists physically.** The ALU builds an
  adder, a subtractor *and* a multiplier; `case(op)` becomes a mux that
  chooses which result leaves the box. Nothing "skips" work.
* **A combinational `case` needs a `default`** (or assign every output on
  every path). Otherwise the output must "remember" its old value in some
  case → the tool infers a **latch**, almost always a bug.
* **Slicing bits is free.** `ir[15:12]` is just routing wires — the
  decoder in `core.v` costs ~0 gates. Multiplying by a power of two (e.g.
  `block_idx << 2`) is also just wires.
* **`<=` vs `=`.** Use non-blocking `<=` in clocked blocks: all flip-flops
  sample their inputs *at the same instant*, then update together. That's
  how real flip-flops behave. Use blocking `=` in combinational blocks.

---

## 2. Module by module: code → hardware

### `alu.v` — combinational logic

`case (op)` with `a+b`, `a-b`, `a*b`. Synthesis result (8-bit):
**262 gates**, mostly XOR/AND — the multiplier array dominates. See it
yourself at 2-bit width: `make schematic` → `docs/alu_2bit.svg`. You'll see
XORs (adder sum bits), ANDs (carry and partial products) and two `$_MUX_`
cells at the end selected by bits of `op` — that's your `case`.

### `regfile.v` — sequential logic + multiplexers

* `reg [7:0] regs[0:12]` + `always @(posedge clk)` → **104 D flip-flops**
  with synchronous reset and an enable (`$_SDFFCE_` cells in the report).
* `if (we && wa < 13) regs[wa] <= wd;` → a 4-to-13 **decoder** producing
  each register's enable.
* Each read port (`da`, `db`) → a **16:1 mux, 8 bits wide**. Two ports →
  most of the regfile's 288 `$_MUX_` cells.
* r13–r15 aren't flip-flops: they're **wires** from the core. `threadIdx.x`
  for lane 2 is literally the constant `8'd2` tied into its mux.

Key timing rule (the regfile test checks it): a write is **invisible
until after the clock edge**. During a cycle you read old values, compute,
and the result lands at the edge.

> Investigate: the report shows 24 extra plain `$_DFFE_` cells in the
> regfile beyond the 104. Open `build/rtl/synth.log`, find them, and
> explain where they come from. (Reading synthesis reports is a real skill.)

### `lane.v` — one thread's datapath

ALU + regfile + a **3:1 write-back mux** (ALU result / immediate / memory)
+ three AND gates:

```verilog
wire reg_we = exec & writes_reg & active;
```

That AND with `active` **is** the SIMT mask. A masked lane still receives
the instruction and still spends the cycle; its writes are just blocked.
That's exactly why a CUDA warp with a partially-true `if` wastes lanes.

### `core.v` — the scheduler

* **FSM flip-flops:** `state`, `pc`, `ir`, `block_idx`, `done`
  (≈33 FFs). Every instruction takes two cycles:
  * `FETCH`: `ir <= imem[pc]`
  * `EXEC`: decoded fields fan out to all lanes; at the *end* of this cycle
    (the clock edge) each lane writes its register / memory, and the FSM
    moves `pc` forward — or, on `RET`, starts the next block or raises
    `done`.
* **`generate for`** stamps out 4 physical copies of `lane`. Lane `l` gets
  `thread_idx = l` (a constant) and its own `active` comparator
  (`blockIdx*4 + l < num_threads`).
* **Data memory** has 5 read ports and 5 write ports (4 lanes + host).
  That's the expensive part — see §4.

---

## 3. Watch one kernel run

```bash
make core          # 8 threads = 2 blocks
make core N=7      # lane 3 masked in block 1; C[7] stays 0xEE
```

The trace prints one line per `EXEC` cycle, showing the value each lane
read from `rs`. Look at `pc=6 LDR`: the four lanes present addresses
`0 1 2 3` — **same instruction, different data**. In block 1 they present
`4 5 6 7`. That's SIMT in one line.

Total: 13 instructions × 2 cycles × 2 blocks + 1 = **53 cycles**.

Open `build/rtl/tb_core.vcd` in a waveform viewer and add:
`clk`, `dut.state`, `dut.pc`, `dut.ir`, `dut.block_idx`,
`dut.g_lane[0].u_lane.u_rf.regs[4]`, `dut.g_lane[3].active`, `dut.done`.
Follow `LDR r4, r4` (`pc=6`): in FETCH `ir` becomes `5440`; in EXEC lane 0's
`mem_addr` is 0 and `mem_rdata` is 10; at the next rising edge `regs[4]`
becomes 10. Being able to narrate that cycle is the goal of this project.

Machine code, for reference (`make asm`):

```
 0: 0011 0000 1101 1110  30de   MUL   r0, %blockIdx, %blockDim
 1: 0001 0000 0000 1111  100f   ADD   r0, r0, %threadIdx
     op   rd   rs   rt
```

---

## 4. Synthesis: what did the hardware cost?

```bash
make synth
```

Measured with Yosys 0.33 (generic gates, hierarchy kept):

| Module (one instance) | Cells | Notes |
|---|---|---|
| `alu`     | 262   | multiplier is most of it |
| `regfile` | 487   | 128 flip-flops + 2 read muxes |
| `lane` glue | 55  | write-back mux + mask ANDs |
| `core` (own logic) | 7,444 | **1,024 FFs for imem+dmem**, 5,065 muxes |
| **Total** | **10,648** | |

Scaling `LANES` (flattened generic synth, same flow):

| LANES | Total cells | Δ per extra lane |
|---|---|---|
| 1 | 4,286  | — |
| 2 | 6,270  | ~1,980 |
| 4 | 10,182 | ~1,960 |
| 8 | 18,022 | ~1,960 |

The control logic (FSM, PC, decoder) costs the **same** at 1 or 8 lanes —
that's the whole economic argument for SIMT: amortize one instruction
stream over many datapaths. But notice each lane costs ~800 cells of
datapath and **more than that again in memory ports** (each extra lane adds
a 64:1 × 8-bit read mux plus a write port on `dmem`). That's why real GPUs
don't give every lane a private port into memory: they use **banked shared
memory** (bank conflicts!) and **coalesce** a warp's global accesses into
wide transactions.

On a Lattice iCE40 FPGA (`synth_ice40`): **5,423 LUT4s, 952 flip-flops,
126 carry cells, 1 block RAM**. Yosys put `imem` in a block RAM (one read
port — fits), but `dmem` stays in LUTs because block RAM has at most 2
ports and we asked for 5. Fits an HX8K-class part.

---

## Files

```
rtl/       reference RTL (isa.vh, alu.v, regfile.v, lane.v, core.v)
starter/   same, with TODOs for you to fill in
tb/        tb_alu (exhaustive), tb_regfile (directed), tb_core (host driver)
sw/        asm.py assembler, vecadd.asm kernel
synth/     synth.ys (generic + iCE40), schematic.ys
docs/      alu_2bit.svg gate-level schematic
```
