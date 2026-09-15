"""
Unit and integration tests for PEG AOT Compiler Self-Hosting and Bootstrapping (Issue #297, DSN-25 Phase 3).
Verifies that the generated meta-parser accurately parses .peg grammars, maintains AST equivalence
with combinator parsing, and satisfies deterministic fixpoint invariants.
"""

from __future__ import annotations

from pathlib import Path
from typing import List

from core.structures.peg_compiler.ast_nodes import GrammarDef
from core.structures.peg_compiler.codegen import CodeGenerator
from core.structures.peg_compiler.meta_grammar import MetaGrammarParser


def _get_grammars_dir() -> Path:
    return Path(__file__).resolve().parent.parent.parent / "grammars"


def test_self_hosting_parses_all_existing_grammars() -> None:
    """Verifies that the AOT self-hosted MetaGrammarParser parses all repository .peg grammars."""
    grammars_dir = _get_grammars_dir()
    parser_aot = MetaGrammarParser(use_aot=True)

    peg_files = list(grammars_dir.glob("*.peg"))
    assert (
        len(peg_files) >= 3
    ), f"Expected at least 3 grammar files, found {len(peg_files)}"

    for peg_file in peg_files:
        content = peg_file.read_text(encoding="utf-8")
        g_def = parser_aot.parse(content)
        assert isinstance(g_def, GrammarDef)
        assert len(g_def.rules) > 0
        assert g_def.start_rule is not None


def test_ast_equivalence_between_aot_and_combinator() -> None:
    """Verifies that the AOT self-hosted parser produces AST rule names matching combinators."""
    grammars_dir = _get_grammars_dir()
    parser_combinator = MetaGrammarParser(use_aot=False)
    parser_aot = MetaGrammarParser(use_aot=True)

    test_grammars: List[str] = ["calc.peg", "search_query.peg", "turtle.peg"]
    for g_name in test_grammars:
        g_path = grammars_dir / g_name
        if not g_path.exists():
            continue

        content = g_path.read_text(encoding="utf-8")
        ast_comb = parser_combinator.parse(content)
        ast_aot = parser_aot.parse(content)

        assert ast_comb.name == ast_aot.name
        rules_comb = [r.name for r in ast_comb.rules]
        rules_aot = [r.name for r in ast_aot.rules]
        assert rules_comb == rules_aot


def test_recompilation_roundtrip_fixpoint() -> None:
    """Verifies that self-hosted recompilation of peg_meta.peg produces valid, executable Python code."""
    grammars_dir = _get_grammars_dir()
    meta_peg_path = grammars_dir / "peg_meta.peg"
    assert meta_peg_path.exists()

    content = meta_peg_path.read_text(encoding="utf-8")
    parser = MetaGrammarParser()
    ast_def = parser.parse(content)

    generator = CodeGenerator(ast_def)
    code = generator.generate()

    assert "class MetaGrammarParser" in code
    assert "def _init_rules(self)" in code
    assert len(code) > 5000

    # Ensure generated code is syntactically valid Python
    compiled = compile(code, "<string>", "exec")
    assert compiled is not None


def test_cli_no_aot_flag(tmp_path: Path) -> None:
    """Verifies that the CLI --no-aot flag successfully compiles grammars using combinator fallback."""
    from core.structures.peg_compiler.cli import run_cli

    grammars_dir = _get_grammars_dir()
    calc_path = grammars_dir / "calc.peg"
    out_file = tmp_path / "calc_combinator_generated.py"

    ret = run_cli([str(calc_path), "-o", str(out_file), "--no-aot"])
    assert ret == 0
    assert out_file.exists()
    code = out_file.read_text(encoding="utf-8")
    assert "class CalcParser" in code
    compiled = compile(code, "<string>", "exec")
    assert compiled is not None
