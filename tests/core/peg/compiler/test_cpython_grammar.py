#!/usr/bin/env python3
"""Comprehensive Unit and Integration Tests for CPython PEG Grammar Specification in src/core/peg.

Validates:
1. PEP 617 / python.gram syntax constructs (rule:, | alts, name=expr, [expr], ~, sep.rule+)
2. Return type annotations and rule modifiers (rule[type] (memo):)
3. Directives (@header, @trailer, @include with triple quotes)
4. Deterministic disambiguation between CharClass ([a-z]) and Optional ([expr])
5. Ahead-of-Time code generation and runtime evaluation
6. Real CPython Grammar/python.gram block compilation
Conforms to DSN-25 and DSN-33-04 specifications. Zero external dependencies.
"""

from __future__ import annotations

from core.peg.compiler.ast_nodes import (
    ActionExpr,
    CharClassExpr,
    ChoiceExpr,
    CutExpr,
    GatherExpr,
    LitExpr,
    NamedExpr,
    OptExpr,
    RuleRefExpr,
    SeqExpr,
)
from core.peg.compiler.backend.javascript import JSCodeGenerator
from core.peg.compiler.backend.python import CodeGenerator
from core.peg.compiler.parser import MetaGrammarParser


class TestCPythonPEGParser:
    """Tests parsing CPython PEG grammar syntax constructs into GrammarDef AST."""

    def setup_method(self) -> None:
        self.parser = MetaGrammarParser(use_aot=False)

    def test_cpython_rule_colon_and_alternatives(self) -> None:
        grammar_text = """
        rule:
            | 'foo'
            | 'bar'
        """
        ast = self.parser.parse(grammar_text)
        assert len(ast.rules) == 1
        rule = ast.rules[0]
        assert rule.name == "rule"
        assert isinstance(rule.expr, ChoiceExpr)
        assert len(rule.expr.alternatives) == 2
        assert rule.expr.alternatives[0] == LitExpr("foo")
        assert rule.expr.alternatives[1] == LitExpr("bar")

    def test_cpython_variable_binding_and_type_annotation(self) -> None:
        grammar_text = """
        expr[int]:
            | a=term '+' b=term { return a + b }
            | c[int]=term { return c }
        """
        ast = self.parser.parse(grammar_text)
        assert len(ast.rules) == 1
        rule = ast.rules[0]
        assert rule.name == "expr"
        assert rule.return_type == "int"
        assert isinstance(rule.expr, ChoiceExpr)

        # First alternative: action wrapping seq with named expressions
        first_alt = rule.expr.alternatives[0]
        assert isinstance(first_alt, ActionExpr)
        assert isinstance(first_alt.expr, SeqExpr)
        seq_elems = first_alt.expr.elements
        assert isinstance(seq_elems[0], NamedExpr)
        assert seq_elems[0].name == "a"
        assert seq_elems[0].expr == RuleRefExpr("term")
        assert seq_elems[1] == LitExpr("+")
        assert isinstance(seq_elems[2], NamedExpr)
        assert seq_elems[2].name == "b"

    def test_cpython_optional_brackets_vs_char_class(self) -> None:
        grammar_text = """
        mixed:
            | [statements]
            | [';']
            | [a | b]
            | [a-z0-9]
            | [^0-9]
            | [ \t\r\n]
        """
        ast = self.parser.parse(grammar_text)
        rule = ast.rules[0]
        assert isinstance(rule.expr, ChoiceExpr)
        alts = rule.expr.alternatives

        # [statements] -> OptExpr(RuleRefExpr("statements"))
        assert isinstance(alts[0], OptExpr)
        assert alts[0].expr == RuleRefExpr("statements")

        # [';'] -> OptExpr(LitExpr(";"))
        assert isinstance(alts[1], OptExpr)
        assert alts[1].expr == LitExpr(";")

        # [a | b] -> OptExpr(ChoiceExpr([a, b]))
        assert isinstance(alts[2], OptExpr)
        assert isinstance(alts[2].expr, ChoiceExpr)

        # [a-z0-9] -> CharClassExpr
        assert isinstance(alts[3], CharClassExpr)
        assert alts[3].raw_spec == "a-z0-9"
        assert not alts[3].inverted

        # [^0-9] -> CharClassExpr(inverted=True)
        assert isinstance(alts[4], CharClassExpr)
        assert alts[4].raw_spec == "0-9"
        assert alts[4].inverted

        # [ \t\r\n] -> CharClassExpr
        assert isinstance(alts[5], CharClassExpr)
        assert "\\t" in alts[5].raw_spec or "\t" in alts[5].raw_spec

    def test_cpython_gather_separated_list(self) -> None:
        grammar_text = """
        items:
            | ','.statement+
            | ';'.simple_stmt*
        """
        ast = self.parser.parse(grammar_text)
        rule = ast.rules[0]
        assert isinstance(rule.expr, ChoiceExpr)
        alts = rule.expr.alternatives

        # ','.statement+ -> GatherExpr(separator=LitExpr(','), element=RuleRefExpr('statement'), is_one_or_more=True)
        assert isinstance(alts[0], GatherExpr)
        assert alts[0].separator == LitExpr(",")
        assert alts[0].element == RuleRefExpr("statement")
        assert alts[0].is_one_or_more is True

        # ';'.simple_stmt* -> GatherExpr(is_one_or_more=False)
        assert isinstance(alts[1], GatherExpr)
        assert alts[1].separator == LitExpr(";")
        assert alts[1].element == RuleRefExpr("simple_stmt")
        assert alts[1].is_one_or_more is False

    def test_cpython_cut_operator(self) -> None:
        grammar_text = """
        if_stmt:
            | 'if' ~ condition ':' body
        """
        ast = self.parser.parse(grammar_text)
        rule = ast.rules[0]
        assert isinstance(rule.expr, SeqExpr)
        assert rule.expr.elements[0] == LitExpr("if")
        assert isinstance(rule.expr.elements[1], CutExpr)
        assert rule.expr.elements[2] == RuleRefExpr("condition")

    def test_cpython_directives_and_triple_quotes(self) -> None:
        grammar_text = """
        @header '''
        # Module header
        import sys
        '''

        @trailer '''
        # Module trailer
        '''

        @include "extra.gram"

        start: 'OK'
        """
        ast = self.parser.parse(grammar_text)
        assert len(ast.rules) == 1
        assert "@header" in ast.directives
        assert "import sys" in ast.directives["@header"]
        assert "@trailer" in ast.directives
        assert "@include" in ast.directives
        assert ast.directives["@include"] == "extra.gram"

    def test_cpython_rule_modifiers(self) -> None:
        grammar_text = """
        simple_stmt[stmt_ty] (memo):
            | 'pass'
        """
        ast = self.parser.parse(grammar_text)
        rule = ast.rules[0]
        assert rule.name == "simple_stmt"
        assert rule.return_type == "stmt_ty"
        assert "memo" in rule.modifiers


