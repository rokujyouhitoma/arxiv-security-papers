"""
Tests for Zero-libc / Freestanding Pure Scheme Bare-Metal Runtime for ULisp.
Conforms to DSN-36 and Issue #516.
Verifies that ULisp can generate standalone static ELF binaries with:
- ZERO libc (glibc/musl) dependencies (-nostdlib -static)
- ZERO external libraries (libgc, libm, etc.)
- 100% Pure Scheme POSIX layer emitting direct Linux x86-64 syscalls
"""

import os
import subprocess
import tempfile

WORKSPACE_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
ULISP_DIR = os.path.join(WORKSPACE_DIR, "ulisp")
COMPILER_SCM = os.path.join(ULISP_DIR, "compiler.scm")
POSIX_SCM = os.path.join(ULISP_DIR, "lib/posix.scm")
GC_SCM = os.path.join(ULISP_DIR, "lib/gc.scm")


def test_bare_metal_freestanding_execution():
    """Verify that a Scheme program linked with posix.scm runs under -nostdlib -static."""
    assert os.path.exists(COMPILER_SCM), f"Compiler not found: {COMPILER_SCM}"
    assert os.path.exists(POSIX_SCM), f"POSIX runtime not found: {POSIX_SCM}"

    with open(POSIX_SCM, "r", encoding="utf-8") as f:
        posix_code = f.read()

    test_scm_code = f"""
{posix_code}

;; Test Application Logic
(ulisp-init-heap! 65536)
(sys-write-string "ULISP_BARE_METAL_ONLINE\\n")
(sys-write-string "RESULT: ")
(sys-write-fixnum (+ 100 23))
(sys-newline)
(sys-exit 0)
"""

    with tempfile.TemporaryDirectory() as tmpdir:
        src_path = os.path.join(tmpdir, "test.scm")
        s_path = os.path.join(tmpdir, "test.s")
        bin_path = os.path.join(tmpdir, "test_bare")

        with open(src_path, "w", encoding="utf-8") as f:
            f.write(test_scm_code)

        # 1. Compile Scheme -> x86-64 assembly
        with open(src_path, "r", encoding="utf-8") as f_in, open(
            s_path, "w", encoding="utf-8"
        ) as f_out:
            ret = subprocess.run(
                ["python3", "-m", "ilisp", COMPILER_SCM],
                stdin=f_in,
                stdout=f_out,
                stderr=subprocess.PIPE,
                cwd=WORKSPACE_DIR,
                text=True,
            )
        assert ret.returncode == 0, f"Compilation failed: {ret.stderr}"
        assert os.path.exists(s_path)

        # 2. Assemble and link with -nostdlib -static
        link_res = subprocess.run(
            ["gcc", "-nostdlib", "-static", s_path, "-o", bin_path],
            capture_output=True,
            text=True,
        )
        assert link_res.returncode == 0, f"Linking failed: {link_res.stderr}"
        assert os.path.exists(bin_path)

        # 3. Verify static ELF without dynamic loader
        ldd_res = subprocess.run(["ldd", bin_path], capture_output=True, text=True)
        # ldd outputs "not a dynamic executable" on stderr or stdout
        combined_ldd = (ldd_res.stdout + ldd_res.stderr).lower()
        assert "not a dynamic executable" in combined_ldd

        # 4. Execute the bare metal binary
        run_res = subprocess.run([bin_path], capture_output=True)
        assert run_res.returncode == 0
        output = run_res.stdout.decode("utf-8")
        assert "ULISP_BARE_METAL_ONLINE" in output
        assert "RESULT: 123" in output


