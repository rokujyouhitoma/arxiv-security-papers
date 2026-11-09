// =======================================================================
// uLisp Concurrency Runtime: ARM64 AAPCS64 Native Context Switch (context_aarch64.s)
// Conforms to DSN-37 Section 5, Section 7.3 & Issue #692
// =======================================================================
// Provides:
//   1. swap_context(old_sp_ptr, new_sp) : Canonical 17-instruction AAPCS64
//      callee-saved register context switch (x19-x28, x29/fp, x30/lr, sp).
//   2. ulisp_task_entry_trampoline & ulisp_task_exit_trampoline :
//      Strict 16-byte AAPCS64-aligned coroutine entry/exit trampolines with
//      %x19 heap frontier preservation.
//   3. Scheme runtime entrypoints (%asm-swap-context!, %asm-resume-task!,
//      %asm-yield-task!, %asm-switch-task!, %asm-get-trampoline-addr,
//      %asm-verify-swap-context-regs!, %asm-bench-swap-context!).
// =======================================================================

    .text
    .p2align 4

// -----------------------------------------------------------------------
// Worker TLS Initialization & Resilience (TPIDR_EL0)
// -----------------------------------------------------------------------

    .globl ulisp_init_worker_tls
    .weak ulisp_init_worker_tls
    .globl ulisp_fn__pctinit_worker_tls
    .weak ulisp_fn__pctinit_worker_tls
    .globl ulisp_fn__pctsys_init_worker_tls
    .weak ulisp_fn__pctsys_init_worker_tls
    .type ulisp_init_worker_tls, %function
    .p2align 4
ulisp_init_worker_tls:
ulisp_fn__pctinit_worker_tls:
ulisp_fn__pctsys_init_worker_tls:
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    adrp x0, ulisp_tls_initialized
    ldr x1, [x0, :lo12:ulisp_tls_initialized]
    cmp x1, #1
    b.eq .L_tls_already_inited

    // Initialize Worker 0 slot in ulisp_worker_tls_table
    adrp x0, ulisp_worker_tls_table
    add x0, x0, :lo12:ulisp_worker_tls_table
    str xzr, [x0]
    msr tpidr_el0, x0

    adrp x0, ulisp_tls_initialized
    mov x1, #1
    str x1, [x0, :lo12:ulisp_tls_initialized]

.L_tls_already_inited:
    mov x0, #111   // SCHEME_TRUE
    ldp x29, x30, [sp], #16
    ret

// -----------------------------------------------------------------------
// 1. Canonical 17-Instruction ARM64 AAPCS64 Context Switch
//    x0 = old_sp_ptr (uint64_t*)
//    x1 = new_sp     (uint64_t)
// -----------------------------------------------------------------------
    .globl swap_context
    .type swap_context, %function
    .p2align 4
