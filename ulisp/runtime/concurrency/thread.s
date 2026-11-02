# =======================================================================
# uLisp Concurrency Runtime: System V AMD64 Native Threading (thread.s)
# Conforms to DSN-37 Section 7.4 & Phase 7 Task 7.1 (Issue #675)
# =======================================================================
# Provides:
#   1. ulisp_spawn_thread(fn_ptr, arg) :
#      Linux SYS_clone (syscall 56) with dedicated 1MB stack & guard page.
#   2. ulisp_set_affinity(core_id) :
#      Linux SYS_sched_setaffinity (syscall 203) for 1:1 CPU core pinning.
#   3. ulisp_get_online_cpus() :
#      Linux SYS_sched_getaffinity (syscall 204) with POPCNT for hardware topology.
#   4. ulisp_thread_exit() :
#      Linux SYS_exit (syscall 60) for clean thread termination.
# =======================================================================

    .intel_syntax noprefix
    .text

# -----------------------------------------------------------------------
# Constants & Flags
# -----------------------------------------------------------------------
# Clone flags:
#   CLONE_VM      = 0x00000100
#   CLONE_FS      = 0x00000200
#   CLONE_FILES   = 0x00000400
#   CLONE_SIGHAND = 0x00000800
#   CLONE_THREAD  = 0x00010000
#   CLONE_SYSVSEM = 0x00040000
# Total flags = 0x00050f00
.equ CLONE_THREAD_FLAGS, 0x00050f00

# Stack size = 1MB (1048576 bytes = 0x100000)
.equ THREAD_STACK_SIZE,  0x100000
# Guard page size = 4KB (4096 bytes = 0x1000)
.equ STACK_GUARD_SIZE,   0x1000

# Syscall numbers (Linux x86-64)
.equ SYS_MMAP,             9
.equ SYS_MPROTECT,        10
.equ SYS_MUNMAP,          11
.equ SYS_CLONE,           56
.equ SYS_EXIT,            60
.equ SYS_SCHED_SETAFFINITY, 203
.equ SYS_SCHED_GETAFFINITY, 204

# mmap flags: PROT_READ|PROT_WRITE = 3, MAP_PRIVATE|MAP_ANONYMOUS = 0x22
.equ PROT_READ_WRITE,     3
.equ MAP_ANON_PRIVATE,    0x22
.equ PROT_NONE,           0

# Scheme tagged constants
.equ SCHEME_TRUE,         111   # #t (0x6F)
.equ SCHEME_FALSE,        47    # #f (0x2F)

# -----------------------------------------------------------------------
# 1. Native Thread Stack Allocator
#    Returns allocated stack_top in %rax, or 0 on failure.
# -----------------------------------------------------------------------
    .globl ulisp_alloc_thread_stack
    .type ulisp_alloc_thread_stack, @function
    .p2align 4
ulisp_alloc_thread_stack:
    push rbp
    mov rbp, rsp
    push rbx

    # SYS_mmap(0, THREAD_STACK_SIZE, PROT_READ|PROT_WRITE, MAP_ANON_PRIVATE, -1, 0)
    mov rax, SYS_MMAP
    xor rdi, rdi
    mov rsi, THREAD_STACK_SIZE
    mov rdx, PROT_READ_WRITE
    mov r10, MAP_ANON_PRIVATE
    mov r8, -1
    xor r9, r9
    syscall

    # Check for mmap error (rax < 0 or > -4096)
    cmp rax, -4096
    ja .L_mmap_fail

    mov rbx, rax                # rbx = stack_base

    # SYS_mprotect(stack_base, STACK_GUARD_SIZE, PROT_NONE) -> CWE-119 guard page
    mov rax, SYS_MPROTECT
    mov rdi, rbx
    mov rsi, STACK_GUARD_SIZE
    xor rdx, rdx                # PROT_NONE
    syscall

    # stack_top = stack_base + THREAD_STACK_SIZE
    lea rax, [rbx + THREAD_STACK_SIZE]
    pop rbx
    pop rbp
    ret

.L_mmap_fail:
    xor rax, rax
    pop rbx
    pop rbp
    ret

# -----------------------------------------------------------------------
# 2. Native Thread Spawn Primitive
#    Scheme: (%sys-spawn-thread proc arg)
#    rdi = proc (tagged Scheme closure or raw function pointer)
#    rsi = arg  (tagged Scheme object)
# -----------------------------------------------------------------------
    .globl ulisp_fn__pctsys_spawn_thread
    .globl ulisp_fn___lib_ulisp_concurrency_thread___pctsys_spawn_thread
    .type ulisp_fn__pctsys_spawn_thread, @function
    .p2align 4
