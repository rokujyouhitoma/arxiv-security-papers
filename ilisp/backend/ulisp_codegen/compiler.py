"""ULisp Native AOT Assembly and ELF Compiler Pipeline for ILISP.

Drives the ULisp compiler engine to emit x86-64 GAS assembly and links with
the minimal C runtime using GCC/Clang to produce standalone native ELF binaries.
Conforms to DSN-33 and DSN-31 (Backend B) architecture specifications.
"""

from __future__ import annotations

import os
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import Any, Optional, Sequence, Union

from ilisp.backend.ulisp_codegen.transpiler import UlispCodegenError, UlispTranspiler

__all__ = [
    "UlispCodegenError",
    "compile_to_assembly",
    "compile_to_elf",
    "run_elf",
]


def _find_repo_root() -> Path:
    """Locate the root directory of the arxiv-security-papers repository."""
    curr = Path(__file__).resolve().parent
    for p in [curr] + list(curr.parents):
        if (p / "ulisp").is_dir() and (p / "docs").is_dir():
            return p
    # Fallback to current working directory
    return Path.cwd()


def _get_ulisp_dir() -> Path:
    """Locate the ulisp/ directory containing compiler.scm and runtime.c."""
    repo_root = _find_repo_root()
    ulisp_dir = repo_root / "ulisp"
    if not ulisp_dir.is_dir():
        raise UlispCodegenError(f"ULisp directory not found at {ulisp_dir}")
    return ulisp_dir


def _ensure_ulisp_core(ulisp_dir: Path) -> Path:
    """Ensure build/ulisp_core.scm is concatenated and available."""
    build_dir = ulisp_dir / "build"
    build_dir.mkdir(parents=True, exist_ok=True)
    core_path = build_dir / "ulisp_core.scm"

    lib_files = [
        ulisp_dir / "lib" / "string.scm",
        ulisp_dir / "lib" / "printer.scm",
        ulisp_dir / "lib" / "reader.scm",
        ulisp_dir / "compiler.scm",
    ]

    # Check if core needs rebuild
    needs_rebuild = not core_path.exists()
    if not needs_rebuild:
        core_mtime = core_path.stat().st_mtime
        for lf in lib_files:
            if lf.exists() and lf.stat().st_mtime > core_mtime:
                needs_rebuild = True
                break

    if needs_rebuild:
        content_parts: list[str] = []
        for lf in lib_files:
            if lf.exists():
                content_parts.append(lf.read_text(encoding="utf-8"))
            else:
                raise UlispCodegenError(f"Missing required ULisp source file: {lf}")
        core_path.write_text("\n".join(content_parts), encoding="utf-8")

    return core_path


def _resolve_compiler_input(scheme_code: str, target_ulisp_dir: Path) -> str:
    """Prepend required standard library modules based on code features."""
    prepend_parts: list[str] = []

    # Check for printer library requirements
    needs_printer_lib = (
        "display" in scheme_code or "write" in scheme_code or "newline" in scheme_code
    )

    # Check for string/symbol library requirements (printer depends on string.scm)
    needs_string_lib = (
        needs_printer_lib
        or "string->symbol" in scheme_code
        or "symbol->string" in scheme_code
        or "number->string" in scheme_code
        or "'" in scheme_code
    )

    if needs_string_lib:
        str_scm = target_ulisp_dir / "lib" / "string.scm"
        if str_scm.is_file():
            prepend_parts.append(str_scm.read_text(encoding="utf-8"))

    if needs_printer_lib:
        prn_scm = target_ulisp_dir / "lib" / "printer.scm"
        if prn_scm.is_file():
            prepend_parts.append(prn_scm.read_text(encoding="utf-8"))

    if prepend_parts:
        return "\n".join(prepend_parts) + "\n" + scheme_code
    return scheme_code


