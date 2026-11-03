# =======================================================================
# uLisp Concurrency Runtime: System V AMD64 Linux Futex Core (futex.s)
# Conforms to DSN-37 Section 7.4.2 & Section 14.9 Task 7.2 (Issue #676)
# =======================================================================
# Provides:
#   1. ulisp_futex_alloc_cell() -> cell_addr
#   2. ulisp_futex_free_cell(cell_addr) -> #t
#   3. ulisp_futex_get(cell_addr) -> u32_val
#   4. ulisp_futex_set(cell_addr, val) -> #t
#   5. ulisp_futex_cas(cell_addr, expected, new_val) -> #t / #f
#   6. ulisp_futex_wait(cell_addr, expected_val, timeout_ms) -> status
#   7. ulisp_futex_wake(cell_addr, count) -> woken_count
# =======================================================================

    .intel_syntax noprefix
    .text

# -----------------------------------------------------------------------
# Constants & Flags
# -----------------------------------------------------------------------
.equ SYS_MMAP,             9
.equ SYS_MUNMAP,          11
.equ SYS_FUTEX,          202

# Futex operation flags (Private to process for ultra-low latency)
.equ FUTEX_WAIT_PRIVATE, 128
.equ FUTEX_WAKE_PRIVATE, 129

# mmap flags: PROT_READ|PROT_WRITE = 3, MAP_PRIVATE|MAP_ANONYMOUS = 0x22
.equ PROT_READ_WRITE,     3
.equ MAP_ANON_PRIVATE,    0x22

# Scheme tagged constants
.equ SCHEME_TRUE,         111   # #t (0x6F)
.equ SCHEME_FALSE,        47    # #f (0x2F)

# -----------------------------------------------------------------------
# 1. 64-Byte Cacheline-Aligned Futex Cell Allocator
#    ulisp_fn__pctsys_futex_alloc_cell() -> Fixnum(addr)
# -----------------------------------------------------------------------
    .globl ulisp_fn__pctsys_futex_alloc_cell
    .globl ulisp_fn___lib_ulisp_concurrency_futex___pctsys_futex_alloc_cell
    .type ulisp_fn__pctsys_futex_alloc_cell, @function
    .p2align 4
ulisp_fn__pctsys_futex_alloc_cell:
ulisp_fn___lib_ulisp_concurrency_futex___pctsys_futex_alloc_cell:
    push rbp
    mov rbp, rsp

    # Allocate 4096-byte page via sys_mmap (guaranteed 4096-byte aligned > 64-byte)
    mov rax, SYS_MMAP
    xor rdi, rdi                # addr = NULL
    mov rsi, 4096               # length = 4096 bytes
    mov rdx, PROT_READ_WRITE    # prot = PROT_READ | PROT_WRITE
    mov r10, MAP_ANON_PRIVATE   # flags = MAP_PRIVATE | MAP_ANONYMOUS
    mov r8, -1                  # fd = -1
    xor r9, r9                  # offset = 0
    syscall

    test rax, rax
    js .L_alloc_fail

    # Initialize first 32-bit word to 0
    mov dword ptr [rax], 0

    # Tag address as Scheme fixnum (shl rax, 2)
    shl rax, 2
    pop rbp
    ret

.L_alloc_fail:
    mov rax, SCHEME_FALSE
    pop rbp
    ret

# -----------------------------------------------------------------------
# 2. Futex Cell Deallocator
#    ulisp_fn__pctsys_futex_free_cell_excl(cell_addr) -> #t
# -----------------------------------------------------------------------
    .globl ulisp_fn__pctsys_futex_free_cell_excl
    .globl ulisp_fn___lib_ulisp_concurrency_futex___pctsys_futex_free_cell_excl
    .type ulisp_fn__pctsys_futex_free_cell_excl, @function
    .p2align 4
