# =======================================================================
# uLisp Concurrency Runtime: System V AMD64 Native Context Switch (context.s)
# Conforms to DSN-37 Section 5, Section 7.3 & Phase 2 Task 2.1 (Issue #634)
# =======================================================================
# Provides:
#   1. swap_context(old_sp_ptr, new_sp) : Canonical 15-instruction System V
#      AMD64 callee-saved register context switch (rbp, rbx, r12-r15, rsp).
#   2. ulisp_task_entry_trampoline & ulisp_task_exit_trampoline :
#      16-byte ABI-aligned coroutine entry/exit trampolines with %r12 heap
#      frontier preservation.
#   3. Scheme runtime entrypoints (%asm-swap-context!, %asm-resume-task!,
#      %asm-yield-task!, %asm-switch-task!, %asm-get-trampoline-addr,
#      %asm-verify-swap-context-regs!, %asm-bench-swap-context!).
# =======================================================================

    .intel_syntax noprefix
    .text

# -----------------------------------------------------------------------
# 1. Canonical 15-Instruction System V AMD64 Context Switch
#    rdi = old_sp_ptr (uint64_t*)
#    rsi = new_sp     (uint64_t)
# -----------------------------------------------------------------------
    .globl swap_context
    .type swap_context, @function
    .p2align 4
swap_context:
    push rbp
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov [rdi], rsp
    mov rsp, rsi
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

# -----------------------------------------------------------------------
# 2. Task Entry & Exit Trampolines (16-Byte System V ABI Aligned)
# -----------------------------------------------------------------------
# Stack layout at first entry into ulisp_task_entry_trampoline:
#   rbx = top (16-byte aligned top of task stack / TCB header base)
#   r13 = task closure (tagged Scheme pair) or raw function pointer
#   r11 = live uLisp heap pointer (%r12 from caller)
#   rsp = frame_top - 8 (where [rsp] == ulisp_task_exit_trampoline, rsp % 16 == 8)
    .globl ulisp_task_entry_trampoline
    .type ulisp_task_entry_trampoline, @function
    .p2align 4
ulisp_task_entry_trampoline:
    mov r12, r11
    mov rax, r13
    and rax, 3
    cmp rax, 1
    jne .L_task_entry_raw_fn
    mov r10, r13
    xor rax, rax
    mov r11, [r10 - 1]
    push rbx
    call r11
    pop rbx
    mov [rbx - 40], rax
    ret
.L_task_entry_raw_fn:
    mov rdi, rbx
    push rbx
    call r13
    pop rbx
    mov [rbx - 40], rax
    ret

    .globl ulisp_task_exit_trampoline
    .type ulisp_task_exit_trampoline, @function
    .p2align 4
ulisp_task_exit_trampoline:
    mov qword ptr [rbx - 24], 3
    mov qword ptr [rbx - 32], 0
    mov rax, [rbx - 48]
    lea rdx, [rip + ulisp_gc_state]
    mov r8, r12
    sub r8, [rdx]
    shr r8, 25
    and r8, [rip + ulisp_thread_idx_mask]
    lea rdx, [rip + ulisp_current_task_top]
    mov [rdx + r8*8], rax
    inc qword ptr [rip + ulisp_total_context_switches]
    mov r11, r12
    lea rdi, [rbx - 16]
    mov rsi, [rbx - 8]
    and rsp, -16
    call swap_context
    ud2

# -----------------------------------------------------------------------
# 3. Scheme Primitives for Task Resume / Yield / P2P Switch
# -----------------------------------------------------------------------

# (%asm-get-trampoline-addr which)
#   which = 0 -> address of ulisp_task_entry_trampoline (tagged fixnum)
#   which = 1 -> address of ulisp_task_exit_trampoline  (tagged fixnum)
#   which = 2 -> address of swap_context                (tagged fixnum)
#   which = 3 -> ulisp_total_context_switches           (tagged fixnum)
#   which = 4 -> ulisp_current_task_top[worker]         (tagged fixnum)
#   which = 5 -> current worker TLS slot index (0..63)  (tagged fixnum)
#   which = 6 -> ulisp_handler_chain[worker]            (tagged fixnum)
    .globl ulisp_fn__pctasm_get_trampoline_addr
    .globl ulisp_fn___lib_ulisp_concurrency_context___pctasm_get_trampoline_addr
    .type ulisp_fn__pctasm_get_trampoline_addr, @function
    .p2align 4
