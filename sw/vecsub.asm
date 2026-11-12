; vecsub.asm -- C[i] = A[i] - B[i]
;
; Memory layout (set by the host / testbench):
;     A at 0..7     B at 8..15     C at 16..23
;
; Every lane runs EVERY line below in the same cycle. Only r13/r15 differ
; per lane, so each lane ends up touching a different array element.

    MUL   r0, %blockIdx, %blockDim   ; r0 = blockIdx * blockDim
    ADD   r0, r0, %threadIdx         ; r0 = i  (global thread id)

    CONST r1, 0                      ; &A[0]
    CONST r2, 8                      ; &B[0]
    CONST r3, 16                     ; &C[0]

    ADD   r4, r1, r0                 ; r4 = &A[i]
    LDR   r4, r4                     ; r4 = A[i]
    ADD   r5, r2, r0                 ; r5 = &B[i]
    LDR   r5, r5                     ; r5 = B[i]
    SUB   r6, r4, r5                 ; r6 = A[i] - B[i]
    ADD   r7, r3, r0                 ; r7 = &C[i]
    STR   r7, r6                     ; C[i] = r6
    RET
