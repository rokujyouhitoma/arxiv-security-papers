"""ULisp Native AOT Code Generation Backend for ILISP.

Compiles ILISP S-expression programs into standalone x86-64 ELF native binaries
via the ULisp self-hosting AOT compiler engine and GCC/Clang toolchain.
Conforms to DSN-33 and DSN-31 (Backend B) architecture specifications.
"""

from __future__ import annotations

from ilisp.backend.ulisp_codegen.compiler import (
    compile_to_assembly,
    compile_to_elf,
    run_elf,
)
from ilisp.backend.ulisp_codegen.transpiler import (
    UlispCodegenError,
    UlispTranspileError,
    UlispTranspiler,
    transpile_for_ulisp,
)

__all__ = [
    "UlispCodegenError",
    "UlispTranspileError",
    "UlispTranspiler",
    "compile_to_assembly",
    "compile_to_elf",
    "run_elf",
    "transpile_for_ulisp",
]
