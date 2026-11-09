# TinyGPU: a small four-lane processor for vector addition

This project is a model of a tiny GPU-like processor written in Verilog. It runs a small program that adds two arrays:

```text
C[i] = A[i] + B[i]
```

The central idea is simple: **one instruction is sent to four lanes, and each lane applies it to its own data.** That is called SIMD/SIMT-style execution. SIMD stands for Same Instruction, Multiple Data. This project is small enough to simulate on a laptop; it is not a complete or commercially realistic GPU.

## Big Picture of TinyGPU (Architecture)

```mermaid
flowchart TB
    HOST["Host / testbench<br/>loads program and data; starts core; reads results"]

    subgraph CORE["TinyGPU core"]
        direction TB

        subgraph CONTROL["Shared instruction and control path"]
            direction LR
            IMEM["Instruction memory<br/>imem.v"]
            SCHED["Scheduler<br/>PC, instruction register,<br/>IDLE / FETCH / EXEC,<br/>block index"]
            DEC["Decoder<br/>splits instruction into<br/>op, rd, rs, rt, immediate"]
            IMEM -->|"instruction at PC"| SCHED
            SCHED -->|"PC"| IMEM
            SCHED -->|"instruction register"| DEC
            DEC -->|"op: check for RET"| SCHED
        end

        subgraph LANES["Four lanes: same instruction, different data"]
            direction LR

            subgraph L0["Lane 0 (threadIdx = 0)"]
                direction TB
                MASK0["Thread mask<br/>active = global index < thread count"]
                RF0["Register file<br/>r0-r12 plus special r13-r15"]
                ALU0["ALU<br/>ADD / SUB / MUL"]
                WB0["Write-back mux<br/>ALU / constant / loaded data"]
                CTRL0["Write enables<br/>EXEC + active + operation"]
                RF0 -->|"rs and rt values"| ALU0
                ALU0 --> WB0
                WB0 -->|"write data"| RF0
                RF0 -->|"rs: load/store address"| DMEM
                RF0 -->|"rt: store data"| DMEM
                DMEM -->|"loaded value"| WB0
                MASK0 --> CTRL0
                CTRL0 -->|"register write enable"| RF0
                CTRL0 -->|"store enable"| DMEM
            end

            subgraph L1["Lane 1 (threadIdx = 1)"]
                direction TB
                MASK1["Thread mask<br/>active = global index < thread count"]
                RF1["Register file<br/>r0-r12 plus special r13-r15"]
                ALU1["ALU<br/>ADD / SUB / MUL"]
                WB1["Write-back mux<br/>ALU / constant / loaded data"]
                CTRL1["Write enables<br/>EXEC + active + operation"]
                RF1 -->|"rs and rt values"| ALU1
                ALU1 --> WB1
                WB1 -->|"write data"| RF1
                RF1 -->|"rs: load/store address"| DMEM
                RF1 -->|"rt: store data"| DMEM
                DMEM -->|"loaded value"| WB1
                MASK1 --> CTRL1
                CTRL1 -->|"register write enable"| RF1
                CTRL1 -->|"store enable"| DMEM
            end

            subgraph L2["Lane 2 (threadIdx = 2)"]
                direction TB
                MASK2["Thread mask<br/>active = global index < thread count"]
                RF2["Register file<br/>r0-r12 plus special r13-r15"]
                ALU2["ALU<br/>ADD / SUB / MUL"]
                WB2["Write-back mux<br/>ALU / constant / loaded data"]
                CTRL2["Write enables<br/>EXEC + active + operation"]
                RF2 -->|"rs and rt values"| ALU2
                ALU2 --> WB2
                WB2 -->|"write data"| RF2
                RF2 -->|"rs: load/store address"| DMEM
                RF2 -->|"rt: store data"| DMEM
                DMEM -->|"loaded value"| WB2
                MASK2 --> CTRL2
                CTRL2 -->|"register write enable"| RF2
                CTRL2 -->|"store enable"| DMEM
            end

            subgraph L3["Lane 3 (threadIdx = 3)"]
                direction TB
                MASK3["Thread mask<br/>active = global index < thread count"]
                RF3["Register file<br/>r0-r12 plus special r13-r15"]
                ALU3["ALU<br/>ADD / SUB / MUL"]
                WB3["Write-back mux<br/>ALU / constant / loaded data"]
                CTRL3["Write enables<br/>EXEC + active + operation"]
                RF3 -->|"rs and rt values"| ALU3
                ALU3 --> WB3
                WB3 -->|"write data"| RF3
                RF3 -->|"rs: load/store address"| DMEM
                RF3 -->|"rt: store data"| DMEM
                DMEM -->|"loaded value"| WB3
                MASK3 --> CTRL3
                CTRL3 -->|"register write enable"| RF3
                CTRL3 -->|"store enable"| DMEM
            end
        end

        DMEM["Shared data memory<br/>dmem.v<br/>one lane port per lane"]
        BLOCKDIM["blockDim = 4<br/>constant for this core"]

        DEC -.->|"op, rd, rs, rt, immediate"| RF0
        DEC -.->|"op, rd, rs, rt, immediate"| ALU0
        DEC -.->|"op and immediate"| WB0
        DEC -.->|"op, rd, rs, rt, immediate"| RF1
        DEC -.->|"op, rd, rs, rt, immediate"| ALU1
        DEC -.->|"op and immediate"| WB1
        DEC -.->|"op, rd, rs, rt, immediate"| RF2
        DEC -.->|"op, rd, rs, rt, immediate"| ALU2
        DEC -.->|"op and immediate"| WB2
        DEC -.->|"op, rd, rs, rt, immediate"| RF3
        DEC -.->|"op, rd, rs, rt, immediate"| ALU3
        DEC -.->|"op and immediate"| WB3

        SCHED -.->|"EXEC, block index"| CTRL0
        SCHED -.->|"EXEC, block index"| CTRL1
        SCHED -.->|"EXEC, block index"| CTRL2
        SCHED -.->|"EXEC, block index"| CTRL3
        SCHED -.->|"block index"| MASK0
        SCHED -.->|"block index"| MASK1
        SCHED -.->|"block index"| MASK2
        SCHED -.->|"block index"| MASK3
        SCHED -.->|"blockIdx (r13)"| RF0
        SCHED -.->|"blockIdx (r13)"| RF1
        SCHED -.->|"blockIdx (r13)"| RF2
        SCHED -.->|"blockIdx (r13)"| RF3
        BLOCKDIM -.->|"blockDim (r14)"| RF0
        BLOCKDIM -.->|"blockDim (r14)"| RF1
        BLOCKDIM -.->|"blockDim (r14)"| RF2
        BLOCKDIM -.->|"blockDim (r14)"| RF3
        HOST -->|"start, thread count"| SCHED
        HOST <-->|"load program"| IMEM
        HOST <-->|"load inputs / read results"| DMEM
    end
```

Each lane contains the same basic datapath: a private register file, an
ALU, and a write-back mux. The decoder broadcasts the instruction fields
to every lane. The scheduler tells the lanes when to execute and which
block is running. Each lane's mask and write-enable logic prevents an
out-of-range lane from changing registers or storing data. All four lanes
connect to the shared data memory, while the host uses its separate
load/read interface.

The host in this project is going to be the testbench. It loads the
program into instruction memory and the arrays into data memory, starts the processor, waits for it to finish, and checks the answers.

## What is a lane?

A **lane** is one small worker. There are four lanes in the default core. Each lane has its own:

- **Register file:** small private storage for values the lane is using.
- **ALU:** calculator for add, subtract, and multiply (needed for vector addition). (alu.v file)
- **Write-back logic:** chooses which value to save in a register.

The lanes share the instruction stream and data memory. They receive the same operation and register numbers, but their register contents can differ.
That lets them execute the same instruction on different array elements at the same time.

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
