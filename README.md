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
