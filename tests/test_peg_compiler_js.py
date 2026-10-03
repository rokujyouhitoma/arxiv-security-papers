#!/usr/bin/env python3
"""
Unit and integration tests for DSN-25 Packrat PEG JavaScript Code Generator (Issue 417).
Verifies:
1. JSCodeGenerator emits standalone, valid JavaScript code.
2. Generated JavaScript parsers execute successfully in Node.js runtime.
3. CLI `--target js` and automatic `.js` output extension detection.
"""

from __future__ import annotations

import json
import shutil
import subprocess
import tempfile
from pathlib import Path

import pytest

from core.structures.peg_compiler import compile_grammar_to_code
from core.structures.peg_compiler.cli import run_cli


@pytest.fixture
def node_bin() -> str:
    path = shutil.which("node")
    if not path:
        pytest.skip("Node.js runtime not installed")
    return path


SIMPLE_ARITH_GRAMMAR = """
grammar Arithmetic

expr <- head:term rest:(_ op:("+" / "-") _ right:term)*
term <- head:factor rest:(_ op:("*" / "/") _ right:factor)*
factor <- number / "(" _ inner:expr _ ")"
number <- [0-9]+
_ <- [ \t]*
"""


def test_js_code_generator_compilation(node_bin: str) -> None:
    """Verifies that JSCodeGenerator compiles grammar AST to runnable JavaScript."""
    js_code = compile_grammar_to_code(SIMPLE_ARITH_GRAMMAR, target="js")
    assert "ArithmeticParser" in js_code
    assert "ParseResult" in js_code
    assert "ParseContext" in js_code
    assert "function lit(" in js_code or "function reg(" in js_code

    # Execute inside Node.js to verify syntax validity and functionality
    with tempfile.TemporaryDirectory() as tmp_dir:
        js_file = Path(tmp_dir) / "arithmetic_parser.js"
        js_file.write_text(js_code, encoding="utf-8")

        test_script = f"""
        const {{ ArithmeticParser }} = require({json.dumps(str(js_file))});
        const parser = new ArithmeticParser();

        const res1 = parser.parse("42");
        const res2 = parser.parse("1 + 2 * 3");

        console.log(JSON.stringify({{
            parsed1: res1 !== null,
            parsed2: res2 !== null
        }}));
        """
        res = subprocess.run(
            [node_bin, "-e", test_script],
            capture_output=True,
            text=True,
            check=True,
        )
        data = json.loads(res.stdout)
        assert data["parsed1"] is True
        assert data["parsed2"] is True


def test_js_code_generator_syntax_error_handling(node_bin: str) -> None:
    """Verifies that generated JavaScript parser throws PEGSyntaxError on invalid input."""
    js_code = compile_grammar_to_code(SIMPLE_ARITH_GRAMMAR, target="js")

    with tempfile.TemporaryDirectory() as tmp_dir:
        js_file = Path(tmp_dir) / "arithmetic_parser.js"
        js_file.write_text(js_code, encoding="utf-8")

        test_script = f"""
        const {{ ArithmeticParser }} = require({json.dumps(str(js_file))});
        const parser = new ArithmeticParser();

        let caught = false;
        try {{
            parser.parse("1 + * 2");
        }} catch (err) {{
            caught = err.name === 'PEGSyntaxError' || err.message.includes('Unconsumed');
        }}

        console.log(JSON.stringify({{ caught }}));
        """
        res = subprocess.run(
            [node_bin, "-e", test_script],
            capture_output=True,
            text=True,
            check=True,
        )
        data = json.loads(res.stdout)
        assert data["caught"] is True


def test_cli_target_js_option(node_bin: str) -> None:
    """Verifies CLI flag --target js and auto-detection with -o parser.js."""
    with tempfile.TemporaryDirectory() as tmp_dir:
        grammar_file = Path(tmp_dir) / "test.peg"
        grammar_file.write_text(
            "grammar Test\nroot <- 'hello' ' '+ 'world'\n", encoding="utf-8"
        )

        out_js = Path(tmp_dir) / "test_parser.js"

        # Test CLI auto-detection from .js extension
        exit_code = run_cli([str(grammar_file), "-o", str(out_js)])
        assert exit_code == 0
        assert out_js.is_file()

        content = out_js.read_text(encoding="utf-8")
        assert "TestParser" in content

        # Run generated parser in Node.js
        test_script = f"""
        const {{ TestParser }} = require({json.dumps(str(out_js))});
        const parser = new TestParser();
        const res = parser.parse("hello   world");
        console.log(JSON.stringify({{ success: !!res }}));
        """
        res = subprocess.run(
            [node_bin, "-e", test_script],
            capture_output=True,
            text=True,
            check=True,
        )
        data = json.loads(res.stdout)
        assert data["success"] is True
