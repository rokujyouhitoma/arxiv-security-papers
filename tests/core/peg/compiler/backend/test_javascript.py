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

from core.peg.compiler import compile_grammar_to_code, run_cli
from core.peg.compiler.backend.javascript import JSCodeGenerator


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
    """Verifies CLI compilation of tools/grammars/graph_query.peg with --ast-only."""
    graph_query_peg = Path("tools/grammars/graph_query.peg")
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


def test_parse_with_diagnostics_and_syntax_error_details(node_bin: str) -> None:
    """Verifies that parseWithDiagnostics returns structured diagnostics without throwing."""
    grammar = r"""
    grammar DiagDemo
    entry <- id:ident ':' _ val:word _ sep:';' {
        return { id: id, val: val };
    }
    ident <- [a-zA-Z_]+ { return val.join(''); }
    word <- [a-z]+ { return val.join(''); }
    _ <- [ \t]*
    """
    with tempfile.TemporaryDirectory() as tmp_dir:
        out_js = Path(tmp_dir) / "diag_demo_parser.js"
        js_code = compile_grammar_to_code(grammar, target="js")
        out_js.write_text(js_code, encoding="utf-8")

        test_script = f"""
        const {{ DiagDemoParser, PEGSyntaxError }} = require({json.dumps(str(out_js))});
        const parser = new DiagDemoParser();

        // 1. Successful parse
        const resOk = parser.parseWithDiagnostics("my_key: validvalue ;");

        // 2. Syntax error in middle
        const resErr = parser.parseWithDiagnostics("my_key: 12345 ;");

        // 3. Trailing unconsumed input
        const resTrailing = parser.parseWithDiagnostics("my_key: validvalue ; extra_garbage");

        // 4. Standard parse throwing PEGSyntaxError with detailed diagnostics
        let thrownError = null;
        try {{
            parser.parse("my_key: 12345 ;");
        }} catch (e) {{
            if (e instanceof PEGSyntaxError) {{
                thrownError = {{
                    message: e.message,
                    offset: e.offset,
                    line: e.line,
                    col: e.col,
                    expectedTokens: e.expectedTokens,
                    snippet: e.snippet
                }};
            }}
        }}

        console.log(JSON.stringify({{
            resOk,
            resErr,
            resTrailing,
            thrownError
        }}));
        """
        proc = subprocess.run(
            [node_bin, "-e", test_script],
            capture_output=True,
            text=True,
            check=True,
        )
        data = json.loads(proc.stdout)

        # 1. Success check
        assert data["resOk"]["success"] is True
        assert data["resOk"]["value"]["id"] == "my_key"
        assert data["resOk"]["value"]["val"] == "validvalue"
        assert data["resOk"]["diagnostics"] is None

        # 2. Middle syntax error check
        assert data["resErr"]["success"] is False
        assert data["resErr"]["value"] is None
        diag = data["resErr"]["diagnostics"]
        assert diag["offset"] == 8
        assert diag["line"] == 1
        assert diag["col"] == 9
        assert isinstance(diag["expectedTokens"], list)
        assert len(diag["expectedTokens"]) > 0
        assert "12345" in diag["snippet"]

        # 3. Trailing check
        assert data["resTrailing"]["success"] is False
        diag_trail = data["resTrailing"]["diagnostics"]
        assert diag_trail["errorMsg"] == "Unconsumed trailing input"
        assert diag_trail["offset"] == 20
        assert diag_trail["expectedTokens"] == ["EOF"]

        # 4. Thrown error check
        err = data["thrownError"]
        assert err is not None
        assert err["offset"] == 8
        assert err["line"] == 1
        assert err["col"] == 9
        assert isinstance(err["expectedTokens"], list)
        assert "12345" in err["snippet"]


