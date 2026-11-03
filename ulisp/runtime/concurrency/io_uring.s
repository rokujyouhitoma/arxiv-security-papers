# =======================================================================
# uLisp Concurrency Runtime: System V AMD64 Linux io_uring Core (io_uring.s)
# Conforms to DSN-37 Section 7.4.3 & Section 14.9 Task 7.3 (Issue #677)
# =======================================================================
# Provides:
#   1. ulisp_fn__pctsys_io_uring_probe() -> #t / #f
#   2. ulisp_fn__pctsys_io_uring_setup(entries) -> Fixnum(ring_fd) or #f
#   3. ulisp_fn__pctsys_io_uring_enter(ring_fd, to_submit, min_complete, flags) -> Fixnum(res) or #f
#   4. ulisp_fn__pctsys_io_uring_close_excl(ring_fd) -> #t
# =======================================================================

    .intel_syntax noprefix
    .text

# -----------------------------------------------------------------------
# Constants & Flags
# -----------------------------------------------------------------------
.equ SYS_CLOSE,             3
.equ SYS_MMAP,              9
.equ SYS_MUNMAP,           11
.equ SYS_IO_URING_SETUP,  425
.equ SYS_IO_URING_ENTER,  426
.equ SYS_IO_URING_REG,    427

# Scheme tagged constants
.equ SCHEME_TRUE,         111   # #t (0x6F)
.equ SCHEME_FALSE,        47    # #f (0x2F)

# -----------------------------------------------------------------------
# 1. Probe io_uring Support
#    ulisp_fn__pctsys_io_uring_probe() -> #t / #f
# -----------------------------------------------------------------------
    .globl ulisp_fn__pctsys_io_uring_probe
    .globl ulisp_fn___lib_ulisp_concurrency_io_uring___pctsys_io_uring_probe
    .type ulisp_fn__pctsys_io_uring_probe, @function
    .p2align 4
ulisp_fn__pctsys_io_uring_probe:
ulisp_fn___lib_ulisp_concurrency_io_uring___pctsys_io_uring_probe:
    push rbp
    mov rbp, rsp
    sub rsp, 144                # Allocate 144 bytes for struct io_uring_params (120 bytes + padding)

    # Zero out params buffer
    lea rdi, [rbp - 144]
    xor eax, eax
    mov ecx, 18                 # 18 * 8 = 144 bytes
    rep stosq

    # Attempt io_uring_setup(2, &params)
    mov rax, SYS_IO_URING_SETUP
    mov rdi, 2                  # 2 entries minimum
    lea rsi, [rbp - 144]        # params pointer
    syscall

    test rax, rax
    js .L_probe_failed

    # Succeeded: close the test fd and return #t
    mov rdi, rax
    mov rax, SYS_CLOSE
    syscall

    mov rax, SCHEME_TRUE
    leave
    ret

.L_probe_failed:
    mov rax, SCHEME_FALSE
    leave
    ret

# -----------------------------------------------------------------------
# 2. Setup io_uring Ring
#    ulisp_fn__pctsys_io_uring_setup(entries) -> Fixnum(fd) or #f
# -----------------------------------------------------------------------
    .globl ulisp_fn__pctsys_io_uring_setup
    .globl ulisp_fn___lib_ulisp_concurrency_io_uring___pctsys_io_uring_setup
    .type ulisp_fn__pctsys_io_uring_setup, @function
    .p2align 4
ulisp_fn__pctsys_io_uring_setup:
ulisp_fn___lib_ulisp_concurrency_io_uring___pctsys_io_uring_setup:
    push rbp
    mov rbp, rsp
    sub rsp, 144                # struct io_uring_params buffer

    # Unbox entries (Fixnum: rdi >> 2)
    sar rdi, 2
    test rdi, rdi
    jle .L_setup_failed

    # Zero out params struct
    mov r8, rdi                 # Save unboxed entries count in r8
    lea rdi, [rbp - 144]
    xor eax, eax
    mov ecx, 18
    rep stosq

    # Call io_uring_setup(entries, params)
    mov rax, SYS_IO_URING_SETUP
    mov rdi, r8                 # entries
    lea rsi, [rbp - 144]
    syscall

    test rax, rax
    js .L_setup_failed

    # Box return fd as Scheme fixnum (rax << 2)
    sal rax, 2
    leave
    ret

.L_setup_failed:
    mov rax, SCHEME_FALSE
    leave
    ret

# -----------------------------------------------------------------------
# 3. Enter io_uring (Submit / Wait)
#    ulisp_fn__pctsys_io_uring_enter(ring_fd, to_submit, min_complete, flags) -> Fixnum(res) or #f
# -----------------------------------------------------------------------
    .globl ulisp_fn__pctsys_io_uring_enter
    .globl ulisp_fn___lib_ulisp_concurrency_io_uring___pctsys_io_uring_enter
    .type ulisp_fn__pctsys_io_uring_enter, @function
    .p2align 4
ulisp_fn__pctsys_io_uring_enter:
ulisp_fn___lib_ulisp_concurrency_io_uring___pctsys_io_uring_enter:
    push rbp
    mov rbp, rsp

    # Unbox args from System V AMD64 calling convention:
    # rdi: ring_fd, rsi: to_submit, rdx: min_complete, rcx: flags
    sar rdi, 2                  # ring_fd
    sar rsi, 2                  # to_submit
    sar rdx, 2                  # min_complete
    sar rcx, 2                  # flags

    mov r10, rcx                # Linux syscall 4th arg is r10
    mov rax, SYS_IO_URING_ENTER
    xor r8, r8                  # sig = NULL
    xor r9, r9                  # sigsz = 0
    syscall

    test rax, rax
    js .L_enter_failed

    sal rax, 2                  # Box as Scheme fixnum
    leave
    ret

.L_enter_failed:
    mov rax, SCHEME_FALSE
    leave
    ret

# -----------------------------------------------------------------------
# 4. Close io_uring Ring
#    ulisp_fn__pctsys_io_uring_close_excl(ring_fd) -> #t
# -----------------------------------------------------------------------
    .globl ulisp_fn__pctsys_io_uring_close_excl
    .globl ulisp_fn___lib_ulisp_concurrency_io_uring___pctsys_io_uring_close_excl
    .type ulisp_fn__pctsys_io_uring_close_excl, @function
    .p2align 4
ulisp_fn__pctsys_io_uring_close_excl:
ulisp_fn___lib_ulisp_concurrency_io_uring___pctsys_io_uring_close_excl:
    push rbp
    mov rbp, rsp

    sar rdi, 2                  # Unbox ring_fd
    test rdi, rdi
    js .L_close_done

    mov rax, SYS_CLOSE
    syscall

.L_close_done:
    mov rax, SCHEME_TRUE
    leave
    ret

    .section .note.GNU-stack,"",@progbits