ulisp_fn__pctasm_get_trampoline_addr:
ulisp_fn___lib_ulisp_concurrency_context___pctasm_get_trampoline_addr:
    sar rdi, 2
    cmp rdi, 0
    je .L_get_addr_entry
    cmp rdi, 1
    je .L_get_addr_exit
    cmp rdi, 2
    je .L_get_addr_swap
    cmp rdi, 3
    je .L_get_total_switches
    cmp rdi, 5
    je .L_get_worker_slot
    cmp rdi, 6
    je .L_get_handler_chain
    lea rdx, [rip + ulisp_gc_state]
    mov r8, r12
    sub r8, [rdx]
    shr r8, 25
    and r8, [rip + ulisp_thread_idx_mask]
    lea rax, [rip + ulisp_current_task_top]
    mov rax, [rax + r8*8]
    shl rax, 2
    ret
.L_get_worker_slot:
    lea rdx, [rip + ulisp_gc_state]
    mov rax, r12
    sub rax, [rdx]
    shr rax, 25
    and rax, [rip + ulisp_thread_idx_mask]
    shl rax, 2
    ret
.L_get_handler_chain:
    lea rdx, [rip + ulisp_gc_state]
    mov r8, r12
    sub r8, [rdx]
    shr r8, 25
    and r8, [rip + ulisp_thread_idx_mask]
    lea rax, [rip + ulisp_handler_chain]
    mov rax, [rax + r8*8]
    shl rax, 2
    ret
.L_get_addr_entry:
    lea rax, [rip + ulisp_task_entry_trampoline]
    shl rax, 2
    ret
.L_get_addr_exit:
    lea rax, [rip + ulisp_task_exit_trampoline]
    shl rax, 2
    ret
.L_get_addr_swap:
    lea rax, [rip + swap_context]
    shl rax, 2
    ret
.L_get_total_switches:
    lea rax, [rip + ulisp_total_context_switches]
    mov rax, [rax]
    shl rax, 2
    ret

# (%asm-set-handler-chain! chain-addr)
    .globl ulisp_fn__pctasm_set_handler_chain_excl
    .globl ulisp_fn___lib_ulisp_concurrency_context___pctasm_set_handler_chain_excl
    .type ulisp_fn__pctasm_set_handler_chain_excl, @function
    .p2align 4
ulisp_fn__pctasm_set_handler_chain_excl:
ulisp_fn___lib_ulisp_concurrency_context___pctasm_set_handler_chain_excl:
    sar rdi, 2
    lea rdx, [rip + ulisp_gc_state]
    mov r8, r12
    sub r8, [rdx]
    shr r8, 25
    and r8, [rip + ulisp_thread_idx_mask]
    lea r9, [rip + ulisp_handler_chain]
    mov [r9 + r8*8], rdi
    mov rax, 111
    ret

# (%asm-swap-context! old-sp-ptr new-sp)
    .globl ulisp_fn__pctasm_swap_context_excl
    .globl ulisp_fn___lib_ulisp_concurrency_context___pctasm_swap_context_excl
    .type ulisp_fn__pctasm_swap_context_excl, @function
    .p2align 4
ulisp_fn__pctasm_swap_context_excl:
ulisp_fn___lib_ulisp_concurrency_context___pctasm_swap_context_excl:
    sar rdi, 2
    sar rsi, 2
    inc qword ptr [rip + ulisp_total_context_switches]
    mov r11, r12
    sub rsp, 8
    call swap_context
    add rsp, 8
    mov r12, r11
    mov rax, 111
    ret