def test_generate_runtime_module(node_bin: str, tmp_path: Path) -> None:
    """Verifies that JSCodeGenerator.generate_runtime_module emits valid UMD module."""
    runtime_code = JSCodeGenerator.generate_runtime_module()
    assert "Standalone Packrat PEG Runtime Engine" in runtime_code
    assert "ParseResult: ParseResult" in runtime_code
    assert "PEGSyntaxError: PEGSyntaxError" in runtime_code
    assert "Parser: Parser" in runtime_code
    assert "charClass: charClass" in runtime_code

    runtime_file = tmp_path / "peg-runtime.js"
    runtime_file.write_text(runtime_code, encoding="utf-8")

    test_script = f"""
    const runtime = require({json.dumps(str(runtime_file))});
    const symbols = [
        typeof runtime.ParseResult,
        typeof runtime.PEGSyntaxError,
        typeof runtime.ParseContext,
        typeof runtime.Parser,
        typeof runtime.lit,
        typeof runtime.seq,
        typeof runtime.choice,
        typeof runtime.charClass
    ];
    console.log(JSON.stringify(symbols));
    """
    proc = subprocess.run(
        [node_bin, "-e", test_script],
        capture_output=True,
        text=True,
        check=True,
    )
    symbols = json.loads(proc.stdout)
    assert all(sym == "function" for sym in symbols)


def test_compile_no_runtime_mode() -> None:
    """Verifies that --no-runtime produces concise parser code referencing external runtime."""
    embedded_code = compile_grammar_to_code(
        SIMPLE_ARITH_GRAMMAR, target="js", embedded_runtime=True
    )
    modular_code = compile_grammar_to_code(
        SIMPLE_ARITH_GRAMMAR, target="js", embedded_runtime=False
    )

    # Modular version should be significantly smaller (no runtime class body duplication)
    assert len(modular_code) < len(embedded_code) * 0.4
    assert "Section 1: External Packrat PEG Runtime Resolution" in modular_code
    assert "PEGRuntime not found. Ensure peg-runtime.js is loaded" in modular_code
    assert "function ParseResult(success" not in modular_code


def test_cli_modular_runtime_and_shared_execution(
    tmp_path: Path, node_bin: str
) -> None:
    """Verifies CLI --runtime-only and --no-runtime options with multiple cooperating parsers."""
    # 1. Emit runtime via CLI --runtime-only
    runtime_path = tmp_path / "peg-runtime.js"
    rc_runtime = run_cli(["--runtime-only", "--target", "js", "-o", str(runtime_path)])
    assert rc_runtime == 0
    assert runtime_path.exists()

    # 2. Emit two different parsers with --no-runtime
    arith_grammar_file = tmp_path / "arith.peg"
    arith_grammar_file.write_text(SIMPLE_ARITH_GRAMMAR, encoding="utf-8")
    arith_parser_file = tmp_path / "arith_parser.js"
    rc_arith = run_cli(
        [
            str(arith_grammar_file),
            "-o",
            str(arith_parser_file),
            "--target",
            "js",
            "--no-runtime",
        ]
    )
    assert rc_arith == 0
    assert arith_parser_file.exists()

    kv_grammar = """
    grammar KeyVal
    pair <- k:[a-zA-Z]+ "=" v:[a-zA-Z0-9]+ { return { key: k.join(""), val: v.join("") }; }
    """
    kv_grammar_file = tmp_path / "kv.peg"
    kv_grammar_file.write_text(kv_grammar, encoding="utf-8")
    kv_parser_file = tmp_path / "kv_parser.js"
    rc_kv = run_cli(
        [
            str(kv_grammar_file),
            "-o",
            str(kv_parser_file),
            "--target",
            "js",
            "--no-runtime",
        ]
    )
    assert rc_kv == 0
    assert kv_parser_file.exists()

    # 3. Execute script requiring both parsers sharing peg-runtime.js in same directory
    test_script = f"""
    const {{ ArithmeticParser }} = require({json.dumps(str(arith_parser_file))});
    const {{ KeyValParser }} = require({json.dumps(str(kv_parser_file))});

    const p1 = new ArithmeticParser();
    const res1 = p1.parse("10 + 20 * 3");

    const p2 = new KeyValParser();
    const res2 = p2.parseWithDiagnostics("user=alice");

    console.log(JSON.stringify({{
        res1: res1 !== null,
        res2Success: res2.success,
        res2Val: res2.value
    }}));
    """
    proc = subprocess.run(
        [node_bin, "-e", test_script],
        capture_output=True,
        text=True,
        check=False,
    )
    assert proc.returncode == 0, f"Node execution failed:\n{proc.stderr}\n{proc.stdout}"
    data = json.loads(proc.stdout)

    assert data["res1"] is True
    assert data["res2Success"] is True
    assert data["res2Val"] == {"key": "user", "val": "alice"}


