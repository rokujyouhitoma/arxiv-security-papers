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


def test_js_code_generator_ast_only_mode(node_bin: str) -> None:
    """Verifies that --ast-only bypasses Python action code and yields generic AST nodes."""
    grammar_with_python_action = """
    grammar ActionTest
    expr <- left:ident _ '+' _ right:ident {
        return CustomPythonClass(left=left, right=right)
    }
    ident <- [a-zA-Z]+
    _ <- [ \t]*
    """
    with tempfile.TemporaryDirectory() as tmp_dir:
        out_js = Path(tmp_dir) / "action_test_parser.js"
        js_code = compile_grammar_to_code(
            grammar_with_python_action, target="js", ast_only=True
        )
        out_js.write_text(js_code, encoding="utf-8")

        test_script = f"""
        const {{ ActionTestParser }} = require({json.dumps(str(out_js))});
        const parser = new ActionTestParser();
        const res = parser.parse("foo + bar");
        console.log(JSON.stringify(res));
        """
        proc = subprocess.run(
            [node_bin, "-e", test_script],
            capture_output=True,
            text=True,
            check=True,
        )
        ast = json.loads(proc.stdout)
        assert ast["type"] == "expr"
        assert isinstance(ast["value"], list)


def test_cli_ast_only_with_graph_query_peg(node_bin: str) -> None:
    """Verifies CLI compilation of grammars/graph_query.peg with --ast-only."""
    graph_query_peg = Path("grammars/graph_query.peg")
    assert graph_query_peg.exists()

    with tempfile.TemporaryDirectory() as tmp_dir:
        out_js = Path(tmp_dir) / "graph_query_ast_parser.js"
        exit_code = run_cli(
            [str(graph_query_peg), "-o", str(out_js), "--target", "js", "--ast-only"]
        )
        assert exit_code == 0
        assert out_js.is_file()

        test_script = f"""
        const {{ GraphQueryParser }} = require({json.dumps(str(out_js))});
        const parser = new GraphQueryParser();
        const res = parser.parse("(p:Paper) -> (c:CVE)");
        console.log(JSON.stringify({{ success: res && res.type === 'query' }}));
        """
        proc = subprocess.run(
            [node_bin, "-e", test_script],
            capture_output=True,
            text=True,
            check=True,
        )
        data = json.loads(proc.stdout)
        assert data["success"] is True


def test_warth_left_recursion_in_generated_js(node_bin: str) -> None:
    """Verifies that Warth et al. ('08) left-recursion seed growing works in generated JS."""
    grammar = """
    grammar LeftRecCalc
    expr <- left:expr _ '+' _ right:num {
        return left + right;
    } / num
    num <- [0-9]+ {
        return parseInt(val.join(''), 10);
    }
    _ <- [ \t]*
    """
    with tempfile.TemporaryDirectory() as tmp_dir:
        out_js = Path(tmp_dir) / "lr_calc_parser.js"
        js_code = compile_grammar_to_code(grammar, target="js")
        out_js.write_text(js_code, encoding="utf-8")

        test_script = f"""
        const {{ LeftRecCalcParser }} = require({json.dumps(str(out_js))});
        const parser = new LeftRecCalcParser();
        // 1 + 2 + 3 + 4 -> evaluates left-associatively without stack overflow
        const res = parser.parse("1 + 2 + 3 + 4");
        console.log(JSON.stringify({{ res: res }}));
        """
        proc = subprocess.run(
            [node_bin, "-e", test_script],
            capture_output=True,
            text=True,
            check=True,
        )
        data = json.loads(proc.stdout)
        assert data["res"] == 10


def test_char_class_range_evaluation_in_generated_js(node_bin: str) -> None:
    """Verifies that CharClass uses direct character code range comparison instead of RegExp."""
    grammar = r"""
    grammar CharClassDemo
    entry <- id:ident ':' _ content:non_digit _ sep:special {
        return { id: id, val: content, sep: sep };
    }
    ident <- head:[a-zA-Z_] tail:[a-zA-Z0-9_]* {
        return head + tail.join('');
    }
    non_digit <- [^0-9 \t\r\n]+ {
        return val.join('');
    }
    special <- [\]\-\/\n\t]
    _ <- [ \t]*
    """
    with tempfile.TemporaryDirectory() as tmp_dir:
        out_js = Path(tmp_dir) / "char_class_parser.js"
        js_code = compile_grammar_to_code(grammar, target="js")
        out_js.write_text(js_code, encoding="utf-8")

        # 1. Verify no new RegExp('[') is emitted for CharClass
        assert "new RegExp('[" not in js_code
        assert 'new RegExp("[' not in js_code
        assert "charClass([[65, 90], [97, 122]], [95], false" in js_code

        # 2. Execute with Node.js
        test_script = f"""
        const {{ CharClassDemoParser }} = require({json.dumps(str(out_js))});
        const parser = new CharClassDemoParser();
        const res1 = parser.parse("foo_bar: hello_world /");
        const res2 = parser.parse("_test123: abc-def ]");
        console.log(JSON.stringify({{ res1: res1, res2: res2 }}));
        """
        proc = subprocess.run(
            [node_bin, "-e", test_script],
            capture_output=True,
            text=True,
            check=True,
        )
        data = json.loads(proc.stdout)
        assert data["res1"]["id"] == "foo_bar"
        assert data["res1"]["val"] == "hello_world"
        assert data["res1"]["sep"] == "/"
        assert data["res2"]["id"] == "_test123"
        assert data["res2"]["val"] == "abc-def"
        assert data["res2"]["sep"] == "]"