ulisp_fn__pctsys_futex_free_cell_excl:
ulisp_fn___lib_ulisp_concurrency_futex___pctsys_futex_free_cell_excl:
    push rbp
    mov rbp, rsp

    sar rdi, 2                  # raw ptr
    test rdi, rdi
    jz .L_free_done

    mov rax, SYS_MUNMAP
    mov rsi, 4096               # length = 4096
    syscall

.L_free_done:
    mov rax, SCHEME_TRUE
    pop rbp
    ret

# -----------------------------------------------------------------------
# 3. Futex 32-bit Value Getter
#    ulisp_fn__pctsys_futex_get(cell_addr) -> Fixnum(val)
# -----------------------------------------------------------------------
    .globl ulisp_fn__pctsys_futex_get
    .globl ulisp_fn___lib_ulisp_concurrency_futex___pctsys_futex_get
    .type ulisp_fn__pctsys_futex_get, @function
    .p2align 4
ulisp_fn__pctsys_futex_get:
ulisp_fn___lib_ulisp_concurrency_futex___pctsys_futex_get:
    push rbp
    mov rbp, rsp

    sar rdi, 2                  # raw ptr
    xor rax, rax
    mov eax, dword ptr [rdi]    # 32-bit load
    shl rax, 2                  # Tag as Fixnum
    pop rbp
    ret

# -----------------------------------------------------------------------
# 4. Futex 32-bit Value Setter
#    ulisp_fn__pctsys_futex_set_excl(cell_addr, val) -> #t
# -----------------------------------------------------------------------
    .globl ulisp_fn__pctsys_futex_set_excl
    .globl ulisp_fn___lib_ulisp_concurrency_futex___pctsys_futex_set_excl
    .type ulisp_fn__pctsys_futex_set_excl, @function
    .p2align 4
ulisp_fn__pctsys_futex_set_excl:
ulisp_fn___lib_ulisp_concurrency_futex___pctsys_futex_set_excl:
    push rbp
    mov rbp, rsp

    sar rdi, 2                  # raw ptr
    sar rsi, 2                  # raw val
    xchg dword ptr [rdi], esi   # Atomic swap (implicit lock)
    mov rax, SCHEME_TRUE
    pop rbp
    ret

# -----------------------------------------------------------------------
# 5. Futex 32-bit Compare-and-Swap
#    ulisp_fn__pctsys_futex_cas_excl(cell_addr, expected, new_val) -> #t / #f
# -----------------------------------------------------------------------
    .globl ulisp_fn__pctsys_futex_cas_excl
    .globl ulisp_fn___lib_ulisp_concurrency_futex___pctsys_futex_cas_excl
    .type ulisp_fn__pctsys_futex_cas_excl, @function
    .p2align 4
ulisp_fn__pctsys_futex_cas_excl:
ulisp_fn___lib_ulisp_concurrency_futex___pctsys_futex_cas_excl:
    push rbp
    mov rbp, rsp

    sar rdi, 2                  # raw ptr
    sar rsi, 2                  # raw expected
    sar rdx, 2                  # raw new_val

    mov eax, esi                # rax = expected
    lock cmpxchg dword ptr [rdi], edx
    jz .L_cas_success

    mov rax, SCHEME_FALSE
    pop rbp
    ret

.L_cas_success:
    mov rax, SCHEME_TRUE
    pop rbp
    ret

# -----------------------------------------------------------------------
# 6. Futex Wait (FUTEX_WAIT_PRIVATE)
#    ulisp_fn__pctsys_futex_wait(cell_addr, expected_val, timeout_ms) -> Fixnum(status)
#    Status:
#      0 = Woken successfully
#      1 = Value mismatch (EAGAIN / EWOULDBLOCK)
#      2 = Timed out (ETIMEDOUT)
#      3 = Interrupted by signal (EINTR)
#     -1 = Other error
# -----------------------------------------------------------------------
    .globl ulisp_fn__pctsys_futex_wait
    .globl ulisp_fn___lib_ulisp_concurrency_futex___pctsys_futex_wait
    .type ulisp_fn__pctsys_futex_wait, @function
    .p2align 4