# (%asm-resume-task! top-addr send-val)
    .globl ulisp_fn__pctasm_resume_task_excl
    .globl ulisp_fn___lib_ulisp_concurrency_context___pctasm_resume_task_excl
    .type ulisp_fn__pctasm_resume_task_excl, @function
    .p2align 4
ulisp_fn__pctasm_resume_task_excl:
ulisp_fn___lib_ulisp_concurrency_context___pctasm_resume_task_excl:
    sar rdi, 2
    mov [rdi - 40], rsi
    mov qword ptr [rdi - 24], 1
    inc qword ptr [rdi - 56]
    inc qword ptr [rip + ulisp_total_context_switches]
    lea rdx, [rip + ulisp_gc_state]
    mov r8, r12
    sub r8, [rdx]
    shr r8, 25
    and r8, [rip + ulisp_thread_idx_mask]
    lea rdx, [rip + ulisp_current_task_top]
    mov rax, [rdx + r8*8]
    mov [rdi - 48], rax
    mov [rdx + r8*8], rdi
    lea r9, [rip + ulisp_handler_chain]
    lea r9, [r9 + r8*8]
    push qword ptr [r9]
    push r9
    mov rax, [rdi - 32]
    test rax, rax
    jz .L_resume_keep_handler
    mov [r9], rax
.L_resume_keep_handler:
    lea rcx, [rip + ulisp_gc_state]
    push qword ptr [rcx + 24]
    push qword ptr [rcx + 48]
    push rdi
    mov [rcx + 24], rdi
    mov [rcx + 48], rdi
    mov r11, r12
    mov rsi, [rdi - 16]
    lea rdi, [rdi - 8]
    call swap_context
    mov r12, r11
    pop rdi
    lea rcx, [rip + ulisp_gc_state]
    pop qword ptr [rcx + 48]
    pop qword ptr [rcx + 24]
    pop r9
    pop qword ptr [r9]
    mov rax, [rdi - 40]
    ret

# (%asm-yield-task! yield-val)
    .globl ulisp_fn__pctasm_yield_task_excl
    .globl ulisp_fn___lib_ulisp_concurrency_context___pctasm_yield_task_excl
    .type ulisp_fn__pctasm_yield_task_excl, @function
    .p2align 4
ulisp_fn__pctasm_yield_task_excl:
ulisp_fn___lib_ulisp_concurrency_context___pctasm_yield_task_excl:
    lea rdx, [rip + ulisp_gc_state]
    mov r8, r12
    sub r8, [rdx]
    shr r8, 25
    and r8, [rip + ulisp_thread_idx_mask]
    lea rdx, [rip + ulisp_current_task_top]
    mov rcx, [rdx + r8*8]
    test rcx, rcx
    jz .L_yield_no_active_task
    mov [rcx - 40], rdi
    mov qword ptr [rcx - 24], 2
    inc qword ptr [rip + ulisp_total_context_switches]
    mov rax, [rcx - 48]
    mov [rdx + r8*8], rax
    lea r9, [rip + ulisp_handler_chain]
    mov rax, [r9 + r8*8]
    mov [rcx - 32], rax
    push rcx
    mov r11, r12
    lea rdi, [rcx - 16]
    mov rsi, [rcx - 8]
    call swap_context
    mov r12, r11
    pop rcx
    mov rax, [rcx - 40]
    ret
.L_yield_no_active_task:
    mov rax, rdi
    ret

# (%asm-switch-task! from-top-addr to-top-addr send-val)
    .globl ulisp_fn__pctasm_switch_task_excl
    .globl ulisp_fn___lib_ulisp_concurrency_context___pctasm_switch_task_excl
    .type ulisp_fn__pctasm_switch_task_excl, @function
    .p2align 4