def compile_to_assembly(
    source: Union[str, Sequence[Any]],
    *,
    transpiler: Optional[UlispTranspiler] = None,
    ulisp_dir: Optional[Path] = None,
) -> str:
    """Compile Scheme source code or S-expression ASTs into x86-64 GAS assembly string."""
    if transpiler is None:
        transpiler = UlispTranspiler()

    scheme_code = transpiler.transpile(source)
    target_ulisp_dir = ulisp_dir or _get_ulisp_dir()
    compiler_path = target_ulisp_dir / "compiler.scm"
    if not compiler_path.is_file():
        raise UlispCodegenError(f"ULisp compiler not found at {compiler_path}")

    full_input = _resolve_compiler_input(scheme_code, target_ulisp_dir)

    repo_root = _find_repo_root()
    env = os.environ.copy()
    env["PYTHONPATH"] = str(repo_root)

    cmd = [sys.executable, "-m", "ilisp", str(compiler_path)]
    try:
        proc = subprocess.run(
            cmd,
            input=full_input,
            capture_output=True,
            text=True,
            check=False,
            env=env,
            cwd=str(target_ulisp_dir),
        )
    except Exception as exc:
        raise UlispCodegenError(
            f"Failed to execute ULisp compiler subprocess: {exc}"
        ) from exc

    if proc.returncode != 0:
        err_msg = proc.stderr.strip() or proc.stdout.strip()
        raise UlispCodegenError(
            f"ULisp compilation failed with exit code {proc.returncode}:\n{err_msg}"
        )

    asm_output = proc.stdout
    if not asm_output.strip():
        raise UlispCodegenError("ULisp compiler produced empty assembly output")

    return asm_output


def compile_to_elf(
    source: Union[str, Sequence[Any]],
    output_path: Union[str, Path],
    *,
    opt_level: str = "-O2",
    cc: str = "gcc",
    ulisp_dir: Optional[Path] = None,
) -> Path:
    """Compile Scheme code into a standalone native Linux ELF binary."""
    asm_code = compile_to_assembly(source, ulisp_dir=ulisp_dir)
    target_ulisp_dir = ulisp_dir or _get_ulisp_dir()
    runtime_c = target_ulisp_dir / "runtime.c"

    if not runtime_c.is_file():
        raise UlispCodegenError(f"ULisp C runtime not found at {runtime_c}")

    out_file = Path(output_path).resolve()
    out_file.parent.mkdir(parents=True, exist_ok=True)

    with tempfile.TemporaryDirectory(prefix="ulisp_build_") as tmpdir:
        tmp_s = Path(tmpdir) / "source.s"
        tmp_s.write_text(asm_code, encoding="utf-8")

        compile_cmd = [
            cc,
            opt_level,
            "-g",
            "-Wall",
            "-Wextra",
            "-o",
            str(out_file),
            str(runtime_c),
            str(tmp_s),
        ]

        try:
            res = subprocess.run(
                compile_cmd,
                capture_output=True,
                text=True,
                check=False,
            )
        except FileNotFoundError as exc:
            raise UlispCodegenError(f"C compiler '{cc}' not found in PATH") from exc

        if res.returncode != 0:
            raise UlispCodegenError(
                f"Assembler/Linker failed with exit code {res.returncode}:\n{res.stderr.strip()}"
            )

    # Set executable permissions
    try:
        os.chmod(out_file, 0o755)
    except OSError:
        pass

    return out_file


def run_elf(
    binary_path: Union[str, Path],
    stdin_data: str = "",
    *,
    timeout: float = 10.0,
) -> subprocess.CompletedProcess[str]:
    """Execute a compiled ELF binary safely and return CompletedProcess."""
    bpath = Path(binary_path).resolve()
    if not bpath.is_file():
        raise UlispCodegenError(f"Binary file not found: {bpath}")

    return subprocess.run(
        [str(bpath)],
        input=stdin_data,
        capture_output=True,
        text=True,
        timeout=timeout,
        check=False,
    )
