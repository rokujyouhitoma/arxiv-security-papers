#!/usr/bin/env python3
"""
Command Line Interface (CLI) for PEG Ahead-of-Time Compiler.
Conforms to DSN-25 Phase 2 Ahead-of-Time PEG Compiler specification.
Zero external dependencies.
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path
from typing import List, Optional

from core.structures.peg import PEGSyntaxError
from core.structures.peg_compiler.codegen import CodeGenerator
from core.structures.peg_compiler.meta_grammar import MetaGrammarParser


def compile_grammar_to_code(
    grammar_text: str,
    class_name_override: Optional[str] = None,
    use_aot: bool = True,
) -> str:
    """Compiles .peg grammar text into Python source code string."""
    parser = MetaGrammarParser(use_aot=use_aot)
    grammar_ast = parser.parse(grammar_text)
    if class_name_override:
        # Create updated GrammarDef with overridden name
        from dataclasses import replace

        grammar_ast = replace(grammar_ast, name=class_name_override)
    generator = CodeGenerator(grammar_ast)
    return generator.generate()


def run_cli(args: Optional[List[str]] = None) -> int:
    """CLI execution entrypoint."""
    arg_parser = argparse.ArgumentParser(
        prog="peg-compiler",
        description="DSN-25 Ahead-of-Time Packrat PEG Parser Compiler",
    )
    arg_parser.add_argument(
        "grammar_file",
        type=str,
        help="Path to input .peg grammar definition file",
    )
    arg_parser.add_argument(
        "-o",
        "--output",
        type=str,
        default=None,
        help="Path to output .py generated parser file (default: stdout)",
    )
    arg_parser.add_argument(
        "--class-name",
        type=str,
        default=None,
        help="Override generated parser class name",
    )
    arg_parser.add_argument(
        "--no-aot",
        action="store_true",
        help="Disable AOT compiled meta-parser and use runtime combinators",
    )

    parsed = arg_parser.parse_args(args)
    input_path = Path(parsed.grammar_file)
    if not input_path.exists():
        sys.stderr.write(f"Error: grammar file '{parsed.grammar_file}' not found.\n")
        return 1

    try:
        content = input_path.read_text(encoding="utf-8")
        generated_code = compile_grammar_to_code(
            content,
            class_name_override=parsed.class_name,
            use_aot=not parsed.no_aot,
        )
    except PEGSyntaxError as exc:
        sys.stderr.write(f"PEG Grammar Syntax Error:\n{exc}\n")
        return 1
    except Exception as exc:
        sys.stderr.write(f"Compiler Error: {exc}\n")
        return 1

    if parsed.output:
        out_path = Path(parsed.output)
        out_path.parent.mkdir(parents=True, exist_ok=True)
        out_path.write_text(generated_code, encoding="utf-8")
    else:
        sys.stdout.write(generated_code)

    return 0


if __name__ == "__main__":
    sys.exit(run_cli())