ulisp_fn__pctasm_switch_task_excl:
ulisp_fn___lib_ulisp_concurrency_context___pctasm_switch_task_excl:
    sar rdi, 2
    sar rsi, 2
    mov [rsi - 40], rdx
    mov qword ptr [rdi - 24], 2
    mov qword ptr [rsi - 24], 1
    inc qword ptr [rsi - 56]
    inc qword ptr [rip + ulisp_total_context_switches]
    mov rax, [rsi - 8]
    test rax, rax
    jnz .L_switch_parent_ready
    mov rax, [rdi - 8]
    mov [rsi - 8], rax
    mov rax, [rdi - 48]
    mov [rsi - 48], rax
.L_switch_parent_ready:
    lea rdx, [rip + ulisp_gc_state]
    mov r8, r12
    sub r8, [rdx]
    shr r8, 25
    and r8, [rip + ulisp_thread_idx_mask]
    lea rcx, [rip + ulisp_current_task_top]
    mov [rcx + r8*8], rsi
    lea r9, [rip + ulisp_handler_chain]
    mov rax, [r9 + r8*8]
    mov [rdi - 32], rax
    mov rax, [rsi - 32]
    test rax, rax
    jz .L_switch_keep_handler
    mov [r9 + r8*8], rax
.L_switch_keep_handler:
    lea rcx, [rip + ulisp_gc_state]
    mov [rcx + 24], rsi
    mov [rcx + 48], rsi
    push rdi
    mov r11, r12
    lea rdi, [rdi - 16]
    mov rsi, [rsi - 16]
    call swap_context
    mov r12, r11
    pop rdi
    lea rdx, [rip + ulisp_gc_state]
    mov r8, r12
    sub r8, [rdx]
    shr r8, 25
    and r8, [rip + ulisp_thread_idx_mask]
    lea rcx, [rip + ulisp_current_task_top]
    mov [rcx + r8*8], rdi
    lea r9, [rip + ulisp_handler_chain]
    mov rax, [rdi - 32]
    mov [r9 + r8*8], rax
    lea rcx, [rip + ulisp_gc_state]
    mov [rcx + 24], rdi
    mov [rcx + 48], rdi
    mov rax, [rdi - 40]
    ret

# -----------------------------------------------------------------------
# 4. System V AMD64 Callee-Saved Register & 16-Byte ABI Alignment Verifier
#    (%asm-verify-swap-context-regs! stack1-top stack2-top)
# -----------------------------------------------------------------------
    .globl ulisp_fn__pctasm_verify_swap_context_regs_excl
    .globl ulisp_fn___lib_ulisp_concurrency_context___pctasm_verify_swap_context_regs_excl
    .type ulisp_fn__pctasm_verify_swap_context_regs_excl, @function
    .p2align 4
ulisp_fn__pctasm_verify_swap_context_regs_excl:
ulisp_fn___lib_ulisp_concurrency_context___pctasm_verify_swap_context_regs_excl:
    push rbp
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 8

    sar rdi, 2
    sar rsi, 2
    mov qword ptr [rip + ulisp_verify_status], 0

    # Set up Task 1 stack frame at (stack1_top - 128)
    lea r8, [rdi - 64]
    lea rax, [rip + .L_verify_task1_entry]
    mov qword ptr [r8 - 8], 0
    mov [r8 - 16], rax
    mov rax, 0x1010101010101010
    mov [r8 - 24], rax
    mov rax, 0x2020202020202020
    mov [r8 - 32], rax
    mov rax, 0x3030303030303030
    mov [r8 - 40], rax
    mov rax, 0x4040404040404040
    mov [r8 - 48], rax
    mov rax, 0x5050505050505050
    mov [r8 - 56], rax
    mov rax, 0x6060606060606060
    mov [r8 - 64], rax
    lea rax, [r8 - 64]
    mov [rip + ulisp_verify_t1_sp], rax

    # Set up Task 2 stack frame at (stack2_top - 128)
    lea r9, [rsi - 64]
    lea rax, [rip + .L_verify_task2_entry]
    mov qword ptr [r9 - 8], 0
    mov [r9 - 16], rax
    mov rax, 0x1122334455667788
    mov [r9 - 24], rax
    mov rax, 0x2233445566778899
    mov [r9 - 32], rax
    mov rax, 0x33445566778899AA
    mov [r9 - 40], rax
    mov rax, 0x445566778899AABB
    mov [r9 - 48], rax
    mov rax, 0x5566778899AABBCC
    mov [r9 - 56], rax
    mov rax, 0x66778899AABBCCDD
    mov [r9 - 64], rax
    lea rax, [r9 - 64]
    mov [rip + ulisp_verify_t2_sp], rax

    # Switch from Host -> Task 1
    lea rdi, [rip + ulisp_verify_host_sp]
    mov rsi, [rip + ulisp_verify_t1_sp]
    call swap_context

    # Back in Host: check ulisp_verify_status == 1
    mov rax, [rip + ulisp_verify_status]
    cmp rax, 1
    mov rax, 47
    mov rdx, 111
    cmove rax, rdx

    add rsp, 8
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

    .p2align 4
