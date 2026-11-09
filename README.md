# TinyGPU: a small four-lane processor

This project is a teaching model of a tiny GPU-like processor written in
Verilog. It runs a small program that adds two arrays:

```text
C[i] = A[i] + B[i]
```

The central idea is simple: **one instruction is sent to four lanes, and
each lane applies it to its own data.** That is called SIMD/SIMT-style
execution. This project is small enough to simulate on a laptop; it is not
a complete or commercially realistic GPU.

## Start with the big picture

```text
                host (testbench)
             loads program and data
                       |
                       v
     +---------------------------------------+
     |                  core                 |
     |                                       |
     | instruction memory -> scheduler       |
     |                           |           |
     |                        decoder        |
     |                           |           |
     |               same instruction to all |
     |                  +------+------+      |
     |                  v      v      v      |
     |                lane 0 lane 1 ... lane 3
     |                  |      |      |      |
     |                  +------ shared ------+
     |                         data memory   |
     +---------------------------------------+
                       |
                       v
              host reads result C
```

The host in this project is the testbench (`tb/tb_core.v`). It loads the
program into instruction memory and the arrays into data memory, starts the
processor, waits for it to finish, and checks the answers.

## What is a lane?

A **lane** is one small worker. There are four lanes in the default core.
Each lane has its own:

- **Register file:** small private storage for values the lane is using.
- **ALU:** calculator for add, subtract, and multiply.
- **Write-back logic:** chooses which value to save in a register.

The lanes share the instruction stream and data memory. They receive the
same operation and register numbers, but their register contents can differ.
That lets them execute the same instruction on different array elements at
the same time.

For example, when all lanes run `ADD`, lane 0 adds its two values, lane 1
adds its own two values, and so on. The instruction is shared; the data is
per lane.

## What happens during one instruction?

The scheduler has three states:

1. **IDLE:** Wait for the host to start the program.
2. **FETCH:** Read the instruction at the program counter (PC).
3. **EXEC:** Decode and run that instruction on the lanes.

The processor uses one FETCH cycle and one EXEC cycle per instruction.
During EXEC, the lanes' register or memory writes happen at the rising edge
of the clock. After an ordinary instruction, the scheduler advances the PC.
After `RET`, it either starts the program again for the next group of lanes,
or marks the whole job done.

In Verilog, `assign` and `always @(*)` describe logic that responds to
inputs. `always @(posedge clk)` describes stored state that changes on a
clock edge. A variable declared `reg` is not necessarily a physical
register; the clocked behavior is what makes it storage.

## How four lanes cover many elements

Each lane has a fixed lane number, called `threadIdx` here:

| Lane | `threadIdx` |
|---:|---:|
| 0 | 0 |
| 1 | 1 |
| 2 | 2 |
| 3 | 3 |

The program calculates an element index for each lane:

```text
index = blockIdx * 4 + threadIdx
```

The four lanes in block 0 process elements 0 through 3. If there are more
elements, the scheduler advances `blockIdx` and runs the same program again;
block 1 processes elements 4 through 7, and so on.

If the number of requested elements is not a multiple of four, the last
block has an out-of-range lane. The **thread mask** checks whether that
lane's index is less than the requested thread count. An inactive lane
still receives the instructions, but it cannot write a register or store
to memory.

## The example program, in plain language

[`sw/vecadd.asm`](sw/vecadd.asm) is the program the processor runs. It:

1. Calculates the lane's element index.
2. Loads `A[index]`.
3. Loads `B[index]`.
4. Adds the two values.
5. Stores the sum in `C[index]`.
6. Runs `RET` to finish this block.

The example's memory layout is:

```text
addresses  0–7:  A[0] through A[7]
addresses  8–15: B[0] through B[7]
addresses 16–23: C[0] through C[7]
```

The assembler [`sw/asm.py`](sw/asm.py) converts the readable assembly into
16-bit machine instructions. The testbench loads those instructions into
the processor.