ulisp_fn__pctsys_futex_wait:
ulisp_fn___lib_ulisp_concurrency_futex___pctsys_futex_wait:
    push rbp
    mov rbp, rsp
    sub rsp, 32                 # Space for struct timespec { tv_sec, tv_nsec }

    sar rdi, 2                  # raw ptr (rdi)
    sar rsi, 2                  # raw expected_val
    sar rdx, 2                  # raw timeout_ms

    mov r8, rdi                 # save ptr in r8
    mov r9, rsi                 # save expected in r9

    # Check timeout_ms: if < 0, timeout = NULL
    cmp rdx, 0
    jl .L_wait_no_timeout

    # Convert timeout_ms to struct timespec:
    # sec = timeout_ms / 1000
    # nsec = (timeout_ms % 1000) * 1000000
    mov rax, rdx
    xor rdx, rdx
    mov rcx, 1000
    idiv rcx                    # rax = sec, rdx = rem_ms
    mov qword ptr [rsp], rax    # tv_sec

    imul rdx, 1000000           # nsec = rem_ms * 1,000,000
    mov qword ptr [rsp + 8], rdx # tv_nsec
    lea r10, [rsp]              # r10 = &timespec
    jmp .L_do_syscall

.L_wait_no_timeout:
    xor r10, r10                # r10 = NULL

.L_do_syscall:
    mov rax, SYS_FUTEX          # 202
    mov rdi, r8                 # uaddr
    mov rsi, FUTEX_WAIT_PRIVATE # op = 128
    mov rdx, r9                 # val = expected
    # r10 already set to &timespec or NULL
    xor r8, r8                  # uaddr2 = NULL
    xor r9, r9                  # val3 = 0
    syscall

    # Decode return value
    test rax, rax
    jz .L_status_woken          # rax == 0 -> 0

    cmp rax, -11                # -EAGAIN / -EWOULDBLOCK
    je .L_status_mismatch

    cmp rax, -110               # -ETIMEDOUT
    je .L_status_timeout

    cmp rax, -4                 # -EINTR
    je .L_status_intr

    # Other error (-1)
    mov rax, -1
    jmp .L_wait_ret

.L_status_woken:
    xor rax, rax
    jmp .L_wait_ret

.L_status_mismatch:
    mov rax, 1
    jmp .L_wait_ret

.L_status_timeout:
    mov rax, 2
    jmp .L_wait_ret

.L_status_intr:
    mov rax, 3
    jmp .L_wait_ret

.L_wait_ret:
    shl rax, 2                  # Tag as Fixnum
    add rsp, 32
    pop rbp
    ret

# -----------------------------------------------------------------------
# 7. Futex Wake (FUTEX_WAKE_PRIVATE)
#    ulisp_fn__pctsys_futex_wake(cell_addr, count) -> Fixnum(woken_count)
# -----------------------------------------------------------------------
    .globl ulisp_fn__pctsys_futex_wake
    .globl ulisp_fn___lib_ulisp_concurrency_futex___pctsys_futex_wake
    .type ulisp_fn__pctsys_futex_wake, @function
    .p2align 4
ulisp_fn__pctsys_futex_wake:
ulisp_fn___lib_ulisp_concurrency_futex___pctsys_futex_wake:
    push rbp
    mov rbp, rsp

    sar rdi, 2                  # raw ptr
    sar rsi, 2                  # raw count

    mov rdx, rsi                # val = count
    mov rax, SYS_FUTEX          # 202
    # rdi already uaddr
    mov rsi, FUTEX_WAKE_PRIVATE # op = 129
    xor r10, r10                # timeout = NULL
    xor r8, r8                  # uaddr2 = NULL
    xor r9, r9                  # val3 = 0
    syscall

    test rax, rax
    jns .L_wake_done
    xor rax, rax                # On error return 0 woken

.L_wake_done:
    shl rax, 2                  # Tag as Fixnum
    pop rbp
    ret

    .section .note.GNU-stack,"",@progbits