.L_verify_task1_entry:
    # 1. Verify System V ABI 16-byte stack alignment at entry: (rsp + 8) % 16 == 0
    lea rax, [rsp + 8]
    and rax, 15
    jnz .L_verify_fail

    # 2. Verify initial 6 callee-saved registers for Task 1
    mov rax, 0x1010101010101010
    cmp rbp, rax
    jne .L_verify_fail
    mov rax, 0x2020202020202020
    cmp rbx, rax
    jne .L_verify_fail
    mov rax, 0x3030303030303030
    cmp r12, rax
    jne .L_verify_fail
    mov rax, 0x4040404040404040
    cmp r13, rax
    jne .L_verify_fail
    mov rax, 0x5050505050505050
    cmp r14, rax
    jne .L_verify_fail
    mov rax, 0x6060606060606060
    cmp r15, rax
    jne .L_verify_fail

    # 3. Load Task 1 round-2 canary values into all 6 registers
    mov rbp, 0x1A1A1A1A1A1A1A1A
    mov rbx, 0x2B2B2B2B2B2B2B2B
    mov r12, 0x3C3C3C3C3C3C3C3C
    mov r13, 0x4D4D4D4D4D4D4D4D
    mov r14, 0x5E5E5E5E5E5E5E5E
    mov r15, 0x6F6F6F6F6F6F6F6F

    # Switch Task 1 -> Task 2 (align stack to 16 bytes before call)
    sub rsp, 8
    lea rdi, [rip + ulisp_verify_t1_sp]
    mov rsi, [rip + ulisp_verify_t2_sp]
    call swap_context
    add rsp, 8

    # 4. Resumed in Task 1: verify ABI alignment and all 6 round-2 registers
    lea rax, [rsp + 8]
    and rax, 15
    jnz .L_verify_fail
    mov rax, 0x1A1A1A1A1A1A1A1A
    cmp rbp, rax
    jne .L_verify_fail
    mov rax, 0x2B2B2B2B2B2B2B2B
    cmp rbx, rax
    jne .L_verify_fail
    mov rax, 0x3C3C3C3C3C3C3C3C
    cmp r12, rax
    jne .L_verify_fail
    mov rax, 0x4D4D4D4D4D4D4D4D
    cmp r13, rax
    jne .L_verify_fail
    mov rax, 0x5E5E5E5E5E5E5E5E
    cmp r14, rax
    jne .L_verify_fail
    mov rax, 0x6F6F6F6F6F6F6F6F
    cmp r15, rax
    jne .L_verify_fail

    # Switch Task 1 -> Task 2 for final verification
    sub rsp, 8
    lea rdi, [rip + ulisp_verify_t1_sp]
    mov rsi, [rip + ulisp_verify_t2_sp]
    call swap_context
    add rsp, 8
    jmp .L_verify_fail

    .p2align 4