def test_bare_metal_recursive_computation():
    """Verify recursive Fibonacci and zero-libc arithmetic in bare metal mode."""
    with open(POSIX_SCM, "r", encoding="utf-8") as f:
        posix_code = f.read()

    test_scm_code = f"""
{posix_code}

(define (fib n)
  (if (< n 2)
      n
      (+ (fib (- n 1)) (fib (- n 2)))))

(sys-write-string "FIB(10) = ")
(sys-write-fixnum (fib 10))
(sys-newline)
(sys-exit 0)
"""

    with tempfile.TemporaryDirectory() as tmpdir:
        src_path = os.path.join(tmpdir, "fib.scm")
        s_path = os.path.join(tmpdir, "fib.s")
        bin_path = os.path.join(tmpdir, "fib_bare")

        with open(src_path, "w", encoding="utf-8") as f:
            f.write(test_scm_code)

        with open(src_path, "r", encoding="utf-8") as f_in, open(
            s_path, "w", encoding="utf-8"
        ) as f_out:
            ret = subprocess.run(
                ["python3", "-m", "ilisp", COMPILER_SCM],
                stdin=f_in,
                stdout=f_out,
                stderr=subprocess.PIPE,
                cwd=WORKSPACE_DIR,
                text=True,
            )
        assert ret.returncode == 0, f"Compilation failed: {ret.stderr}"

        link_res = subprocess.run(
            ["gcc", "-nostdlib", "-static", s_path, "-o", bin_path],
            capture_output=True,
            text=True,
        )
        assert link_res.returncode == 0, f"Linking failed: {link_res.stderr}"

        run_res = subprocess.run([bin_path], capture_output=True)
        assert run_res.returncode == 0
        output = run_res.stdout.decode("utf-8")
        assert "FIB(10) = 55" in output


def test_bare_metal_exact_gc_stackmap_unboxed():
    """Verify that Exact GC Stackmaps protect raw unboxed scalar integers from corruption

    while correctly copying and forwarding real heap pointers.
    """
    assert os.path.exists(COMPILER_SCM)
    assert os.path.exists(POSIX_SCM)
    assert os.path.exists(GC_SCM)

    with open(POSIX_SCM, "r", encoding="utf-8") as f:
        posix_code = f.read()
    with open(GC_SCM, "r", encoding="utf-8") as f:
        gc_code = f.read()

    test_scm_code = f"""
{posix_code}
{gc_code}

;; Call a function with stack frame containing both:
;; 1. A live heap pointer `p`
;; 2. An unboxed raw integer `raw-addr` whose value is (from + 1)
;; Under conservative GC, raw-addr would be treated as a heap pointer and corrupted!
;; Under Exact GC Stackmaps, raw-addr slot has mask bit 0 and is preserved 100%!
(define (deep-frame-gc-trigger p)
  (let* ((orig-from (gc-from))
         (raw-addr (%raw-add orig-from 1)))
    ;; Force garbage collection cycle
    (gc-collect! (%get-rsp))
    ;; After collection, spaces are swapped. Verify raw-addr is completely uncorrupted (still orig-from + 1)
    (if (= raw-addr (%raw-add orig-from 1))
        (begin
          (sys-write-string "EXACT_GC_RAW_PRESERVED\\n")
          ;; Verify test-pair was copied and fields preserved
          (if (and (= (car p) 42) (= (cdr p) 99))
              (sys-write-string "PAIR_FIELDS_PRESERVED\\n")
              (sys-write-string "PAIR_FIELDS_CORRUPTED\\n")))
        (sys-write-string "CORRUPTED_BY_CONSERVATIVE_GC\\n"))))

(define (run-test)
  (let ((from (sys-mmap 65536))
        (to (sys-mmap 65536)))
    (gc-init! from to 65536 (%get-rsp))
    (let ((test-pair (cons 42 99)))
      (deep-frame-gc-trigger test-pair))))

(run-test)
(sys-exit 0)
"""

    with tempfile.TemporaryDirectory() as tmpdir:
        src_path = os.path.join(tmpdir, "exact_gc.scm")
        s_path = os.path.join(tmpdir, "exact_gc.s")
        bin_path = os.path.join(tmpdir, "exact_gc_bare")

        with open(src_path, "w", encoding="utf-8") as f:
            f.write(test_scm_code)

        with open(src_path, "r", encoding="utf-8") as f_in, open(
            s_path, "w", encoding="utf-8"
        ) as f_out:
            ret = subprocess.run(
                ["python3", "-m", "ilisp", COMPILER_SCM],
                stdin=f_in,
                stdout=f_out,
                stderr=subprocess.PIPE,
                cwd=WORKSPACE_DIR,
                text=True,
            )
        assert ret.returncode == 0, f"Compilation failed: {ret.stderr}"

        link_res = subprocess.run(
            ["gcc", "-nostdlib", "-static", s_path, "-o", bin_path],
            capture_output=True,
            text=True,
        )
        assert link_res.returncode == 0, f"Linking failed: {link_res.stderr}"

        run_res = subprocess.run([bin_path], capture_output=True)
        assert run_res.returncode == 0
        output = run_res.stdout.decode("utf-8")
        assert "EXACT_GC_RAW_PRESERVED" in output
        assert "PAIR_FIELDS_PRESERVED" in output


