#!/usr/bin/env python3
"""
Unit Test Suite for lint_sexpr.py
Conforms to Issue #628 and DSN-33 Architecture Specification.
"""

import unittest
import sys
import os

# Add scripts directory to path
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "scripts"))
from lint_sexpr import lint_scheme_source, LintError


class TestSexprLinter(unittest.TestCase):
    def test_balanced_simple(self):
        code = "(define (add a b) (+ a b))"
        errs = lint_scheme_source("<test>", code)
        self.assertEqual(len(errs), 0)

    def test_unclosed_paren(self):
        code = "(define (broken a b)\n  (+ a b)\n"
        errs = lint_scheme_source("<test>", code)
        self.assertEqual(len(errs), 1)
        self.assertEqual(errs[0].line, 1)
        self.assertEqual(errs[0].col, 1)
        self.assertIn("unclosed '('", errs[0].message)

    def test_unclosed_inner_paren(self):
        code = "(define (broken a b)\n  (+ a b"
        errs = lint_scheme_source("<test>", code)
        self.assertEqual(len(errs), 1)
        self.assertEqual(errs[0].line, 2)
        self.assertEqual(errs[0].col, 3)
        self.assertIn("unclosed '('", errs[0].message)

    def test_extra_closing_paren(self):
        code = "(define (f x) x))\n"
        errs = lint_scheme_source("<test>", code)
        self.assertEqual(len(errs), 1)
        self.assertEqual(errs[0].line, 1)
        self.assertEqual(errs[0].col, 17)
        self.assertIn("unexpected closing ')'", errs[0].message)

    def test_parens_in_comments_ignored(self):
        code = "; (this is an unclosed paren in a comment\n(define x 10)\n; another comment )"
        errs = lint_scheme_source("<test>", code)
        self.assertEqual(len(errs), 0)

    def test_parens_in_strings_ignored(self):
        code = '(define s "this ( has unclosed ) paren")'
        errs = lint_scheme_source("<test>", code)
        self.assertEqual(len(errs), 0)

    def test_escaped_quotes_in_strings(self):
        code = r'(define s "quoted \"(paren)\" string")'
        errs = lint_scheme_source("<test>", code)
        self.assertEqual(len(errs), 0)

    def test_multiline_string(self):
        code = '(define s "line 1 (\nline 2 )\nline 3")'
        errs = lint_scheme_source("<test>", code)
        self.assertEqual(len(errs), 0)

    def test_unclosed_string(self):
        code = '(define s "unclosed string\n(+ 1 2)'
        errs = lint_scheme_source("<test>", code)
        self.assertEqual(len(errs), 1)
        self.assertEqual(errs[0].line, 1)
        self.assertIn("unclosed string literal", errs[0].message)

    def test_char_literal_open_paren(self):
        # Character literal #\( should NOT count as opening parenthesis
        code = "(write-char #\\()\n"
        errs = lint_scheme_source("<test>", code)
        self.assertEqual(len(errs), 0)

    def test_char_literal_close_paren(self):
        # Character literal #\) should NOT count as closing parenthesis
        code = "(write-char #\\))\n"
        errs = lint_scheme_source("<test>", code)
        self.assertEqual(len(errs), 0)

    def test_char_literal_other_specials(self):
        # #\space, #\newline, #\;, #\"
        code = "(define (test-chars)\n  (list #\\space #\\newline #\\; #\\\" #\\x20))\n"
        errs = lint_scheme_source("<test>", code)
        self.assertEqual(len(errs), 0)

    def test_block_comment(self):
        code = "#| (unclosed in block |# (define x 42) #| another |#"
        errs = lint_scheme_source("<test>", code)
        self.assertEqual(len(errs), 0)

    def test_nested_block_comment(self):
        code = "#| outer #| inner (unclosed |# outer |# (define x 42)"
        errs = lint_scheme_source("<test>", code)
        self.assertEqual(len(errs), 0)

    def test_unclosed_block_comment(self):
        code = "#| unclosed block comment\n(define x 42)"
        errs = lint_scheme_source("<test>", code)
        self.assertEqual(len(errs), 1)
        self.assertEqual(errs[0].line, 1)
        self.assertIn("unclosed block comment", errs[0].message)

    def test_vector_and_bytevector_literals(self):
        code = "(define v #(1 2 3))\n(define bv #u8(10 20 30))\n"
        errs = lint_scheme_source("<test>", code)
        self.assertEqual(len(errs), 0)

    def test_vector_unclosed(self):
        code = "(define v #(1 2 3\n"
        errs = lint_scheme_source("<test>", code)
        self.assertEqual(len(errs), 1)
        self.assertIn("unclosed '('", errs[0].message)


if __name__ == "__main__":
    unittest.main()