.L_verify_task2_entry:
    # 1. Verify System V ABI 16-byte stack alignment at entry: (rsp + 8) % 16 == 0
    lea rax, [rsp + 8]
    and rax, 15
    jnz .L_verify_fail

    # 2. Verify initial 6 callee-saved registers for Task 2
    mov rax, 0x1122334455667788
    cmp rbp, rax
    jne .L_verify_fail
    mov rax, 0x2233445566778899
    cmp rbx, rax
    jne .L_verify_fail
    mov rax, 0x33445566778899AA
    cmp r12, rax
    jne .L_verify_fail
    mov rax, 0x445566778899AABB
    cmp r13, rax
    jne .L_verify_fail
    mov rax, 0x5566778899AABBCC
    cmp r14, rax
    jne .L_verify_fail
    mov rax, 0x66778899AABBCCDD
    cmp r15, rax
    jne .L_verify_fail

    # 3. Load Task 2 round-2 canary values into all 6 registers
    mov rbp, 0x7171717171717171
    mov rbx, 0x7272727272727272
    mov r12, 0x7373737373737373
    mov r13, 0x7474747474747474
    mov r14, 0x7575757575757575
    mov r15, 0x7676767676767676

    # Switch Task 2 -> Task 1
    sub rsp, 8
    lea rdi, [rip + ulisp_verify_t2_sp]
    mov rsi, [rip + ulisp_verify_t1_sp]
    call swap_context
    add rsp, 8

    # 4. Resumed in Task 2: verify ABI alignment and all 6 round-2 registers
    lea rax, [rsp + 8]
    and rax, 15
    jnz .L_verify_fail
    mov rax, 0x7171717171717171
    cmp rbp, rax
    jne .L_verify_fail
    mov rax, 0x7272727272727272
    cmp rbx, rax
    jne .L_verify_fail
    mov rax, 0x7373737373737373
    cmp r12, rax
    jne .L_verify_fail
    mov rax, 0x7474747474747474
    cmp r13, rax
    jne .L_verify_fail
    mov rax, 0x7575757575757575
    cmp r14, rax
    jne .L_verify_fail
    mov rax, 0x7676767676767676
    cmp r15, rax
    jne .L_verify_fail

    # All checks passed! Record status = 1 and switch back to Host
    mov qword ptr [rip + ulisp_verify_status], 1
    add qword ptr [rip + ulisp_total_context_switches], 4
    sub rsp, 8
    lea rdi, [rip + ulisp_verify_t2_sp]
    mov rsi, [rip + ulisp_verify_host_sp]
    call swap_context
    ud2

.L_verify_fail:
    mov qword ptr [rip + ulisp_verify_status], 0
    sub rsp, 8
    lea rdi, [rip + ulisp_verify_t1_sp]
    mov rsi, [rip + ulisp_verify_host_sp]
    call swap_context
    ud2

# -----------------------------------------------------------------------
# 5. 10,000,000 Context Switches Endurance Benchmark & Stress Test
#    (%asm-bench-swap-context! stack1-top stack2-top total-switches)
# -----------------------------------------------------------------------
    .globl ulisp_fn__pctasm_bench_swap_context_excl
    .globl ulisp_fn___lib_ulisp_concurrency_context___pctasm_bench_swap_context_excl
    .type ulisp_fn__pctasm_bench_swap_context_excl, @function
    .p2align 4
