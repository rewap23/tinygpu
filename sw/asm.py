#!/usr/bin/env python3
"""
asm.py -- the tinygpu assembler (the "compiler backend" of this project)

(Helps to check each instruction in TinyGPU by hand)

Turns a .asm kernel into a .hex file of 16-bit machine words that the
testbench loads into instruction memory 

ARCITECTURE/FLOW: 
   vecadd.asm  ──asm.py──►  vecadd.hex  ──testbench loads it──►  instruction memory (imem.v)
   (text you write)         (16-bit numbers)                      (the GPU runs it)

Syntax
    ADD   rd, rs, rt        rd = rs + rt
    SUB   rd, rs, rt
    MUL   rd, rs, rt
    CONST rd, imm           rd = imm   (0..255)
    LDR   rd, rs            rd = mem[rs]
    STR   rs, rt            mem[rs] = rt
    NOP
    RET
Registers: r0..r15, or the aliases %blockIdx (r13), %blockDim (r14),
%threadIdx (r15). Comments start with ';'.

Usage:  python3 asm.py kernel.asm kernel.hex
"""
import sys 

OPCODES = {"NOP": 0, "ADD": 1, "SUB": 2, "MUL": 3,
           "CONST": 4, "LDR": 5, "STR": 6, "RET": 7}
ALIASES = {"%blockidx": 13, "%blockdim": 14, "%threadidx": 15}


def reg(tok, lineno):
    t = tok.lower()
    if t in ALIASES:
        return ALIASES[t]
    if t.startswith("r") and t[1:].isdigit() and 0 <= int(t[1:]) <= 15:
        return int(t[1:])
    sys.exit(f"line {lineno}: bad register '{tok}'")


def encode(op, rd=0, rs=0, rt=0):
    #  [15:12]=op  [11:8]=rd  [7:4]=rs  [3:0]=rt
    return (op << 12) | (rd << 8) | (rs << 4) | rt


def assemble(lines):
    words = []
    for n, raw in enumerate(lines, 1):
        text = raw.split(";")[0].strip()
        if not text:
            continue
        mnem, *rest = text.replace(",", " ").split()
        mnem = mnem.upper()
        if mnem not in OPCODES:
            sys.exit(f"line {n}: unknown instruction '{mnem}'")
        op = OPCODES[mnem]
        args = rest

        if mnem in ("ADD", "SUB", "MUL"):
            w = encode(op, reg(args[0], n), reg(args[1], n), reg(args[2], n))
        elif mnem == "CONST":
            imm = int(args[1], 0)
            if not 0 <= imm <= 255:
                sys.exit(f"line {n}: immediate {imm} out of range")
            w = (op << 12) | (reg(args[0], n) << 8) | imm
        elif mnem == "LDR":
            w = encode(op, rd=reg(args[0], n), rs=reg(args[1], n))
        elif mnem == "STR":
            w = encode(op, rs=reg(args[0], n), rt=reg(args[1], n))
        else:  # NOP, RET
            w = encode(op)
        words.append((w, text))
    return words


def main():
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    with open(sys.argv[1]) as f:
        words = assemble(f.readlines())
    with open(sys.argv[2], "w") as f:
        for i, (w, src) in enumerate(words):
            # $readmemh accepts // comments, so keep the source for reading
            f.write(f"{w:04x}  // {i:2d}: {src}\n")
    for i, (w, src) in enumerate(words):
        print(f"{i:2d}: {w:016b}  {w:04x}   {src}")


if __name__ == "__main__":
    main()
