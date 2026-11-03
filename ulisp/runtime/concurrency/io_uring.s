# =======================================================================
# uLisp Concurrency Runtime: System V AMD64 Linux io_uring Core (io_uring.s)
# Conforms to DSN-37 Section 7.4.3 & Section 14.9 Task 7.3 (Issue #677, #683)
# =======================================================================
# Provides:
#   1. ulisp_fn__pctsys_io_uring_probe() -> #t / #f
#   2. ulisp_fn__pctsys_io_uring_setup(entries) -> Fixnum(ring_fd) or #f
#   2b. ulisp_fn__pctsys_io_uring_setup_sqpoll(entries, sq_thread_idle_ms) -> Fixnum(ring_fd) or #f
#   3. ulisp_fn__pctsys_io_uring_enter(ring_fd, to_submit, min_complete, flags) -> Fixnum(res) or #f
#   3b. ulisp_fn__pctsys_io_uring_register(ring_fd, opcode, arg, nr_args) -> Fixnum(res) or #f
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

.equ IORING_SETUP_SQPOLL,          2
.equ IORING_ENTER_SQ_WAKEUP,       2
.equ IORING_REGISTER_BUFFERS,      0
.equ IORING_UNREGISTER_BUFFERS,    1

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
# 2. Setup io_uring Ring (Standard)
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
# 2b. Setup io_uring Ring with SQPOLL
#    ulisp_fn__pctsys_io_uring_setup_sqpoll(entries, sq_thread_idle_ms) -> Fixnum(fd) or #f
# -----------------------------------------------------------------------
    .globl ulisp_fn__pctsys_io_uring_setup_sqpoll
    .globl ulisp_fn___lib_ulisp_concurrency_io_uring___pctsys_io_uring_setup_sqpoll
    .type ulisp_fn__pctsys_io_uring_setup_sqpoll, @function
    .p2align 4
ulisp_fn__pctsys_io_uring_setup_sqpoll:
ulisp_fn___lib_ulisp_concurrency_io_uring___pctsys_io_uring_setup_sqpoll:
    push rbp
    mov rbp, rsp
    sub rsp, 144                # struct io_uring_params buffer

    # Unbox entries (Fixnum: rdi >> 2)
    sar rdi, 2
    test rdi, rdi
    jle .L_setup_sqpoll_failed

    # Unbox sq_thread_idle_ms (Fixnum: rsi >> 2)
    sar rsi, 2
    test rsi, rsi
    jl .L_setup_sqpoll_failed

    mov r8, rdi                 # Save unboxed entries count in r8
    mov r9, rsi                 # Save unboxed idle ms in r9

    # Zero out params struct
    lea rdi, [rbp - 144]
    xor eax, eax
    mov ecx, 18
    rep stosq

    # Set params.flags = IORING_SETUP_SQPOLL (offset 8 in struct io_uring_params)
    mov dword ptr [rbp - 144 + 8], IORING_SETUP_SQPOLL

    # Set params.sq_thread_idle = idle_ms (offset 16 in struct io_uring_params)
    mov dword ptr [rbp - 144 + 16], r9d

    # Call io_uring_setup(entries, params)
    mov rax, SYS_IO_URING_SETUP
    mov rdi, r8                 # entries
    lea rsi, [rbp - 144]        # params
    syscall

    test rax, rax
    js .L_setup_sqpoll_failed

    # Box return fd as Scheme fixnum (rax << 2)
    sal rax, 2
    leave
    ret

.L_setup_sqpoll_failed:
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
# 3b. Register Buffers / Resources
#    ulisp_fn__pctsys_io_uring_register(ring_fd, opcode, arg, nr_args) -> Fixnum(res) or #f
# -----------------------------------------------------------------------
    .globl ulisp_fn__pctsys_io_uring_register
    .globl ulisp_fn___lib_ulisp_concurrency_io_uring___pctsys_io_uring_register
    .type ulisp_fn__pctsys_io_uring_register, @function
    .p2align 4