## What each hardware file does

The completed design is in [`rtl/`](rtl/). The exercise version, with
selected missing lines for you to fill in, is in [`starter/`](starter/).

| File | In simple terms |
|---|---|
| [`core.v`](rtl/core.v) | Connects all the pieces together and makes four lanes. |
| [`scheduler.v`](rtl/scheduler.v) | Controls IDLE, FETCH, EXEC, the PC, and blocks. |
| [`imem.v`](rtl/imem.v) | Holds the program instructions. |
| [`decoder.v`](rtl/decoder.v) | Splits one instruction into operation and register fields. |
| [`lane.v`](rtl/lane.v) | Connects one lane's registers, ALU, memory signals, and write controls. |
| [`regfile.v`](rtl/regfile.v) | Holds one lane's private registers and supplies special values. |
| [`alu.v`](rtl/alu.v) | Calculates arithmetic results. |
| [`writeback.v`](rtl/writeback.v) | Selects the value to save: ALU result, constant, or loaded data. |
| [`thread_mask.v`](rtl/thread_mask.v) | Decides whether a lane is within the requested thread count. |
| [`dmem.v`](rtl/dmem.v) | Holds array data and provides memory access to the lanes and host. |
| [`isa.vh`](rtl/isa.vh) | Defines the instruction codes and special-register numbers. |

The special registers are:

| Register | Meaning |
|---|---|
| `r13` | `blockIdx`: which group of four is running |
| `r14` | `blockDim`: four lanes per group |
| `r15` | `threadIdx`: this lane's number, from 0 to 3 |

They are read-only values supplied by the core, not ordinary stored
registers.

## Instructions

Each instruction is 16 bits. The top four bits say what operation to do.
Other bits name registers or hold a small constant.

| Instruction | Meaning |
|---|---|
| `ADD rd, rs, rt` | Save `rs + rt` in `rd`. |
| `SUB rd, rs, rt` | Save `rs - rt` in `rd`. |
| `MUL rd, rs, rt` | Save the low 8 bits of `rs * rt` in `rd`. |
| `CONST rd, imm` | Save a constant in `rd`. |
| `LDR rd, rs` | Load data memory at address `rs` into `rd`. |
| `STR rs, rt` | Store the value in `rt` at the address in `rs`. |
| `NOP` | Do nothing. |
| `RET` | Finish this block. |

## Try it

The project uses Icarus Verilog to simulate the design and Yosys to estimate
hardware size. After installing those tools, run these commands from the
project directory:

```bash
make help                 # show available targets
make alu SRC=starter      # test the starter ALU
make regfile SRC=starter  # test the starter registers
make decoder SRC=starter  # test instruction decoding
make scheduler SRC=starter
make core SRC=starter     # run the complete example (8 threads)
make core SRC=starter N=7 # see an out-of-range lane get masked
make all SRC=starter      # run all tests
```

The files in `starter/` contain TODOs, so tests may fail until you complete
the exercises. To compare with the finished implementation, run a target
without `SRC=starter`, for example `make core`.

Useful places to look:

- [`tb/`](tb/) contains testbenches. `tb_core.v` acts as the host and checks
  the finished array.
- [`synth/`](synth/) contains Yosys scripts for estimating hardware size
  and drawing a small ALU schematic.
- [`notes.md`](notes.md) suggests follow-on exercises.

## A good way to learn it

Don't try to understand every file at once. Start with `alu.v`, then test
it. Next learn how one lane stores values in `regfile.v`. After that,
follow the instruction through `decoder.v`, `lane.v`, and `scheduler.v`.
Finally, run `tb_core.v` and watch the four lanes process the arrays.

For every step, ask:

1. What values go into this part?
2. What result comes out?
3. Does it change immediately, or only on a clock edge?
4. Which testbench checks it?

That is enough to build up a complete picture of the mini GPU one small
piece at a time.