ulisp_fn__pctsys_spawn_thread:
ulisp_fn___lib_ulisp_concurrency_thread___pctsys_spawn_thread:
    push rbp
    mov rbp, rsp
    push r12
    push r13
    push r14
    push rbx

    mov r13, rdi                # r13 = proc (DO NOT sar - proc is a closure pointer!)
    mov r14, rsi                # r14 = arg

    # Allocate 1MB stack with 4KB guard page
    call ulisp_alloc_thread_stack
    test rax, rax
    jz .L_spawn_stack_fail

    mov rbx, rax                # rbx = stack_top
    and rbx, -16                # Ensure 16-byte alignment

    # Allocate unique thread spawn index atomically
    mov rax, 1
    lock xadd [rip + ulisp_thread_spawn_counter], rax
    # rax now holds unique thread index (0, 1, 2, ...)
    # Compute isolated per-thread heap arena: child_r12 = parent_r12 + (rax + 1) * 32MB
    inc rax
    shl rax, 25                         # rax = (idx + 1) * 32MB (0x02000000)
    lea rcx, [r12 + rax]                # rcx = isolated child_r12

    # Prepare child stack frame (32 bytes, maintains 16-byte alignment):
    #   [rbx - 8]  = stack_base (for cleanup)
    #   [rbx - 16] = child_r12 (per-thread heap pointer)
    #   [rbx - 24] = arg
    #   [rbx - 32] = proc
    lea rdx, [rbx - THREAD_STACK_SIZE]  # stack_base
    mov [rbx - 8], rdx
    mov [rbx - 16], rcx
    mov [rbx - 24], r14
    mov [rbx - 32], r13
    lea rsi, [rbx - 32]                 # child_sp = rbx - 32

    # SYS_clone(flags, child_sp, parent_tid, child_tid, tls)
    mov rax, SYS_CLONE
    mov rdi, CLONE_THREAD_FLAGS
    # rsi is already child_sp
    xor rdx, rdx                        # parent_tidptr = 0
    xor r10, r10                        # child_tidptr = 0
    xor r8, r8                          # tls = 0
    syscall

    test rax, rax
    js .L_clone_fail
    jz .L_child_thread_start

    # Parent thread: rax = child tid
    shl rax, 2                          # Convert tid to Scheme fixnum
    pop rbx
    pop r14
    pop r13
    pop r12
    pop rbp
    ret

.L_child_thread_start:
    # -------------------------------------------------------------------
    # Child Thread Execution Engine
    # Stack layout at entry:
    #   [rsp]     = proc
    #   [rsp + 8] = arg
    #   [rsp + 16]= parent_r12
    #   [rsp + 24]= stack_base
    # -------------------------------------------------------------------
    pop r11                             # r11 = proc
    pop rdi                             # rdi = arg (1st argument in System V ABI)
    pop r12                             # r12 = live heap pointer restored
    pop rbx                             # rbx = stack_base (rsp is now 16-byte aligned!)

    # Check if proc is tagged pair/closure (low tag == 1)
    mov rax, r11
    and rax, 3
    cmp rax, 1
    jne .L_child_call_raw
    # Scheme closure: pass closure in r10, load entry address into r11
    mov r10, r11
    mov r11, [r10 - 1]
.L_child_call_raw:
    # System V ABI: before call, rsp % 16 == 0. Call pushes 8-byte ret addr.
    mov rax, 4                          # Arity: 1 argument tagged fixnum (1 << 2 = 4)
    call r11

    # Clean exit via SYS_exit(0)
    mov rax, SYS_EXIT
    xor rdi, rdi
    syscall
    ud2

.L_clone_fail:
    # Clone failed: free allocated stack before returning
    mov rdi, rbx
    sub rdi, THREAD_STACK_SIZE          # rdi = stack_base
    mov rsi, THREAD_STACK_SIZE          # rsi = length
    mov rax, SYS_MUNMAP
    syscall
    mov rax, -1
    shl rax, 2
    pop rbx
    pop r14
    pop r13
    pop r12
    pop rbp
    ret

.L_spawn_stack_fail:
    mov rax, -2
    shl rax, 2
    pop rbx
    pop r14
    pop r13
    pop r12
    pop rbp
    ret

# -----------------------------------------------------------------------
# 3. CPU Core Pinning Primitive
#    Scheme: (%sys-set-affinity! core-id)
#    rdi = core-id (tagged fixnum)
# -----------------------------------------------------------------------
    .globl ulisp_fn__pctsys_set_affinity_excl
    .globl ulisp_fn___lib_ulisp_concurrency_thread___pctsys_set_affinity_excl
    .type ulisp_fn__pctsys_set_affinity_excl, @function
    .p2align 4