swap_context:
    sub sp, sp, #96
    stp x19, x20, [sp, #0]
    stp x21, x22, [sp, #16]
    stp x23, x24, [sp, #32]
    stp x25, x26, [sp, #48]
    stp x27, x28, [sp, #64]
    stp x29, x30, [sp, #80]
    mov x2, sp
    str x2, [x0]
    mov sp, x1
    ldp x19, x20, [sp, #0]
    ldp x21, x22, [sp, #16]
    ldp x23, x24, [sp, #32]
    ldp x25, x26, [sp, #48]
    ldp x27, x28, [sp, #64]
    ldp x29, x30, [sp, #80]
    add sp, sp, #96
    ret

// -----------------------------------------------------------------------
// 2. Task Entry & Exit Trampolines (16-Byte AAPCS64 ABI Aligned)
// -----------------------------------------------------------------------
// Stack layout at first entry into ulisp_task_entry_trampoline:
//   x19 = live uLisp heap pointer (preserved from caller)
//   x20 = top (16-byte aligned top of task stack / TCB header base)
//   x21 = task closure (tagged Scheme pair) or raw function pointer
//   sp  = frame_top (sp % 16 == 0)
    .globl ulisp_task_entry_trampoline
    .type ulisp_task_entry_trampoline, %function
    .p2align 4
ulisp_task_entry_trampoline:
    mov x19, x11
    and x0, x21, #3
    cmp x0, #1
    b.ne .L_task_entry_raw_fn

    // Scheme Closure: tag == 1
    mov x10, x21
    mov x7, #0
    ldr x1, [x10, #-1]
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    blr x1
    ldp x29, x30, [sp], #16
    str x0, [x20, #-40]
    b ulisp_task_exit_trampoline

.L_task_entry_raw_fn:
    mov x0, x20
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    blr x21
    ldp x29, x30, [sp], #16
    str x0, [x20, #-40]
    b ulisp_task_exit_trampoline

    .globl ulisp_task_exit_trampoline
    .type ulisp_task_exit_trampoline, %function
    .p2align 4
ulisp_task_exit_trampoline:
    adrp x0, ulisp_tls_initialized
    ldr x1, [x0, :lo12:ulisp_tls_initialized]
    cmp x1, #1
    b.eq 1f
    bl ulisp_init_worker_tls
1:
    // Mark task state = 3 ('terminated)
    mov x1, #3
    str x1, [x20, #-24]
    // Clear handler chain slot
    str xzr, [x20, #-32]

    // Restore parent task top to ulisp_current_task_top[worker]
    ldr x2, [x20, #-48]
    mrs x3, tpidr_el0
    cbz x3, 2f
    ldr x3, [x3]
    and x3, x3, #63
2:
    adrp x4, ulisp_current_task_top
    add x4, x4, :lo12:ulisp_current_task_top
    str x2, [x4, x3, lsl #3]

    // Increment context switch counter
    adrp x5, ulisp_total_context_switches
    ldr x6, [x5, :lo12:ulisp_total_context_switches]
    add x6, x6, #1
    str x6, [x5, :lo12:ulisp_total_context_switches]

    // Switch context back to parent
    sub x0, x20, #16
    ldr x1, [x20, #-8]
    mov x2, sp
    bic x2, x2, #15
    mov sp, x2
    mov x11, x19
    bl swap_context

.L_exit_hang:
    wfi
    b .L_exit_hang

// -----------------------------------------------------------------------
// 3. Scheme Primitives for Task Resume / Yield / P2P Switch
// -----------------------------------------------------------------------

// (%asm-get-trampoline-addr which)
//   which = 0 -> address of ulisp_task_entry_trampoline (tagged fixnum)
//   which = 1 -> address of ulisp_task_exit_trampoline  (tagged fixnum)
//   which = 2 -> address of swap_context                (tagged fixnum)
//   which = 3 -> ulisp_total_context_switches           (tagged fixnum)
//   which = 4 -> ulisp_current_task_top[worker]         (tagged fixnum)
//   which = 5 -> current worker TLS slot index (0..63)  (tagged fixnum)
//   which = 6 -> ulisp_handler_chain[worker]            (tagged fixnum)
//   which = 7 -> context frame size (96 on AArch64)    (tagged fixnum)
    .globl ulisp_fn__pctasm_get_trampoline_addr
    .globl ulisp_fn___lib_ulisp_concurrency_context___pctasm_get_trampoline_addr
    .type ulisp_fn__pctasm_get_trampoline_addr, %function
    .p2align 4
ulisp_fn__pctasm_get_trampoline_addr:
ulisp_fn___lib_ulisp_concurrency_context___pctasm_get_trampoline_addr:
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    adrp x1, ulisp_tls_initialized
    ldr x2, [x1, :lo12:ulisp_tls_initialized]
    cmp x2, #1
    b.eq 1f
    stp x0, xzr, [sp, #-16]!
    bl ulisp_init_worker_tls
    ldp x0, xzr, [sp], #16
1:
    asr x0, x0, #2
    cmp x0, #0
    b.eq .L_get_addr_entry
    cmp x0, #1
    b.eq .L_get_addr_exit
    cmp x0, #2
    b.eq .L_get_addr_swap
    cmp x0, #3
    b.eq .L_get_total_switches
    cmp x0, #5
    b.eq .L_get_worker_slot
    cmp x0, #6
    b.eq .L_get_handler_chain
    cmp x0, #7
    b.eq .L_get_frame_size

    // Default (which = 4): ulisp_current_task_top[worker]
    mrs x1, tpidr_el0
    cbz x1, 2f
    ldr x1, [x1]
    and x1, x1, #63
2:
    adrp x2, ulisp_current_task_top
    add x2, x2, :lo12:ulisp_current_task_top
    ldr x0, [x2, x1, lsl #3]
    lsl x0, x0, #2
    ldp x29, x30, [sp], #16
    ret

.L_get_frame_size:
    mov x0, #96
    lsl x0, x0, #2
    ldp x29, x30, [sp], #16
    ret

.L_get_worker_slot:
    mrs x1, tpidr_el0
    cbz x1, 2f
    ldr x1, [x1]
    and x1, x1, #63
2:
    mov x0, x1
    lsl x0, x0, #2
    ldp x29, x30, [sp], #16
    ret

.L_get_handler_chain:
    mrs x1, tpidr_el0
    cbz x1, 2f
    ldr x1, [x1]
    and x1, x1, #63
2:
    adrp x2, ulisp_handler_chain
    add x2, x2, :lo12:ulisp_handler_chain
    ldr x0, [x2, x1, lsl #3]
    lsl x0, x0, #2
    ldp x29, x30, [sp], #16
    ret

.L_get_addr_entry:
    adrp x0, ulisp_task_entry_trampoline
    add x0, x0, :lo12:ulisp_task_entry_trampoline
    lsl x0, x0, #2
    ldp x29, x30, [sp], #16
    ret

.L_get_addr_exit:
    adrp x0, ulisp_task_exit_trampoline
    add x0, x0, :lo12:ulisp_task_exit_trampoline
    lsl x0, x0, #2
    ldp x29, x30, [sp], #16
    ret

.L_get_addr_swap:
    adrp x0, swap_context
    add x0, x0, :lo12:swap_context
    lsl x0, x0, #2
    ldp x29, x30, [sp], #16
    ret

.L_get_total_switches:
    adrp x1, ulisp_total_context_switches
    ldr x0, [x1, :lo12:ulisp_total_context_switches]
    lsl x0, x0, #2
    ldp x29, x30, [sp], #16
    ret

// (%asm-set-handler-chain! chain-addr)
    .globl ulisp_fn__pctasm_set_handler_chain_excl
    .globl ulisp_fn___lib_ulisp_concurrency_context___pctasm_set_handler_chain_excl
    .type ulisp_fn__pctasm_set_handler_chain_excl, %function
    .p2align 4
ulisp_fn__pctasm_set_handler_chain_excl:
ulisp_fn___lib_ulisp_concurrency_context___pctasm_set_handler_chain_excl:
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    adrp x1, ulisp_tls_initialized
    ldr x2, [x1, :lo12:ulisp_tls_initialized]
    cmp x2, #1
    b.eq 1f
    stp x0, xzr, [sp, #-16]!
    bl ulisp_init_worker_tls
    ldp x0, xzr, [sp], #16
1:
    asr x0, x0, #2
    mrs x1, tpidr_el0
    cbz x1, 2f
    ldr x1, [x1]
    and x1, x1, #63
2:
    adrp x2, ulisp_handler_chain
    add x2, x2, :lo12:ulisp_handler_chain
    str x0, [x2, x1, lsl #3]
    mov x0, #111   // #t
    ldp x29, x30, [sp], #16
    ret

// (%asm-swap-context! old-sp-ptr new-sp)
    .globl ulisp_fn__pctasm_swap_context_excl
    .globl ulisp_fn___lib_ulisp_concurrency_context___pctasm_swap_context_excl
    .type ulisp_fn__pctasm_swap_context_excl, %function
    .p2align 4
ulisp_fn__pctasm_swap_context_excl:
ulisp_fn___lib_ulisp_concurrency_context___pctasm_swap_context_excl:
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    asr x0, x0, #2
    asr x1, x1, #2
    adrp x2, ulisp_total_context_switches
    ldr x3, [x2, :lo12:ulisp_total_context_switches]
    add x3, x3, #1
    str x3, [x2, :lo12:ulisp_total_context_switches]
    mov x11, x19
    bl swap_context
    mov x19, x11
    mov x0, #111   // #t
    ldp x29, x30, [sp], #16
    ret

// (%asm-resume-task! top-addr send-val)
    .globl ulisp_fn__pctasm_resume_task_excl
    .globl ulisp_fn___lib_ulisp_concurrency_context___pctasm_resume_task_excl
    .type ulisp_fn__pctasm_resume_task_excl, %function
    .p2align 4
ulisp_fn__pctasm_resume_task_excl:
ulisp_fn___lib_ulisp_concurrency_context___pctasm_resume_task_excl:
    stp x29, x30, [sp, #-16]!
    mov x29, sp

    adrp x2, ulisp_tls_initialized
    ldr x3, [x2, :lo12:ulisp_tls_initialized]
    cmp x3, #1
    b.eq 1f
    stp x0, x1, [sp, #-16]!
    bl ulisp_init_worker_tls
    ldp x0, x1, [sp], #16
1:
    asr x0, x0, #2
    str x1, [x0, #-40]
    mov x2, #1
    str x2, [x0, #-24]
    ldr x3, [x0, #-56]
    add x3, x3, #1
    str x3, [x0, #-56]

    adrp x4, ulisp_total_context_switches
    ldr x5, [x4, :lo12:ulisp_total_context_switches]
    add x5, x5, #1
    str x5, [x4, :lo12:ulisp_total_context_switches]

    mrs x6, tpidr_el0
    cbz x6, 2f
    ldr x6, [x6]
    and x6, x6, #63
2:
    adrp x7, ulisp_current_task_top
    add x7, x7, :lo12:ulisp_current_task_top
    ldr x8, [x7, x6, lsl #3]
    str x8, [x0, #-48]
    str x0, [x7, x6, lsl #3]

    // Handler chain stitching
    adrp x9, ulisp_handler_chain
    add x9, x9, :lo12:ulisp_handler_chain
    add x9, x9, x6, lsl #3
    ldr x10, [x9]
    stp x9, x10, [sp, #-16]!

    ldr x11, [x0, #-32]
    cbz x11, .L_resume_keep_handler

    mov x12, x11
.L_resume_stitch_loop:
    ldr x13, [x12]
    cbz x13, .L_resume_found_tail
    sub x14, x0, #65536
    cmp x13, x14
    b.lo .L_resume_found_tail
    cmp x13, x0
    b.hs .L_resume_found_tail
    mov x12, x13
    b .L_resume_stitch_loop
.L_resume_found_tail:
    str x10, [x12]
    str x11, [x9]

.L_resume_keep_handler:
    adrp x15, ulisp_gc_state
    add x15, x15, :lo12:ulisp_gc_state
    ldr x16, [x15, #24]
    ldr x17, [x15, #48]
    stp x16, x17, [sp, #-16]!
    stp x0, xzr, [sp, #-16]!
    str x0, [x15, #24]
    str x0, [x15, #48]

    // Call swap_context(&parent_sp, task_sp)
    ldr x1, [x0, #-16]
    sub x0, x0, #8
    mov x11, x19
    bl swap_context
    mov x19, x11

    ldp x0, xzr, [sp], #16
    adrp x15, ulisp_gc_state
    add x15, x15, :lo12:ulisp_gc_state
    ldp x16, x17, [sp], #16
    str x16, [x15, #24]
    str x17, [x15, #48]

    ldp x9, x10, [sp], #16
    str x10, [x9]

    ldr x0, [x0, #-40]
    ldp x29, x30, [sp], #16
    ret

// (%asm-yield-task! yield-val)
    .globl ulisp_fn__pctasm_yield_task_excl
    .globl ulisp_fn___lib_ulisp_concurrency_context___pctasm_yield_task_excl
    .type ulisp_fn__pctasm_yield_task_excl, %function
    .p2align 4
ulisp_fn__pctasm_yield_task_excl:
ulisp_fn___lib_ulisp_concurrency_context___pctasm_yield_task_excl:
    stp x29, x30, [sp, #-16]!
    mov x29, sp

    adrp x2, ulisp_tls_initialized
    ldr x3, [x2, :lo12:ulisp_tls_initialized]
    cmp x3, #1
    b.eq 1f
    stp x0, xzr, [sp, #-16]!
    bl ulisp_init_worker_tls
    ldp x0, xzr, [sp], #16
1:
    mrs x1, tpidr_el0
    cbz x1, 2f
    ldr x1, [x1]
    and x1, x1, #63
2:
    adrp x2, ulisp_current_task_top
    add x2, x2, :lo12:ulisp_current_task_top
    ldr x3, [x2, x1, lsl #3]
    cbz x3, .L_yield_no_active_task

    str x0, [x3, #-40]
    mov x4, #2
    str x4, [x3, #-24]

    adrp x5, ulisp_total_context_switches
    ldr x6, [x5, :lo12:ulisp_total_context_switches]
    add x6, x6, #1
    str x6, [x5, :lo12:ulisp_total_context_switches]

    ldr x7, [x3, #-48]
    str x7, [x2, x1, lsl #3]

    adrp x8, ulisp_handler_chain
    add x8, x8, :lo12:ulisp_handler_chain
    ldr x9, [x8, x1, lsl #3]
    sub x10, x3, #65536
    cmp x9, x10
    b.lo .L_yield_no_local_handler
    cmp x9, x3
    b.hs .L_yield_no_local_handler

    mov x11, x9
.L_yield_prune_loop:
    ldr x12, [x11]
    cbz x12, .L_yield_chain_pruned
    cmp x12, x10
    b.lo .L_yield_cut_link
    cmp x12, x3
    b.hs .L_yield_cut_link
    mov x11, x12
    b .L_yield_prune_loop
.L_yield_cut_link:
    str xzr, [x11]
.L_yield_chain_pruned:
    str x9, [x3, #-32]
    b .L_yield_handler_done

.L_yield_no_local_handler:
    str xzr, [x3, #-32]

.L_yield_handler_done:
    stp x3, xzr, [sp, #-16]!
    ldr x1, [x3, #-8]
    sub x0, x3, #16
    mov x11, x19
    bl swap_context
    mov x19, x11
    ldp x3, xzr, [sp], #16

    ldr x0, [x3, #-40]
    ldp x29, x30, [sp], #16
    ret

.L_yield_no_active_task:
    ldp x29, x30, [sp], #16
    ret

// (%asm-switch-task! from-top-addr to-top-addr send-val)
    .globl ulisp_fn__pctasm_switch_task_excl
    .globl ulisp_fn___lib_ulisp_concurrency_context___pctasm_switch_task_excl
    .type ulisp_fn__pctasm_switch_task_excl, %function
    .p2align 4
ulisp_fn__pctasm_switch_task_excl:
ulisp_fn___lib_ulisp_concurrency_context___pctasm_switch_task_excl:
    stp x29, x30, [sp, #-16]!
    mov x29, sp

    adrp x3, ulisp_tls_initialized
    ldr x4, [x3, :lo12:ulisp_tls_initialized]
    cmp x4, #1
    b.eq 1f
    stp x0, x1, [sp, #-16]!
    stp x2, xzr, [sp, #-16]!
    bl ulisp_init_worker_tls
    ldp x2, xzr, [sp], #16
    ldp x0, x1, [sp], #16
1:
    asr x0, x0, #2
    asr x1, x1, #2

    str x2, [x1, #-40]
    mov x3, #2
    str x3, [x0, #-24]
    mov x4, #1
    str x4, [x1, #-24]
    ldr x5, [x1, #-56]
    add x5, x5, #1
    str x5, [x1, #-56]

    adrp x6, ulisp_total_context_switches
    ldr x7, [x6, :lo12:ulisp_total_context_switches]
    add x7, x7, #1
    str x7, [x6, :lo12:ulisp_total_context_switches]

    ldr x8, [x1, #-8]
    cbnz x8, .L_switch_parent_ready
    ldr x9, [x0, #-8]
    str x9, [x1, #-8]
    ldr x10, [x0, #-48]
    str x10, [x1, #-48]

.L_switch_parent_ready:
    mrs x11, tpidr_el0
    cbz x11, 2f
    ldr x11, [x11]
    and x11, x11, #63
2:
    adrp x12, ulisp_current_task_top
    add x12, x12, :lo12:ulisp_current_task_top
    str x1, [x12, x11, lsl #3]

    adrp x13, ulisp_handler_chain
    add x13, x13, :lo12:ulisp_handler_chain
    add x13, x13, x11, lsl #3
    ldr x14, [x13]

    sub x15, x0, #65536
    cmp x14, x15
    b.lo .L_switch_no_local_from
    cmp x14, x0
    b.hs .L_switch_no_local_from
    mov x16, x14
.L_switch_prune_from:
    ldr x17, [x16]
    cbz x17, .L_switch_pruned_from
    cmp x17, x15
    b.lo .L_switch_cut_from
    cmp x17, x0
    b.hs .L_switch_cut_from
    mov x16, x17
    b .L_switch_prune_from
.L_switch_cut_from:
    str xzr, [x16]
.L_switch_pruned_from:
    str x14, [x0, #-32]
    b .L_switch_check_to

.L_switch_no_local_from:
    str xzr, [x0, #-32]

.L_switch_check_to:
    ldr x14, [x1, #-32]
    cbz x14, .L_switch_keep_handler
    mov x16, x14
    ldr x17, [x13]
.L_switch_stitch_to:
    ldr x18, [x16]
    cbz x18, .L_switch_found_tail_to
    sub x15, x1, #65536
    cmp x18, x15
    b.lo .L_switch_found_tail_to
    cmp x18, x1
    b.hs .L_switch_found_tail_to
    mov x16, x18
    b .L_switch_stitch_to
.L_switch_found_tail_to:
    str x17, [x16]
    str x14, [x13]

.L_switch_keep_handler:
    adrp x15, ulisp_gc_state
    add x15, x15, :lo12:ulisp_gc_state
    str x1, [x15, #24]
    str x1, [x15, #48]

    stp x0, xzr, [sp, #-16]!
    ldr x1, [x1, #-16]
    sub x0, x0, #16
    mov x11, x19
    bl swap_context
    mov x19, x11
    ldp x0, xzr, [sp], #16

    mrs x11, tpidr_el0
    cbz x11, 3f
    ldr x11, [x11]
    and x11, x11, #63
3:
    adrp x12, ulisp_current_task_top
    add x12, x12, :lo12:ulisp_current_task_top
    str x0, [x12, x11, lsl #3]

    adrp x13, ulisp_handler_chain
    add x13, x13, :lo12:ulisp_handler_chain
    add x13, x13, x11, lsl #3
    ldr x14, [x0, #-32]
    cbz x14, .L_switch_back_keep_handler
    mov x16, x14
    ldr x17, [x13]
.L_switch_stitch_back:
    ldr x18, [x16]
    cbz x18, .L_switch_found_tail_back
    sub x15, x0, #65536
    cmp x18, x15
    b.lo .L_switch_found_tail_back
    cmp x18, x0
    b.hs .L_switch_found_tail_back
    mov x16, x18
    b .L_switch_stitch_back
.L_switch_found_tail_back:
    str x17, [x16]
    str x14, [x13]

.L_switch_back_keep_handler:
    adrp x15, ulisp_gc_state
    add x15, x15, :lo12:ulisp_gc_state
    str x0, [x15, #24]
    str x0, [x15, #48]

    ldr x0, [x0, #-40]
    ldp x29, x30, [sp], #16
    ret

// -----------------------------------------------------------------------
// 4. ARM64 AAPCS64 Callee-Saved Register & 16-Byte ABI Alignment Verifier
//    (%asm-verify-swap-context-regs! stack1-top stack2-top)
// -----------------------------------------------------------------------
    .globl ulisp_fn__pctasm_verify_swap_context_regs_excl
    .globl ulisp_fn___lib_ulisp_concurrency_context___pctasm_verify_swap_context_regs_excl
    .type ulisp_fn__pctasm_verify_swap_context_regs_excl, %function
    .p2align 4
ulisp_fn__pctasm_verify_swap_context_regs_excl:
ulisp_fn___lib_ulisp_concurrency_context___pctasm_verify_swap_context_regs_excl:
    sub sp, sp, #96
    stp x19, x20, [sp, #0]
    stp x21, x22, [sp, #16]
    stp x23, x24, [sp, #32]
    stp x25, x26, [sp, #48]
    stp x27, x28, [sp, #64]
    stp x29, x30, [sp, #80]

    asr x0, x0, #2
    asr x1, x1, #2

    adrp x2, ulisp_verify_status
    str xzr, [x2, :lo12:ulisp_verify_status]

    // Set up Task 1 stack frame at (stack1_top - 160)
    sub x8, x0, #160
    ldr x3, =0x1919191919191919
    str x3, [x8, #0]
    ldr x3, =0x2020202020202020
    str x3, [x8, #8]
    ldr x3, =0x2121212121212121
    str x3, [x8, #16]
    ldr x3, =0x2222222222222222
    str x3, [x8, #24]
    ldr x3, =0x2323232323232323
    str x3, [x8, #32]
    ldr x3, =0x2424242424242424
    str x3, [x8, #40]
    ldr x3, =0x2525252525252525
    str x3, [x8, #48]
    ldr x3, =0x2626262626262626
    str x3, [x8, #56]
    ldr x3, =0x2727272727272727
    str x3, [x8, #64]
    ldr x3, =0x2828282828282828
    str x3, [x8, #72]
    ldr x3, =0x2929292929292929
    str x3, [x8, #80]
    adrp x3, .L_verify_task1_entry
    add x3, x3, :lo12:.L_verify_task1_entry
    str x3, [x8, #88]

    adrp x4, ulisp_verify_t1_sp
    str x8, [x4, :lo12:ulisp_verify_t1_sp]

    // Set up Task 2 stack frame at (stack2_top - 160)
    sub x9, x1, #160
    ldr x3, =0x1122334455667788
    str x3, [x9, #0]
    ldr x3, =0x2233445566778899
    str x3, [x9, #8]
    ldr x3, =0x33445566778899AA
    str x3, [x9, #16]
    ldr x3, =0x445566778899AABB
    str x3, [x9, #24]
    ldr x3, =0x5566778899AABBCC
    str x3, [x9, #32]
    ldr x3, =0x66778899AABBCCDD
    str x3, [x9, #40]
    ldr x3, =0x778899AABBCCDDEE
    str x3, [x9, #48]
    ldr x3, =0x8899AABBCCDDEEFF
    str x3, [x9, #56]
    ldr x3, =0x99AABBCCDDEEFF00
    str x3, [x9, #64]
    ldr x3, =0xAABBCCDDEEFF0011
    str x3, [x9, #72]
    ldr x3, =0xBBCCDDEEFF001122
    str x3, [x9, #80]
    adrp x3, .L_verify_task2_entry
    add x3, x3, :lo12:.L_verify_task2_entry
    str x3, [x9, #88]

    adrp x4, ulisp_verify_t2_sp
    str x9, [x4, :lo12:ulisp_verify_t2_sp]

    // Switch from Host -> Task 1
    adrp x0, ulisp_verify_host_sp
    add x0, x0, :lo12:ulisp_verify_host_sp
    adrp x1, ulisp_verify_t1_sp
    ldr x1, [x1, :lo12:ulisp_verify_t1_sp]
    bl swap_context

    // Back in Host: check ulisp_verify_status == 1
    adrp x2, ulisp_verify_status
    ldr x3, [x2, :lo12:ulisp_verify_status]
    cmp x3, #1
    mov x0, #47    // #f
    mov x1, #111   // #t
    csel x0, x1, x0, eq

    ldp x19, x20, [sp, #0]
    ldp x21, x22, [sp, #16]
    ldp x23, x24, [sp, #32]
    ldp x25, x26, [sp, #48]
    ldp x27, x28, [sp, #64]
    ldp x29, x30, [sp, #80]
    add sp, sp, #96
    ret

    .p2align 4
.L_verify_task1_entry:
    // 1. Verify 16-byte SP alignment: sp % 16 == 0
    mov x0, sp
    and x0, x0, #15
    cbnz x0, .L_verify_fail

    // 2. Verify all initial 11 callee-saved registers for Task 1
    ldr x0, =0x1919191919191919; cmp x19, x0; b.ne .L_verify_fail
    ldr x0, =0x2020202020202020; cmp x20, x0; b.ne .L_verify_fail
    ldr x0, =0x2121212121212121; cmp x21, x0; b.ne .L_verify_fail
    ldr x0, =0x2222222222222222; cmp x22, x0; b.ne .L_verify_fail
    ldr x0, =0x2323232323232323; cmp x23, x0; b.ne .L_verify_fail
    ldr x0, =0x2424242424242424; cmp x24, x0; b.ne .L_verify_fail
    ldr x0, =0x2525252525252525; cmp x25, x0; b.ne .L_verify_fail
    ldr x0, =0x2626262626262626; cmp x26, x0; b.ne .L_verify_fail
    ldr x0, =0x2727272727272727; cmp x27, x0; b.ne .L_verify_fail
    ldr x0, =0x2828282828282828; cmp x28, x0; b.ne .L_verify_fail
    ldr x0, =0x2929292929292929; cmp x29, x0; b.ne .L_verify_fail

    // 3. Load Task 1 round-2 canary values into all 11 registers
    ldr x19, =0x1A1A1A1A1A1A1A1A
    ldr x20, =0x2B2B2B2B2B2B2B2B
    ldr x21, =0x3C3C3C3C3C3C3C3C
    ldr x22, =0x4D4D4D4D4D4D4D4D
    ldr x23, =0x5E5E5E5E5E5E5E5E
    ldr x24, =0x6F6F6F6F6F6F6F6F
    ldr x25, =0x7A7A7A7A7A7A7A7A
    ldr x26, =0x8B8B8B8B8B8B8B8B
    ldr x27, =0x9C9C9C9C9C9C9C9C
    ldr x28, =0xADADADADADADADAD
    ldr x29, =0xBEBEBEBEBEBEBEBE

    // Switch Task 1 -> Task 2
    adrp x0, ulisp_verify_t1_sp
    add x0, x0, :lo12:ulisp_verify_t1_sp
    adrp x1, ulisp_verify_t2_sp
    ldr x1, [x1, :lo12:ulisp_verify_t2_sp]
    bl swap_context

    // 4. Resumed in Task 1: verify SP alignment and round-2 registers
    mov x0, sp
    and x0, x0, #15
    cbnz x0, .L_verify_fail
    ldr x0, =0x1A1A1A1A1A1A1A1A; cmp x19, x0; b.ne .L_verify_fail
    ldr x0, =0x2B2B2B2B2B2B2B2B; cmp x20, x0; b.ne .L_verify_fail
    ldr x0, =0x3C3C3C3C3C3C3C3C; cmp x21, x0; b.ne .L_verify_fail
    ldr x0, =0x4D4D4D4D4D4D4D4D; cmp x22, x0; b.ne .L_verify_fail
    ldr x0, =0x5E5E5E5E5E5E5E5E; cmp x23, x0; b.ne .L_verify_fail
    ldr x0, =0x6F6F6F6F6F6F6F6F; cmp x24, x0; b.ne .L_verify_fail
    ldr x0, =0x7A7A7A7A7A7A7A7A; cmp x25, x0; b.ne .L_verify_fail
    ldr x0, =0x8B8B8B8B8B8B8B8B; cmp x26, x0; b.ne .L_verify_fail
    ldr x0, =0x9C9C9C9C9C9C9C9C; cmp x27, x0; b.ne .L_verify_fail
    ldr x0, =0xADADADADADADADAD; cmp x28, x0; b.ne .L_verify_fail
    ldr x0, =0xBEBEBEBEBEBEBEBE; cmp x29, x0; b.ne .L_verify_fail

    // Switch Task 1 -> Task 2 for final verification
    adrp x0, ulisp_verify_t1_sp
    add x0, x0, :lo12:ulisp_verify_t1_sp
    adrp x1, ulisp_verify_t2_sp
    ldr x1, [x1, :lo12:ulisp_verify_t2_sp]
    bl swap_context
    b .L_verify_fail

    .p2align 4
.L_verify_task2_entry:
    // 1. Verify 16-byte SP alignment: sp % 16 == 0
    mov x0, sp
    and x0, x0, #15
    cbnz x0, .L_verify_fail

    // 2. Verify all initial 11 callee-saved registers for Task 2
    ldr x0, =0x1122334455667788; cmp x19, x0; b.ne .L_verify_fail
    ldr x0, =0x2233445566778899; cmp x20, x0; b.ne .L_verify_fail
    ldr x0, =0x33445566778899AA; cmp x21, x0; b.ne .L_verify_fail
    ldr x0, =0x445566778899AABB; cmp x22, x0; b.ne .L_verify_fail
    ldr x0, =0x5566778899AABBCC; cmp x23, x0; b.ne .L_verify_fail
    ldr x0, =0x66778899AABBCCDD; cmp x24, x0; b.ne .L_verify_fail
    ldr x0, =0x778899AABBCCDDEE; cmp x25, x0; b.ne .L_verify_fail
    ldr x0, =0x8899AABBCCDDEEFF; cmp x26, x0; b.ne .L_verify_fail
    ldr x0, =0x99AABBCCDDEEFF00; cmp x27, x0; b.ne .L_verify_fail
    ldr x0, =0xAABBCCDDEEFF0011; cmp x28, x0; b.ne .L_verify_fail
    ldr x0, =0xBBCCDDEEFF001122; cmp x29, x0; b.ne .L_verify_fail

    // 3. Load Task 2 round-2 canary values into all 11 registers
    ldr x19, =0xC1C1C1C1C1C1C1C1
    ldr x20, =0xC2C2C2C2C2C2C2C2
    ldr x21, =0xC3C3C3C3C3C3C3C3
    ldr x22, =0xC4C4C4C4C4C4C4C4
    ldr x23, =0xC5C5C5C5C5C5C5C5
    ldr x24, =0xC6C6C6C6C6C6C6C6
    ldr x25, =0xC7C7C7C7C7C7C7C7
    ldr x26, =0xC8C8C8C8C8C8C8C8
    ldr x27, =0xC9C9C9C9C9C9C9C9
    ldr x28, =0xCACACACACACACACA
    ldr x29, =0xCBCBCBCBCBCBCBCB

    // Switch Task 2 -> Task 1
    adrp x0, ulisp_verify_t2_sp
    add x0, x0, :lo12:ulisp_verify_t2_sp
    adrp x1, ulisp_verify_t1_sp
    ldr x1, [x1, :lo12:ulisp_verify_t1_sp]
    bl swap_context

    // 4. Resumed in Task 2: verify SP alignment and round-2 registers
    mov x0, sp
    and x0, x0, #15
    cbnz x0, .L_verify_fail
    ldr x0, =0xC1C1C1C1C1C1C1C1; cmp x19, x0; b.ne .L_verify_fail
    ldr x0, =0xC2C2C2C2C2C2C2C2; cmp x20, x0; b.ne .L_verify_fail
    ldr x0, =0xC3C3C3C3C3C3C3C3; cmp x21, x0; b.ne .L_verify_fail
    ldr x0, =0xC4C4C4C4C4C4C4C4; cmp x22, x0; b.ne .L_verify_fail
    ldr x0, =0xC5C5C5C5C5C5C5C5; cmp x23, x0; b.ne .L_verify_fail
    ldr x0, =0xC6C6C6C6C6C6C6C6; cmp x24, x0; b.ne .L_verify_fail
    ldr x0, =0xC7C7C7C7C7C7C7C7; cmp x25, x0; b.ne .L_verify_fail
    ldr x0, =0xC8C8C8C8C8C8C8C8; cmp x26, x0; b.ne .L_verify_fail
    ldr x0, =0xC9C9C9C9C9C9C9C9; cmp x27, x0; b.ne .L_verify_fail
    ldr x0, =0xCACACACACACACACA; cmp x28, x0; b.ne .L_verify_fail
    ldr x0, =0xCBCBCBCBCBCBCBCB; cmp x29, x0; b.ne .L_verify_fail

    // All checks passed! Record status = 1 and switch back to Host
    adrp x0, ulisp_verify_status
    mov x1, #1
    str x1, [x0, :lo12:ulisp_verify_status]

    adrp x0, ulisp_total_context_switches
    ldr x1, [x0, :lo12:ulisp_total_context_switches]
    add x1, x1, #4
    str x1, [x0, :lo12:ulisp_total_context_switches]

    adrp x0, ulisp_verify_t2_sp
    add x0, x0, :lo12:ulisp_verify_t2_sp
    adrp x1, ulisp_verify_host_sp
    ldr x1, [x1, :lo12:ulisp_verify_host_sp]
    bl swap_context

.L_verify_fail:
    adrp x0, ulisp_verify_status
    str xzr, [x0, :lo12:ulisp_verify_status]
    adrp x0, ulisp_verify_t1_sp
    add x0, x0, :lo12:ulisp_verify_t1_sp
    adrp x1, ulisp_verify_host_sp
    ldr x1, [x1, :lo12:ulisp_verify_host_sp]
    bl swap_context
    b .L_verify_fail

// -----------------------------------------------------------------------
// 5. Context Switches Endurance Benchmark & Stress Test
//    (%asm-bench-swap-context! stack1-top stack2-top total-switches)
// -----------------------------------------------------------------------
    .globl ulisp_fn__pctasm_bench_swap_context_excl
    .globl ulisp_fn___lib_ulisp_concurrency_context___pctasm_bench_swap_context_excl
    .type ulisp_fn__pctasm_bench_swap_context_excl, %function
    .p2align 4
ulisp_fn__pctasm_bench_swap_context_excl:
ulisp_fn___lib_ulisp_concurrency_context___pctasm_bench_swap_context_excl:
    sub sp, sp, #96
    stp x19, x20, [sp, #0]
    stp x21, x22, [sp, #16]
    stp x23, x24, [sp, #32]
    stp x25, x26, [sp, #48]
    stp x27, x28, [sp, #64]
    stp x29, x30, [sp, #80]

    asr x0, x0, #2
    asr x1, x1, #2
    asr x2, x2, #2
    lsr x2, x2, #1   // half round-trips

    adrp x3, ulisp_bench_completed
    str xzr, [x3, :lo12:ulisp_bench_completed]

    // Prepare Task 1 stack at (stack1_top - 160)
    sub x8, x0, #160
    ldr x4, =0x1111111111111111
    str x4, [x8, #0]    // x19 canary
    str x0, [x8, #8]    // x20: stack1
    str xzr, [x8, #16]  // x21: loop counter = 0
    str x2, [x8, #24]   // x22: target count
    ldr x4, =0x5555555555555555
    str x4, [x8, #72]   // x28 canary
    str x0, [x8, #80]   // x29
    adrp x4, .L_bench_task1_entry
    add x4, x4, :lo12:.L_bench_task1_entry
    str x4, [x8, #88]   // x30

    adrp x5, ulisp_verify_t1_sp
    str x8, [x5, :lo12:ulisp_verify_t1_sp]

    // Prepare Task 2 stack at (stack2_top - 160)
    sub x9, x1, #160
    ldr x4, =0x2222222222222222
    str x4, [x9, #0]    // x19 canary
    str x1, [x9, #8]    // x20: stack2
    str xzr, [x9, #16]  // x21: loop counter = 0
    str x2, [x9, #24]   // x22: target count
    ldr x4, =0x7777777777777777
    str x4, [x9, #72]   // x28 canary
    str x1, [x9, #80]   // x29
    adrp x4, .L_bench_task2_entry
    add x4, x4, :lo12:.L_bench_task2_entry
    str x4, [x9, #88]   // x30

    adrp x5, ulisp_verify_t2_sp
    str x9, [x5, :lo12:ulisp_verify_t2_sp]

    // Enter Task 1
    adrp x0, ulisp_verify_host_sp
    add x0, x0, :lo12:ulisp_verify_host_sp
    adrp x1, ulisp_verify_t1_sp
    ldr x1, [x1, :lo12:ulisp_verify_t1_sp]
    bl swap_context

    // Returned to Host
    adrp x3, ulisp_bench_completed
    ldr x0, [x3, :lo12:ulisp_bench_completed]

    adrp x4, ulisp_total_context_switches
    ldr x5, [x4, :lo12:ulisp_total_context_switches]
    add x5, x5, x0
    str x5, [x4, :lo12:ulisp_total_context_switches]

    lsl x0, x0, #2

    ldp x19, x20, [sp, #0]
    ldp x21, x22, [sp, #16]
    ldp x23, x24, [sp, #32]
    ldp x25, x26, [sp, #48]
    ldp x27, x28, [sp, #64]
    ldp x29, x30, [sp, #80]
    add sp, sp, #96
    ret

    .p2align 4
.L_bench_task1_entry:
.L_bench_task1_loop:
    add x21, x21, #1
    adrp x0, ulisp_verify_t1_sp
    add x0, x0, :lo12:ulisp_verify_t1_sp
    adrp x1, ulisp_verify_t2_sp
    ldr x1, [x1, :lo12:ulisp_verify_t2_sp]
    bl swap_context
    cmp x21, x22
    b.lo .L_bench_task1_loop

    // Verify canaries
    ldr x0, =0x1111111111111111; cmp x19, x0; b.ne .L_bench_corrupt
    ldr x0, =0x5555555555555555; cmp x28, x0; b.ne .L_bench_corrupt

    // Switch back to Host
    adrp x0, ulisp_verify_t1_sp
    add x0, x0, :lo12:ulisp_verify_t1_sp
    adrp x1, ulisp_verify_host_sp
    ldr x1, [x1, :lo12:ulisp_verify_host_sp]
    bl swap_context
    b .L_bench_corrupt

    .p2align 4
.L_bench_task2_entry:
.L_bench_task2_loop:
    add x21, x21, #1
    cmp x21, x22
    b.eq .L_bench_task2_done
    adrp x0, ulisp_verify_t2_sp
    add x0, x0, :lo12:ulisp_verify_t2_sp
    adrp x1, ulisp_verify_t1_sp
    ldr x1, [x1, :lo12:ulisp_verify_t1_sp]
    bl swap_context
    b .L_bench_task2_loop

.L_bench_task2_done:
    ldr x0, =0x2222222222222222; cmp x19, x0; b.ne .L_bench_corrupt
    ldr x0, =0x7777777777777777; cmp x28, x0; b.ne .L_bench_corrupt

    // Record total switches = x21 * 2
    lsl x0, x21, #1
    adrp x1, ulisp_bench_completed
    str x0, [x1, :lo12:ulisp_bench_completed]

    adrp x0, ulisp_verify_t2_sp
    add x0, x0, :lo12:ulisp_verify_t2_sp
    adrp x1, ulisp_verify_t1_sp
    ldr x1, [x1, :lo12:ulisp_verify_t1_sp]
    bl swap_context
    b .L_bench_corrupt

.L_bench_corrupt:
    mov x0, #-1
    adrp x1, ulisp_bench_completed
    str x0, [x1, :lo12:ulisp_bench_completed]
    adrp x0, ulisp_verify_t1_sp
    add x0, x0, :lo12:ulisp_verify_t1_sp
    adrp x1, ulisp_verify_host_sp
    ldr x1, [x1, :lo12:ulisp_verify_host_sp]
    bl swap_context
    b .L_bench_corrupt

// -----------------------------------------------------------------------
// 6. Static Context Switch State Variables (.bss)
// -----------------------------------------------------------------------
    .bss
    .p2align 3
    .globl ulisp_handler_chain
    .weak ulisp_handler_chain
ulisp_handler_chain:
    .zero 512
    .globl ulisp_current_task_top
    .weak ulisp_current_task_top
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
    .globl ulisp_worker_tls_table
    .weak ulisp_worker_tls_table
    .p2align 6
ulisp_worker_tls_table:
    .zero 4096
    .globl ulisp_tls_initialized
    .weak ulisp_tls_initialized
ulisp_tls_initialized:
    .quad 0
    .globl ulisp_gc_state
    .weak ulisp_gc_state
    .p2align 3
ulisp_gc_state:
    .zero 512

    .section .note.GNU-stack,"",%progbits