class TestCPythonPEGExecution:
    """Tests Ahead-of-Time code generation and runtime evaluation of CPython PEG grammars."""

    def test_cpython_calc_grammar_codegen_and_execution(self) -> None:
        grammar_text = """
        @class Calc

        start:
            | ws e=expr ws { return e }

        expr:
            | a=term rest=('+' ws b=term { return b })* {
                val = a
                for r in rest:
                    val += r
                return val
            }

        term:
            | n=/[0-9]+/ ws { return int(n) }

        ws:
            | [ \t\r\n]*
        """
        parser = MetaGrammarParser(use_aot=False)
        ast = parser.parse(grammar_text)
        codegen = CodeGenerator(ast)
        code = codegen.generate()

        namespace: dict = {}
        exec(code, namespace)
        calc_cls = namespace.get("CalcParser")
        assert calc_cls is not None

        calc_instance = calc_cls()
        res1 = calc_instance.parse("42")
        assert res1 == 42
        res2 = calc_instance.parse("10 + 20 + 12")
        assert res2 == 42

    def test_cpython_gather_runtime_evaluation(self) -> None:
        grammar_text = """
        @class CSV

        start:
            | rows=','.num+ { return rows }

        num:
            | n=/[0-9]+/ { return int(n) }
        """
        parser = MetaGrammarParser(use_aot=False)
        ast = parser.parse(grammar_text)
        codegen = CodeGenerator(ast)
        code = codegen.generate()

        namespace: dict = {}
        exec(code, namespace)
        csv_cls = namespace.get("CSVParser")
        assert csv_cls is not None

        csv_instance = csv_cls()
        res = csv_instance.parse("1,2,3,4,5")
        assert res == [1, 2, 3, 4, 5]

    def test_cpython_javascript_codegen(self) -> None:
        grammar_text = """
        ListGrammar:
            | items=','.item+ { return items }

        item:
            | /[a-z]+/
        """
        parser = MetaGrammarParser(use_aot=False)
        ast = parser.parse(grammar_text)
        js_codegen = JSCodeGenerator(ast)
        js_code = js_codegen.generate()
        assert "gather(" in js_code
        assert "function Gather(" in js_code


class TestCPythonPythonGramSample:
    """Tests parsing actual real grammar blocks from CPython Grammar/python.gram."""

    def test_real_python_gram_block_parsing(self) -> None:
        # Authentic snippet from CPython 3.12 / 3.14 Grammar/python.gram
        python_gram_snippet = """
        file[mod_ty]:
            | a=[statements] ENDMARKER { return a }

        statements[asdl_stmt_seq*]:
            | a=statement+ { return a }

        statement[asdl_stmt_seq*]:
            | a=compound_stmt { return a }
            | a[asdl_stmt_seq*]=simple_stmts { return a }

        simple_stmts[asdl_stmt_seq*]:
            | a=simple_stmt !';' NEWLINE { return a }
            | a[asdl_stmt_seq*]=';'.simple_stmt+ [';'] NEWLINE { return a }

        simple_stmt[stmt_ty] (memo):
            | assignment
            | &'return' return_stmt
            | &'raise' raise_stmt
            | &'pass' pass_stmt
        """
        parser = MetaGrammarParser(use_aot=False)
        ast = parser.parse(python_gram_snippet)
        assert len(ast.rules) == 5

        # Rule 1: file
        r_file = ast.rules[0]
        assert r_file.name == "file"
        assert r_file.return_type == "mod_ty"

        # Rule 4: simple_stmts contains gather: ';'.simple_stmt+
        r_simple_stmts = ast.rules[3]
        assert r_simple_stmts.name == "simple_stmts"
        assert isinstance(r_simple_stmts.expr, ChoiceExpr)
        second_alt = r_simple_stmts.expr.alternatives[1]
        assert isinstance(second_alt, ActionExpr)
        assert isinstance(second_alt.expr, SeqExpr)
        named_gather = second_alt.expr.elements[0]
        assert isinstance(named_gather, NamedExpr)
        assert isinstance(named_gather.expr, GatherExpr)
        assert named_gather.expr.separator == LitExpr(";")
        assert named_gather.expr.element == RuleRefExpr("simple_stmt")

        # Rule 5: simple_stmt has memo modifier
        r_simple = ast.rules[4]
        assert r_simple.name == "simple_stmt"
        assert "memo" in r_simple.modifiers