def test_buffered_io_syscall_reduction():
    """Verify that emitting 10,000 characters triggers <= 10 write syscalls via 4KB buffering."""
    with open(POSIX_SCM, "r", encoding="utf-8") as f:
        posix_code = f.read()

    test_scm_code = f"""
{posix_code}

(ulisp-init-heap! 65536)

(define (emit-chars n)
  (if (> n 0)
      (begin
        (sys-write-char #\\A)
        (emit-chars (- n 1)))))

(emit-chars 10000)
(sys-exit 0)
"""

    with tempfile.TemporaryDirectory() as tmpdir:
        src_path = os.path.join(tmpdir, "buf_io.scm")
        s_path = os.path.join(tmpdir, "buf_io.s")
        bin_path = os.path.join(tmpdir, "buf_io_bare")

        with open(src_path, "w", encoding="utf-8") as f:
            f.write(test_scm_code)

        with open(src_path, "r", encoding="utf-8") as f_in, open(
            s_path, "w", encoding="utf-8"
        ) as f_out:
            ret = subprocess.run(
                ["python3", "-m", "ilisp", COMPILER_SCM],
                stdin=f_in,
                stdout=f_out,
                stderr=subprocess.PIPE,
                cwd=WORKSPACE_DIR,
                text=True,
            )
        assert ret.returncode == 0, f"Compilation failed: {ret.stderr}"

        link_res = subprocess.run(
            ["gcc", "-nostdlib", "-static", s_path, "-o", bin_path],
            capture_output=True,
            text=True,
        )
        assert link_res.returncode == 0, f"Linking failed: {link_res.stderr}"

        # Run with strace counting write syscalls
        strace_res = subprocess.run(
            ["strace", "-e", "trace=write", bin_path],
            capture_output=True,
            text=True,
        )
        assert strace_res.returncode == 0
        # Check standard output contains 10,000 'A's
        assert len(strace_res.stdout) == 10000
        assert strace_res.stdout == "A" * 10000

        # In unbuffered execution, write syscall is called 10,000 times.
        # With 4KB buffer (4096 bytes), 10,000 / 4096 = 2 full flushes + 1 final flush on exit = 3 writes!
        write_syscall_lines = [
            line for line in strace_res.stderr.splitlines() if line.startswith("write(")
        ]
        num_writes = len(write_syscall_lines)
        assert num_writes <= 5, f"Expected <= 5 write syscalls, got {num_writes}"