ulisp_fn__pctasm_bench_swap_context_excl:
ulisp_fn___lib_ulisp_concurrency_context___pctasm_bench_swap_context_excl:
    push rbp
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 8

    sar rdi, 2
    sar rsi, 2
    sar rdx, 2
    shr rdx, 1
    mov qword ptr [rip + ulisp_bench_completed], 0

    # Prepare Task 1 stack at (stack1_top - 128)
    lea r8, [rdi - 64]
    lea rax, [rip + .L_bench_task1_entry]
    mov qword ptr [r8 - 8], 0
    mov [r8 - 16], rax
    mov rax, 0x1111111111111111
    mov [r8 - 24], rax
    mov [r8 - 32], rdi
    mov [r8 - 40], rsi
    mov qword ptr [r8 - 48], 0
    mov [r8 - 56], rdx
    mov rax, 0x5555555555555555
    mov [r8 - 64], rax
    lea rax, [r8 - 64]
    mov [rip + ulisp_verify_t1_sp], rax

    # Prepare Task 2 stack at (stack2_top - 128)
    lea r9, [rsi - 64]
    lea rax, [rip + .L_bench_task2_entry]
    mov qword ptr [r9 - 8], 0
    mov [r9 - 16], rax
    mov rax, 0x2222222222222222
    mov [r9 - 24], rax
    mov [r9 - 32], rsi
    mov [r9 - 40], rdi
    mov qword ptr [r9 - 48], 0
    mov [r9 - 56], rdx
    mov rax, 0x7777777777777777
    mov [r9 - 64], rax
    lea rax, [r9 - 64]
    mov [rip + ulisp_verify_t2_sp], rax

    # Enter Task 1
    lea rdi, [rip + ulisp_verify_host_sp]
    mov rsi, [rip + ulisp_verify_t1_sp]
    call swap_context

    # Returned to Host: return ulisp_bench_completed as tagged fixnum
    mov rax, [rip + ulisp_bench_completed]
    add [rip + ulisp_total_context_switches], rax
    shl rax, 2

    add rsp, 8
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

    .p2align 4
.L_bench_task1_entry:
    sub rsp, 8
.L_bench_task1_loop:
    inc r13
    lea rdi, [rip + ulisp_verify_t1_sp]
    mov rsi, [rip + ulisp_verify_t2_sp]
    call swap_context
    cmp r13, r14
    jb .L_bench_task1_loop

    # Verify Task 1 callee-saved canaries after 5,000,000 round-trips (10M switches)
    mov rax, 0x1111111111111111
    cmp rbp, rax
    jne .L_bench_corrupt
    mov rax, 0x5555555555555555
    cmp r15, rax
    jne .L_bench_corrupt

    # Switch back to Host
    lea rdi, [rip + ulisp_verify_t1_sp]
    mov rsi, [rip + ulisp_verify_host_sp]
    call swap_context
    ud2

    .p2align 4
.L_bench_task2_entry:
    sub rsp, 8
.L_bench_task2_loop:
    inc r13
    cmp r13, r14
    je .L_bench_task2_done
    lea rdi, [rip + ulisp_verify_t2_sp]
    mov rsi, [rip + ulisp_verify_t1_sp]
    call swap_context
    jmp .L_bench_task2_loop

.L_bench_task2_done:
    # Verify Task 2 callee-saved canaries after 5,000,000 round-trips
    mov rax, 0x2222222222222222
    cmp rbp, rax
    jne .L_bench_corrupt
    mov rax, 0x7777777777777777
    cmp r15, rax
    jne .L_bench_corrupt

    # Record total switches = r13 * 2 (10,000,000) and return to Task 1
    mov rax, r13
    shl rax, 1
    mov [rip + ulisp_bench_completed], rax
    lea rdi, [rip + ulisp_verify_t2_sp]
    mov rsi, [rip + ulisp_verify_t1_sp]
    call swap_context
    ud2

.L_bench_corrupt:
    mov qword ptr [rip + ulisp_bench_completed], -1
    lea rdi, [rip + ulisp_verify_t1_sp]
    mov rsi, [rip + ulisp_verify_host_sp]
    call swap_context
    ud2

# -----------------------------------------------------------------------
# 6. Static Context Switch State Variables (.bss)
# -----------------------------------------------------------------------
    .bss
    .p2align 3
    .globl ulisp_handler_chain
ulisp_handler_chain:
    .zero 512
    .globl ulisp_current_task_top
ulisp_current_task_top:
    .zero 512
    .globl ulisp_thread_idx_mask
    .weak ulisp_thread_idx_mask
ulisp_thread_idx_mask:
    .quad 0
    .globl ulisp_total_context_switches
ulisp_total_context_switches:
    .quad 0
ulisp_verify_host_sp:
    .quad 0
ulisp_verify_t1_sp:
    .quad 0
ulisp_verify_t2_sp:
    .quad 0
ulisp_verify_status:
    .quad 0
ulisp_bench_completed:
    .quad 0

    .section .note.GNU-stack,"",@progbits