ulisp_fn__pctsys_io_uring_register:
ulisp_fn___lib_ulisp_concurrency_io_uring___pctsys_io_uring_register:
    push rbp
    mov rbp, rsp
    # Allocate stack buffer for struct iovec array: 64 * 16 = 1024 bytes (+ 16 bytes alignment)
    sub rsp, 1040

    # Save incoming arguments
    # rdi: ring_fd (Scheme fixnum)
    # rsi: opcode (Scheme fixnum)
    # rdx: arg (Scheme value: bytevector, vector, or fixnum 0)
    # rcx: nr_args (Scheme fixnum)
    sar rdi, 2                  # ring_fd
    sar rsi, 2                  # opcode
    sar rcx, 2                  # nr_args

    test rdi, rdi
    js .L_reg_failed

    cmp rsi, IORING_REGISTER_BUFFERS
    je .L_reg_buffers

    cmp rsi, IORING_UNREGISTER_BUFFERS
    je .L_unreg_buffers

    # Generic register opcode (fallback)
    xor rdx, rdx
    xor r10, r10
    jmp .L_do_syscall_reg

.L_unreg_buffers:
    xor rdx, rdx                # arg = NULL
    xor r10, r10                # nr_args = 0
    jmp .L_do_syscall_reg

.L_reg_buffers:
    # Build iovec array on stack at [rsp]
    # Check if arg (in rdx) is a bytevector (tag 7) or vector (tag 5)
    mov r8, rdx
    and r8, 7
    cmp r8, 7
    je .L_reg_single_bv
    cmp r8, 5
    je .L_reg_vector_bv
    jmp .L_reg_failed

.L_reg_single_bv:
    # Single bytevector: rdx has tag 7
    # iov_base = rdx + 1
    # iov_len = [rdx - 7] >> 2
    lea rax, [rdx + 1]
    mov r9, [rdx - 7]
    sar r9, 2
    test r9, r9
    js .L_reg_failed

    mov [rsp], rax              # iov[0].iov_base
    mov [rsp + 8], r9           # iov[0].iov_len

    mov rdx, rsp                # arg = &iov[0]
    mov r10, 1                  # nr_args = 1
    jmp .L_do_syscall_reg

.L_reg_vector_bv:
    # Vector of bytevectors: rdx has tag 5
    # Vector length: [rdx - 5] >> 2
    mov rax, [rdx - 5]
    sar rax, 2
    test rax, rax
    jle .L_reg_failed
    cmp rax, 64
    jg .L_reg_failed

    mov r10, rax                # r10 = count of buffers
    xor r8, r8                  # r8 = index loop (0 .. count - 1)

.L_vec_loop:
    cmp r8, r10
    jge .L_vec_loop_done

    # Fetch element: [rdx + 3 + r8*8]
    mov r11, [rdx + 3 + r8*8]
    mov rax, r11
    and rax, 7
    cmp rax, 7                  # Must be bytevector (tag 7)
    jne .L_reg_failed

    # iov_base = r11 + 1
    lea rax, [r11 + 1]
    # iov_len = [r11 - 7] >> 2
    mov r9, [r11 - 7]
    sar r9, 2

    # Store into iov[r8] at [rsp + r8*16]
    mov rcx, r8
    shl rcx, 4                  # rcx = r8 * 16
    mov [rsp + rcx], rax        # iov_base
    mov [rsp + rcx + 8], r9     # iov_len

    inc r8
    jmp .L_vec_loop

.L_vec_loop_done:
    mov rdx, rsp                # arg = &iov[0]
    # r10 already has nr_args count
    jmp .L_do_syscall_reg

.L_do_syscall_reg:
    mov rax, SYS_IO_URING_REG
    # Linux syscall 427: rdi=ring_fd, rsi=opcode, rdx=arg, r10=nr_args
    syscall

    test rax, rax
    js .L_reg_failed

    sal rax, 2                  # Box as Scheme fixnum
    leave
    ret

.L_reg_failed:
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