def test_bare_metal_escape_analysis_stack_promotion():
    """Verify that non-escaping pairs are stack-promoted with ZERO heap bump allocation."""
    with open(POSIX_SCM, "r", encoding="utf-8") as f:
        posix_code = f.read()

    test_scm_code = f"""
{posix_code}

(ulisp-init-heap! 65536)

;; Loop 100 times creating local non-escaping pairs and computing their sum
(define (run-loop n acc)
  (if (<= n 0)
      acc
      (let ((p (cons n acc)))
        (run-loop (- n 1) (+ (car p) (cdr p))))))

(define (test-stack-alloc)
  (let ((before-heap (%get-heap-ptr)))
    (let ((result (run-loop 100 0)))
      (let ((after-heap (%get-heap-ptr)))
        (sys-write-string "LOOP_RESULT: ")
        (sys-write-fixnum result)
        (sys-newline)
        (if (= before-heap after-heap)
            (sys-write-string "STACK_PROMOTION_HEAP_DELTA_ZERO\\n")
            (begin
              (sys-write-string "HEAP_ADVANCED_BYTES: ")
              (sys-write-fixnum (%raw-sub after-heap before-heap))
              (sys-newline)))))))

(test-stack-alloc)
(sys-exit 0)
"""

    with tempfile.TemporaryDirectory() as tmpdir:
        src_path = os.path.join(tmpdir, "stack_alloc.scm")
        s_path = os.path.join(tmpdir, "stack_alloc.s")
        bin_path = os.path.join(tmpdir, "stack_alloc_bare")

        with open(src_path, "w", encoding="utf-8") as f:
            f.write(test_scm_code)

        with open(src_path, "r", encoding="utf-8") as f_in, open(
            s_path, "w", encoding="utf-8"
        ) as f_out:
            ret = subprocess.run(
                ["python3", "-m", "ilisp", COMPILER_SCM],
                stdin=f_in,
                stdout=f_out,
                stderr=subprocess.PIPE,
                cwd=WORKSPACE_DIR,
                text=True,
            )
        assert ret.returncode == 0, f"Compilation failed: {ret.stderr}"

        link_res = subprocess.run(
            ["gcc", "-nostdlib", "-static", s_path, "-o", bin_path],
            capture_output=True,
            text=True,
        )
        assert link_res.returncode == 0, f"Linking failed: {link_res.stderr}"

        run_res = subprocess.run([bin_path], capture_output=True)
        assert run_res.returncode == 0
        output = run_res.stdout.decode("utf-8")
        assert "LOOP_RESULT: 5050" in output
        assert "STACK_PROMOTION_HEAP_DELTA_ZERO" in output


