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
