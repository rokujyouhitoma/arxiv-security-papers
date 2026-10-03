#!/usr/bin/env python3
"""
Command Line Interface (CLI) for PEG Ahead-of-Time Compiler.
Conforms to DSN-25 Phase 2 Ahead-of-Time PEG Compiler specification.
Supports multi-language code generation (Python & JavaScript).
Zero external dependencies.
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path
from typing import List, Optional

from core.structures.peg import PEGSyntaxError
from core.structures.peg_compiler.codegen import CodeGenerator
from core.structures.peg_compiler.codegen_js import JSCodeGenerator
from core.structures.peg_compiler.meta_grammar import MetaGrammarParser
from core.structures.peg_compiler.optimizer import GrammarOptimizer


def compile_grammar_to_code(
    grammar_text: str,
    class_name_override: Optional[str] = None,
    use_aot: bool = True,
    optimize: bool = True,
    target: str = "python",
) -> str:
    """Compiles .peg grammar text into Python or JavaScript source code string."""
    parser = MetaGrammarParser(use_aot=use_aot)
    grammar_ast = parser.parse(grammar_text)
    if class_name_override:
        from dataclasses import replace

        grammar_ast = replace(grammar_ast, name=class_name_override)
    if optimize:
        optimizer = GrammarOptimizer()
        grammar_ast = optimizer.optimize_grammar(grammar_ast)

    normalized_target = target.lower().strip()
    if normalized_target in ("js", "javascript"):
        generator_js = JSCodeGenerator(grammar_ast)
        return generator_js.generate()

    generator_py = CodeGenerator(grammar_ast)
    return generator_py.generate()


def _build_arg_parser() -> argparse.ArgumentParser:
    """Builds CLI argument parser."""
    parser = argparse.ArgumentParser(
        prog="peg-compiler",
        description="DSN-25 Ahead-of-Time Packrat PEG Parser Compiler",
    )
    parser.add_argument(
        "grammar_file", type=str, help="Path to input .peg grammar file"
    )
    parser.add_argument(
        "-o", "--output", type=str, default=None, help="Path to output file"
    )
    parser.add_argument(
        "--target",
        choices=["python", "js", "javascript"],
        default=None,
        help="Target programming language (python, js)",
    )
    parser.add_argument(
        "--class-name", type=str, default=None, help="Override class name"
    )
    parser.add_argument("--no-aot", action="store_true", help="Disable AOT meta-parser")
    parser.add_argument(
        "--no-optimize", action="store_true", help="Disable AST optimization"
    )
    return parser


def _resolve_target(target: Optional[str], output: Optional[str]) -> str:
    """Infers code generation target from arguments and output filename."""
    if target is not None:
        return target
    if output and output.endswith(".js"):
        return "js"
    return "python"


def _write_output(generated_code: str, output: Optional[str]) -> None:
    """Writes output string to file or stdout."""
    if output:
        out_path = Path(output)
        out_path.parent.mkdir(parents=True, exist_ok=True)
        out_path.write_text(generated_code, encoding="utf-8")
    else:
        sys.stdout.write(generated_code)


def run_cli(args: Optional[List[str]] = None) -> int:
    """CLI execution entrypoint."""
    parsed = _build_arg_parser().parse_args(args)
    input_path = Path(parsed.grammar_file)
    if not input_path.exists():
        sys.stderr.write(f"Error: grammar file '{parsed.grammar_file}' not found.\n")
        return 1

    target = _resolve_target(parsed.target, parsed.output)

    try:
        content = input_path.read_text(encoding="utf-8")
        generated_code = compile_grammar_to_code(
            content,
            class_name_override=parsed.class_name,
            use_aot=not parsed.no_aot,
            optimize=not parsed.no_optimize,
            target=target,
        )
    except PEGSyntaxError as exc:
        sys.stderr.write(f"PEG Grammar Syntax Error:\n{exc}\n")
        return 1
    except Exception as exc:
        sys.stderr.write(f"Compiler Error: {exc}\n")
        return 1

    _write_output(generated_code, parsed.output)
    return 0


if __name__ == "__main__":
    sys.exit(run_cli())
