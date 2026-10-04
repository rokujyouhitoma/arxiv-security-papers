"""ILISP Python AST Code Generation Backend (Backend A).

Transpiles Scheme S-expressions into Python standard ast.AST with
Self Tail-Call Optimization (Self-TCO) and Cell boxing for mutated variables.
"""

from ilisp.backend.py_codegen.compiler import PythonASTCompiler, compile_ilisp

__all__ = ["PythonASTCompiler", "compile_ilisp"]