def test_bare_metal_nursery_generational_gc():
    """Verify that Generational Copying GC promotes surviving objects and resets nursery."""
    with open(POSIX_SCM, "r", encoding="utf-8") as f:
        posix_code = f.read()
    with open(GC_SCM, "r", encoding="utf-8") as f:
        gc_code = f.read()

    test_scm_code = f"""
{posix_code}
{gc_code}

(define (deep-frame-minor-gc-trigger root-pair mature-from nursery-base)
  ;; 3. Trigger minor GC explicitly from deep frame where root-pair is live in caller
  (gc-minor-collect! (%get-rsp))

  ;; 4. Verify that root-pair was promoted into mature-from space
  (let ((addr (%ptr-untag root-pair)))
    (if (and (>= addr mature-from) (< addr (%ptr-add mature-from 16384)))
        (sys-write-string "ROOT_PROMOTED_TO_MATURE\\n")
        (sys-write-string "ROOT_NOT_PROMOTED\\n")))

  ;; 5. Verify field integrity after promotion
  (if (and (= (car root-pair) 42) (= (cdr root-pair) 99))
      (sys-write-string "NURSERY_PROMOTION_SUCCESS\\n")
      (sys-write-string "FIELD_CORRUPTION\\n"))

  ;; 6. Verify that nursery bump pointer was reset to nursery-base
  (if (= (%get-heap-ptr) nursery-base)
      (sys-write-string "NURSERY_RESET_ZERO_COST\\n")
      (sys-write-string "NURSERY_NOT_RESET\\n"))

  ;; 7. Verify minor collection count is 1
  (if (= (gc-minor-count) 1)
      (sys-write-string "MINOR_COUNT_IS_ONE\\n")
      (sys-write-string "MINOR_COUNT_INVALID\\n")))

(define (run-generational-test)
  (let* ((nursery-base (sys-mmap 4096))
         (mature-from  (sys-mmap 16384))
         (mature-to    (sys-mmap 16384))
         (remset       (sys-mmap 4096)))
    ;; 1. Initialize generational GC
    (gc-init-generational! nursery-base 4096 mature-from mature-to 16384 (%get-rsp) remset)

    ;; 2. Allocate surviving root object in nursery
    (let ((root-pair (cons 42 99)))
      (deep-frame-minor-gc-trigger root-pair mature-from nursery-base))))

(run-generational-test)
(sys-exit 0)
"""

    with tempfile.TemporaryDirectory() as tmpdir:
        src_path = os.path.join(tmpdir, "gen_gc.scm")
        s_path = os.path.join(tmpdir, "gen_gc.s")
        bin_path = os.path.join(tmpdir, "gen_gc_bare")

        with open(src_path, "w", encoding="utf-8") as f:
            f.write(test_scm_code)

        with open(src_path, "r", encoding="utf-8") as f_in, open(
            s_path, "w", encoding="utf-8"
        ) as f_out:
            ret = subprocess.run(
                ["python3", "-m", "ilisp", COMPILER_SCM],
                stdin=f_in,
                stdout=f_out,
                stderr=subprocess.PIPE,
                cwd=WORKSPACE_DIR,
                text=True,
            )
        assert ret.returncode == 0, f"Compilation failed: {ret.stderr}"

        link_res = subprocess.run(
            ["gcc", "-nostdlib", "-static", s_path, "-o", bin_path],
            capture_output=True,
            text=True,
        )
        assert link_res.returncode == 0, f"Linking failed: {link_res.stderr}"

        run_res = subprocess.run([bin_path], capture_output=True)
        assert run_res.returncode == 0
        output = run_res.stdout.decode("utf-8")
        assert "ROOT_PROMOTED_TO_MATURE" in output
        assert "NURSERY_PROMOTION_SUCCESS" in output
        assert "NURSERY_RESET_ZERO_COST" in output
        assert "MINOR_COUNT_IS_ONE" in output


def test_bare_metal_gc_directive_default_all():
    """Verify that default (no directive) selects 'all' GC mode with 128-byte state in BSS."""
    with open(POSIX_SCM, "r", encoding="utf-8") as f:
        posix_code = f.read()

    test_scm_code = f"""
{posix_code}

(sys-write-string "DEFAULT_ALL_GC_SUCCESS\\n")
(sys-exit 0)
"""
    with tempfile.TemporaryDirectory() as tmpdir:
        src_path = os.path.join(tmpdir, "default_gc.scm")
        s_path = os.path.join(tmpdir, "default_gc.s")
        bin_path = os.path.join(tmpdir, "default_gc_bare")

        with open(src_path, "w", encoding="utf-8") as f:
            f.write(test_scm_code)

        with open(src_path, "r", encoding="utf-8") as f_in, open(
            s_path, "w", encoding="utf-8"
        ) as f_out:
            ret = subprocess.run(
                ["python3", "-m", "ilisp", COMPILER_SCM],
                stdin=f_in,
                stdout=f_out,
                stderr=subprocess.PIPE,
                cwd=WORKSPACE_DIR,
                text=True,
            )
        assert ret.returncode == 0, f"Compilation failed: {ret.stderr}"

        # Verify assembly contains .space 128 for ulisp_gc_state
        with open(s_path, "r", encoding="utf-8") as f_asm:
            asm_content = f_asm.read()
            assert "ulisp_gc_state:" in asm_content
            assert ".space 128" in asm_content

        link_res = subprocess.run(
            ["gcc", "-nostdlib", "-static", s_path, "-o", bin_path],
            capture_output=True,
            text=True,
        )
        assert link_res.returncode == 0, f"Linking failed: {link_res.stderr}"

        run_res = subprocess.run([bin_path], capture_output=True)
        assert run_res.returncode == 0
        output = run_res.stdout.decode("utf-8")
        assert "DEFAULT_ALL_GC_SUCCESS" in output