ulisp_fn__pctsys_set_affinity_excl:
ulisp_fn___lib_ulisp_concurrency_thread___pctsys_set_affinity_excl:
    push rbp
    mov rbp, rsp
    sub rsp, 16

    sar rdi, 2                          # rdi = raw core-id
    cmp rdi, 0
    jl .L_affinity_invalid
    cmp rdi, 63
    jg .L_affinity_invalid

    # Build 64-bit cpu mask: 1 << core_id
    mov rcx, rdi
    mov rax, 1
    shl rax, cl
    mov [rsp], rax                      # cpu_set mask on stack
    mov qword ptr [rsp + 8], 0

    # SYS_sched_setaffinity(0, 8, &mask)
    mov rax, SYS_SCHED_SETAFFINITY
    xor rdi, rdi                        # 0 = calling thread
    mov rsi, 8                          # sizeof(cpu_set_t) = 8 bytes
    lea rdx, [rsp]                      # mask ptr
    syscall

    test rax, rax
    jnz .L_affinity_fail

    mov rax, SCHEME_TRUE                # Return #t
    add rsp, 16
    pop rbp
    ret

.L_affinity_invalid:
.L_affinity_fail:
    mov rax, SCHEME_FALSE               # Return #f
    add rsp, 16
    pop rbp
    ret

# -----------------------------------------------------------------------
# 4. Hardware Topology: Online CPU Count Primitive
#    Scheme: (%sys-online-cpu-count)
# -----------------------------------------------------------------------
    .globl ulisp_fn__pctsys_online_cpu_count
    .globl ulisp_fn___lib_ulisp_concurrency_thread___pctsys_online_cpu_count
    .type ulisp_fn__pctsys_online_cpu_count, @function
    .p2align 4
ulisp_fn__pctsys_online_cpu_count:
ulisp_fn___lib_ulisp_concurrency_thread___pctsys_online_cpu_count:
    mov rax, [rip + ulisp_cached_online_cpus]
    test rax, rax
    jnz .L_popcnt_cached

    push rbp
    mov rbp, rsp
    sub rsp, 128                        # 1024-bit mask buffer

    # SYS_sched_getaffinity(0, 128, &mask)
    mov rax, SYS_SCHED_GETAFFINITY
    xor rdi, rdi                        # 0 = calling process
    mov rsi, 128
    mov rdx, rsp
    syscall

    test rax, rax
    js .L_getaff_fallback

    # Count set bits across returned buffer using POPCNT
    xor ecx, ecx                        # total count = 0
    xor r8, r8                          # byte index = 0
.L_popcnt_loop:
    cmp r8, rax
    jge .L_popcnt_done
    popcnt r9, [rsp + r8]
    add rcx, r9
    add r8, 8
    jmp .L_popcnt_loop

.L_popcnt_done:
    test rcx, rcx
    jnz .L_popcnt_store

.L_getaff_fallback:
    mov rcx, 1                          # Fallback to 1 core

.L_popcnt_store:
    mov [rip + ulisp_cached_online_cpus], rcx
    mov rax, rcx
    shl rax, 2                          # Tag as Scheme Fixnum
    add rsp, 128
    pop rbp
    ret

.L_popcnt_cached:
    shl rax, 2                          # Tag as Scheme Fixnum
    ret

# -----------------------------------------------------------------------
# 5. Thread Exit Primitive
#    Scheme: (%sys-thread-exit! code)
# -----------------------------------------------------------------------
    .globl ulisp_fn__pctsys_thread_exit_excl
    .globl ulisp_fn___lib_ulisp_concurrency_thread___pctsys_thread_exit_excl
    .type ulisp_fn__pctsys_thread_exit_excl, @function
    .p2align 4
ulisp_fn__pctsys_thread_exit_excl:
ulisp_fn___lib_ulisp_concurrency_thread___pctsys_thread_exit_excl:
    sar rdi, 2                          # rdi = exit code
    mov rax, SYS_EXIT
    syscall
    ud2

# -----------------------------------------------------------------------
# Static Data: Cached CPU count & Atomic Thread Spawn Counter
# -----------------------------------------------------------------------
    .data
    .p2align 3
    .globl ulisp_cached_online_cpus
ulisp_cached_online_cpus:
    .quad 0
    .globl ulisp_thread_spawn_counter
ulisp_thread_spawn_counter:
    .quad 0

    .section .note.GNU-stack,"",@progbits