def test_no_runtime_missing_runtime_error(tmp_path: Path, node_bin: str) -> None:
    """Verifies that --no-runtime parser throws clear error when runtime is absent."""
    isolated_dir = tmp_path / "isolated"
    isolated_dir.mkdir(parents=True, exist_ok=True)
    parser_file = isolated_dir / "isolated_parser.js"

    grammar_file = isolated_dir / "test.peg"
    grammar_file.write_text("grammar Test\nrule <- 'ok'\n", encoding="utf-8")

    run_cli(
        [
            str(grammar_file),
            "-o",
            str(parser_file),
            "--target",
            "js",
            "--no-runtime",
        ]
    )

    test_script = f"""
    try {{
        require({json.dumps(str(parser_file))});
        console.log(JSON.stringify({{ error: null }}));
    }} catch (e) {{
        console.log(JSON.stringify({{ error: e.message }}));
    }}
    """
    proc = subprocess.run(
        [node_bin, "-e", test_script],
        capture_output=True,
        text=True,
        check=True,
    )
    data = json.loads(proc.stdout)
    assert data["error"] is not None
    assert "PEGRuntime not found" in data["error"]


def test_cti_query_parser_and_evaluator_integration(node_bin: str) -> None:
    """Verifies that generated CTIQueryParser and CTIQueryEvaluator execute in Node.js."""
    parser_cand = Path("src/web/site/js/frameworks/cti-query-parser.js")
    parser_path = (
        parser_cand
        if parser_cand.exists()
        else Path("site/js/frameworks/cti-query-parser.js")
    )
    eval_cand = Path("src/web/site/js/frameworks/cti-query-evaluator.js")
    evaluator_path = (
        eval_cand
        if eval_cand.exists()
        else Path("site/js/frameworks/cti-query-evaluator.js")
    )
    assert parser_path.exists()
    assert evaluator_path.exists()

    test_script = f"""
    const {{ CTIQueryParser }} = require({json.dumps(str(parser_path.resolve()))});
    const {{ CTIQueryEvaluator }} = require({json.dumps(str(evaluator_path.resolve()))});

    const parser = new CTIQueryParser();
    const evaluator = new CTIQueryEvaluator();

    const nodes = [
      {{ id: 'paper:1', type: 'Paper', title: 'Zero Trust Study' }},
      {{ id: 'cve:1', type: 'Vulnerability', severity: 'HIGH', label: 'CVE-2024-0001' }},
      {{ id: 'cve:2', type: 'Vulnerability', severity: 'LOW', label: 'CVE-2024-0002' }},
      {{ id: 'cwe:1', type: 'Weakness', label: 'CWE-79' }}
    ];

    const edges = [
      {{ source: 'paper:1', target: 'cve:1', label: 'REFERENCES' }},
      {{ source: 'cve:1', target: 'cwe:1', label: 'EXPLOITS' }}
    ];

    const res1 = evaluator.evaluateQuery(parser, 'type:Vulnerability AND severity:high', nodes, edges);
    const res2 = evaluator.evaluateQuery(parser, '(p:Paper) -> (v:Vulnerability)', nodes, edges);
    const res3 = evaluator.evaluateQuery(parser, '(p:Paper) -[:REFERENCES]-> (v:Vulnerability)', nodes, edges);
    const res4 = evaluator.evaluateQuery(parser, '(p:Paper) ->', nodes, edges);

    console.log(JSON.stringify({{
      res1Count: res1.count,
      res1Matched: Array.from(res1.matchedNodeIds),
      res2Count: res2.count,
      res3Count: res3.count,
      res4Success: res4.success,
      res4HasDiag: res4.diagnostics !== null
    }}));
    """
    proc = subprocess.run(
        [node_bin, "-e", test_script],
        capture_output=True,
        text=True,
        check=True,
    )
    data = json.loads(proc.stdout)
    assert data["res1Count"] == 1
    assert data["res1Matched"] == ["cve:1"]
    assert data["res2Count"] == 2
    assert data["res3Count"] == 2
    assert data["res4Success"] is False
    assert data["res4HasDiag"] is True