def test_bare_metal_gc_directive_none_arena():
    """Verify that (!gc none) emits 0-byte GC state in BSS for arena bump allocation."""
    with open(POSIX_SCM, "r", encoding="utf-8") as f:
        posix_code = f.read()

    test_scm_code = f"""
(!gc none)
{posix_code}

;; Allocate objects purely with arena bump pointer
(let ((p1 (cons 10 20))
      (p2 (cons 30 40)))
  (if (and (= (car p1) 10) (= (cdr p2) 40))
      (sys-write-string "ARENA_NONE_SUCCESS\\n")
      (sys-write-string "ARENA_FAIL\\n")))
(sys-exit 0)
"""
    with tempfile.TemporaryDirectory() as tmpdir:
        src_path = os.path.join(tmpdir, "none_gc.scm")
        s_path = os.path.join(tmpdir, "none_gc.s")
        bin_path = os.path.join(tmpdir, "none_gc_bare")

        with open(src_path, "w", encoding="utf-8") as f:
            f.write(test_scm_code)

        with open(src_path, "r", encoding="utf-8") as f_in, open(
            s_path, "w", encoding="utf-8"
        ) as f_out:
            ret = subprocess.run(
                ["python3", "-m", "ilisp", COMPILER_SCM],
                stdin=f_in,
                stdout=f_out,
                stderr=subprocess.PIPE,
                cwd=WORKSPACE_DIR,
                text=True,
            )
        assert ret.returncode == 0, f"Compilation failed: {ret.stderr}"

        # Verify assembly contains ulisp_gc_state: without .space (0-byte)
        with open(s_path, "r", encoding="utf-8") as f_asm:
            asm_content = f_asm.read()
            assert "ulisp_gc_state:" in asm_content
            # Neither .space 64 nor .space 128 should follow ulisp_gc_state
            gc_state_idx = asm_content.find("ulisp_gc_state:")
            peek_buf_idx = asm_content.find("ulisp_peek_buf:")
            between = asm_content[gc_state_idx:peek_buf_idx]
            assert ".space" not in between

        link_res = subprocess.run(
            ["gcc", "-nostdlib", "-static", s_path, "-o", bin_path],
            capture_output=True,
            text=True,
        )
        assert link_res.returncode == 0, f"Linking failed: {link_res.stderr}"

        run_res = subprocess.run([bin_path], capture_output=True)
        assert run_res.returncode == 0
        output = run_res.stdout.decode("utf-8")
        assert "ARENA_NONE_SUCCESS" in output


def test_bare_metal_gc_directive_dual_space():
    """Verify that (!gc dual-space) emits 64-byte GC state in BSS for Cheney 2-space GC."""
    with open(POSIX_SCM, "r", encoding="utf-8") as f:
        posix_code = f.read()

    test_scm_code = f"""
(!gc dual-space)
{posix_code}

(sys-write-string "DUAL_SPACE_SUCCESS\\n")
(sys-exit 0)
"""
    with tempfile.TemporaryDirectory() as tmpdir:
        src_path = os.path.join(tmpdir, "dual_space_gc.scm")
        s_path = os.path.join(tmpdir, "dual_space_gc.s")
        bin_path = os.path.join(tmpdir, "dual_space_gc_bare")

        with open(src_path, "w", encoding="utf-8") as f:
            f.write(test_scm_code)

        with open(src_path, "r", encoding="utf-8") as f_in, open(
            s_path, "w", encoding="utf-8"
        ) as f_out:
            ret = subprocess.run(
                ["python3", "-m", "ilisp", COMPILER_SCM],
                stdin=f_in,
                stdout=f_out,
                stderr=subprocess.PIPE,
                cwd=WORKSPACE_DIR,
                text=True,
            )
        assert ret.returncode == 0, f"Compilation failed: {ret.stderr}"

        # Verify assembly contains .space 64 for ulisp_gc_state
        with open(s_path, "r", encoding="utf-8") as f_asm:
            asm_content = f_asm.read()
            assert "ulisp_gc_state:" in asm_content
            gc_state_idx = asm_content.find("ulisp_gc_state:")
            peek_buf_idx = asm_content.find("ulisp_peek_buf:")
            between = asm_content[gc_state_idx:peek_buf_idx]
            assert ".space 64" in between
            assert ".space 128" not in between

        link_res = subprocess.run(
            ["gcc", "-nostdlib", "-static", s_path, "-o", bin_path],
            capture_output=True,
            text=True,
        )
        assert link_res.returncode == 0, f"Linking failed: {link_res.stderr}"

        run_res = subprocess.run([bin_path], capture_output=True)
        assert run_res.returncode == 0
        output = run_res.stdout.decode("utf-8")
        assert "DUAL_SPACE_SUCCESS" in output


def test_bare_metal_automatic_gc_stress():
    """Verify that %alloc slowpath automatically triggers copying GC repeatedly under small heap."""
    with open(POSIX_SCM, "r", encoding="utf-8") as f:
        posix_code = f.read()

    test_scm_code = f"""
(!gc dual-space)
{posix_code}

(define (stress-loop count acc)
  (if (<= count 0)
      acc
      (stress-loop (- count 1) (cons (car acc) count))))

;; Restrict heap to a tiny 16KB from-space and 16KB to-space
(let* ((st-ptr (%get-gc-state-ptr))
       (lim-ptr (%get-heap-limit-ptr))
       (from (%raw-load st-ptr 0))
       (small-size 16384))
  (%raw-store! st-ptr 16 (%to-raw small-size))
  (let ((to (%raw-load st-ptr 8)))
    (%raw-store! st-ptr 40 to)
    (%raw-store! lim-ptr 0 (%ptr-add from small-size)))

  ;; Allocate 10,000 cons cells (240,000 bytes) in a 16KB heap (~15 automatic GC cycles)
  (let ((res (stress-loop 10000 (cons 1 2))))
    (if (and (pair? res) (= (car res) 1))
        (sys-write-string "AUTO_GC_STRESS_SUCCESS\\n")
        (sys-write-string "AUTO_GC_CORRUPTION\\n"))))

(sys-exit 0)
"""
    with tempfile.TemporaryDirectory() as tmpdir:
        src_path = os.path.join(tmpdir, "stress_gc.scm")
        s_path = os.path.join(tmpdir, "stress_gc.s")
        bin_path = os.path.join(tmpdir, "stress_gc_bare")

        with open(src_path, "w", encoding="utf-8") as f:
            f.write(test_scm_code)

        with open(src_path, "r", encoding="utf-8") as f_in, open(
            s_path, "w", encoding="utf-8"
        ) as f_out:
            ret = subprocess.run(
                ["python3", "-m", "ilisp", COMPILER_SCM],
                stdin=f_in,
                stdout=f_out,
                stderr=subprocess.PIPE,
                cwd=WORKSPACE_DIR,
                text=True,
            )
        assert ret.returncode == 0, f"Compilation failed: {ret.stderr}"

        link_res = subprocess.run(
            ["gcc", "-nostdlib", "-static", s_path, "-o", bin_path],
            capture_output=True,
            text=True,
        )
        assert link_res.returncode == 0, f"Linking failed: {link_res.stderr}"

        run_res = subprocess.run([bin_path], capture_output=True)
        assert run_res.returncode == 0
        output = run_res.stdout.decode("utf-8")
        assert "AUTO_GC_STRESS_SUCCESS" in output
