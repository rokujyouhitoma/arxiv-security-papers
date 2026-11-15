#!/usr/bin/env python3
r"""
ULisp S-Expression Parenthesis Depth & Syntax Linter (lint_sexpr.py)
Conforms to Issue #628 and DSN-33 Architecture Specification.

High-performance, zero-dependency linter for Scheme (.scm) source files.
Detects:
  - Unclosed parentheses '(' at EOF with exact line/column of the opening paren.
  - Unexpected extra closing parentheses ')' with exact line/column.
  - Unclosed string literals '"' at EOF.
  - Unclosed block comments '#|' at EOF.
Accurately skips:
  - Line comments (; ... \n)
  - String literals ("...") including escape sequences (\" and \\)
  - Character literals (#\(, #\), #\space, #\newline, #\xNN, etc.)
  - Nested block comments (#| ... |#)
"""

import sys
import os
from typing import List, Tuple, Optional
from dataclasses import dataclass
from typing import Any, List, Optional, Sequence, Tuple


class LintError:
    def __init__(self, filepath: str, line: int, col: int, message: str, line_text: str = ""):
        self.filepath = filepath
        self.line = line
        self.col = col
        self.message = message
        self.line_text = line_text

    def __str__(self) -> str:
        s = f"{self.filepath}:{self.line}:{self.col}: error: {self.message}"
        if self.line_text:
            s += f"\n    {self.line_text.rstrip()}"
            pointer = " " * (self.col - 1) + "^"
            s += f"\n    {pointer}"
        return s


_COMPILER_PATH_PREFIXES = (
    "compiler/",
    "frontend/",
    "middleend/",
    "lir/",
    "backend/",
    "lib/ulisp/concurrency/passes/",
)

_FIRST_CLASS_PRIMITIVES = ("car", "cdr")
_BINARY_ARITH_OPS = ("+", "*")


def is_compiler_source_path(filepath: str) -> bool:
    """Return True if filepath is part of the self-hosting compiler sources."""
    norm = os.path.normpath(filepath).replace("\\", "/")
    if norm == "<test>":
        return False
    if not norm.endswith(".scm"):
        return False
    basename = os.path.basename(norm)
    if basename == "compiler_entry.scm":
        return True
    parts = norm.split("/")
    for idx in range(len(parts)):
        sub = "/".join(parts[idx:])
        if any(sub.startswith(prefix) for prefix in _COMPILER_PATH_PREFIXES):
            return True
    return False


@dataclass
class _Sym:
    name: str
    line: int
    col: int


@dataclass
class _ListExpr:
    elems: List[Any]
    dotted_tail: Optional[Any]
    line: int
    col: int
    kind: str = "list"  # "list", "vector", "bytevector"


@dataclass
class _QuoteExpr:
    kind: str  # "quote", "quasiquote", "unquote", "unquote-splicing", "datum-comment"
    datum: Any
    line: int
    col: int


@dataclass
class _Atom:
    line: int
    col: int


_DELIM_CHARS = set("()\";'`, \t\r\n")


def _tokenize_scheme(content: str) -> List[Tuple[str, str, int, int]]:
    """Tokenize balanced Scheme source for AST compatibility checks."""
    tokens: List[Tuple[str, str, int, int]] = []
    n = len(content)
    i = 0
    line = 1
    col = 1

    while i < n:
        c = content[i]
        if c == "\n":
            line += 1
            col = 1
            i += 1
            continue
        if c in (" ", "\t", "\r"):
            i += 1
            col += 1
            continue
        if c == ";":
            while i < n and content[i] != "\n":
                i += 1
                col += 1
            continue
        if c == '"':
            tok_l, tok_c = line, col
            i += 1
            col += 1
            while i < n:
                sc = content[i]
                if sc == "\\":
                    i += 1
                    col += 1
                    if i < n:
                        if content[i] == "\n":
                            line += 1
                            col = 1
                        else:
                            col += 1
                        i += 1
                    continue
                if sc == '"':
                    i += 1
                    col += 1
                    break
                if sc == "\n":
                    line += 1
                    col = 1
                else:
                    col += 1
                i += 1
            tokens.append(("ATOM", '"..."', tok_l, tok_c))
            continue
        if c == "#":
            if i + 1 < n and content[i + 1] == "|":
                depth = 1
                i += 2
                col += 2
                while i < n and depth > 0:
                    if content[i] == "\n":
                        line += 1
                        col = 1
                        i += 1
                    elif i + 1 < n and content[i : i + 2] == "#|":
                        depth += 1
                        i += 2
                        col += 2
                    elif i + 1 < n and content[i : i + 2] == "|#":
                        depth -= 1
                        i += 2
                        col += 2
                    else:
                        i += 1
                        col += 1
                continue
            if i + 1 < n and content[i + 1] == ";":
                tokens.append(("DATUM_COMMENT", "#;", line, col))
                i += 2
                col += 2
                continue
            if i + 1 < n and content[i + 1] == "\\":
                tok_l, tok_c = line, col
                i += 2
                col += 2
                if i < n:
                    if content[i] == "\n":
                        line += 1
                        col = 1
                        i += 1
                    else:
                        i += 1
                        col += 1
                        while i < n and content[i] not in _DELIM_CHARS:
                            i += 1
                            col += 1
                tokens.append(("ATOM", "#\\char", tok_l, tok_c))
                continue
            if i + 1 < n and content[i + 1] == "(":
                tokens.append(("VEC_OPEN", "#(", line, col))
                i += 2
                col += 2
                continue
            if i + 3 < n and content[i : i + 4] == "#u8(":
                tokens.append(("BV_OPEN", "#u8(", line, col))
                i += 4
                col += 4
                continue
            # #t, #f, #xNN, #!optional, etc.
            tok_l, tok_c = line, col
            start = i
            i += 1
            col += 1
            while i < n and content[i] not in _DELIM_CHARS:
                i += 1
                col += 1
            tokens.append(("ATOM", content[start:i], tok_l, tok_c))
            continue
        if c == "(":
            tokens.append(("LPAREN", "(", line, col))
            i += 1
            col += 1
            continue
        if c == ")":
            tokens.append(("RPAREN", ")", line, col))
            i += 1
            col += 1
            continue
        if c == "'":
            tokens.append(("QUOTE", "'", line, col))
            i += 1
            col += 1
            continue
        if c == "`":
            tokens.append(("QUASIQUOTE", "`", line, col))
            i += 1
            col += 1
            continue
        if c == ",":
            if i + 1 < n and content[i + 1] == "@":
                tokens.append(("UNQUOTE_SPLICING", ",@", line, col))
                i += 2
                col += 2
            else:
                tokens.append(("UNQUOTE", ",", line, col))
                i += 1
                col += 1
            continue
        if c == "|":
            tok_l, tok_c = line, col
            start = i
            i += 1
            col += 1
            while i < n and content[i] != "|":
                if content[i] == "\\":
                    i += 1
                    col += 1
                if i < n:
                    if content[i] == "\n":
                        line += 1
                        col = 1
                    else:
                        col += 1
                    i += 1
            if i < n and content[i] == "|":
                i += 1
                col += 1
            tokens.append(("SYM", content[start:i], tok_l, tok_c))
            continue

        tok_l, tok_c = line, col
        start = i
        while i < n and content[i] not in _DELIM_CHARS:
            i += 1
            col += 1
        val = content[start:i]
        if val == ".":
            tokens.append(("DOT", ".", tok_l, tok_c))
        else:
            tokens.append(("SYM_OR_NUM", val, tok_l, tok_c))

    return tokens


def _is_number_literal(text: str) -> bool:
    if not text:
        return False
    s = text
    if s[0] in ("+", "-") and len(s) > 1:
        s = s[1:]
    if not s or not s[0].isdigit():
        return False
    try:
        float(text)
        return True
    except ValueError:
        return False


def _parse_tokens(tokens: Sequence[Tuple[str, str, int, int]]) -> List[Any]:
    pos = 0
    total = len(tokens)

    def read_expr() -> Optional[Any]:
        nonlocal pos
        while pos < total and tokens[pos][0] == "DATUM_COMMENT":
            pos += 1
            if pos < total:
                read_expr()
        if pos >= total:
            return None
        kind, val, line, col = tokens[pos]
        if kind in ("LPAREN", "VEC_OPEN", "BV_OPEN"):
            pos += 1
            elems: List[Any] = []
            dotted_tail: Optional[Any] = None
            while pos < total:
                if tokens[pos][0] == "DATUM_COMMENT":
                    pos += 1
                    if pos < total:
                        read_expr()
                    continue
                if tokens[pos][0] == "RPAREN":
                    pos += 1
                    break
                if tokens[pos][0] == "DOT" and kind == "LPAREN":
                    pos += 1
                    dotted_tail = read_expr()
                    while pos < total and tokens[pos][0] != "RPAREN":
                        read_expr()
                    if pos < total and tokens[pos][0] == "RPAREN":
                        pos += 1
                    break
                item = read_expr()
                if item is not None:
                    elems.append(item)
            list_kind = (
                "vector" if kind == "VEC_OPEN" else ("bytevector" if kind == "BV_OPEN" else "list")
            )
            return _ListExpr(elems, dotted_tail, line, col, list_kind)
        if kind == "RPAREN":
            pos += 1
            return None
        if kind in ("QUOTE", "QUASIQUOTE", "UNQUOTE", "UNQUOTE_SPLICING"):
            pos += 1
            datum = read_expr()
            qmap = {
                "QUOTE": "quote",
                "QUASIQUOTE": "quasiquote",
                "UNQUOTE": "unquote",
                "UNQUOTE_SPLICING": "unquote-splicing",
            }
            return _QuoteExpr(qmap[kind], datum, line, col)
        pos += 1
        if kind == "SYM":
            return _Sym(val, line, col)
        if kind == "SYM_OR_NUM" and not _is_number_literal(val):
            return _Sym(val, line, col)
        return _Atom(line, col)

    forms: List[Any] = []
    while pos < total:
        expr = read_expr()
        if expr is not None:
            forms.append(expr)
    return forms


def check_ulisp_compat(filepath: str, content: str) -> List[LintError]:
    """Static compatibility checks preventing bin/ulisp-boot ABI & arity failures."""
    lines = content.splitlines(keepends=True)

    def line_text(l_num: int) -> str:
        if 1 <= l_num <= len(lines):
            return lines[l_num - 1]
        return ""

    errors: List[LintError] = []
    tokens = _tokenize_scheme(content)
    forms = _parse_tokens(tokens)

    def add_err(line: int, col: int, msg: str) -> None:
        errors.append(LintError(filepath, line, col, msg, line_text(line)))

    def check_expr(expr: Any, qq_depth: int = 0) -> None:
        if expr is None:
            return
        if isinstance(expr, _Atom):
            return
        if isinstance(expr, _Sym):
            return
        if isinstance(expr, _QuoteExpr):
            if expr.kind == "quote":
                return
            if expr.kind == "quasiquote":
                check_expr(expr.datum, qq_depth + 1)
                return
            if expr.kind in ("unquote", "unquote-splicing"):
                if qq_depth > 0:
                    check_expr(expr.datum, qq_depth - 1)
                return
            return
        if not isinstance(expr, _ListExpr):
            return
        if expr.kind != "list":
            return

        if qq_depth > 0:
            if (
                len(expr.elems) == 2
                and expr.dotted_tail is None
                and isinstance(expr.elems[0], _Sym)
                and expr.elems[0].name in ("unquote", "unquote-splicing")
            ):
                check_expr(expr.elems[1], qq_depth - 1)
                return
            for sub in expr.elems:
                check_expr(sub, qq_depth)
            if expr.dotted_tail is not None:
                check_expr(expr.dotted_tail, qq_depth)
            return

        if not expr.elems:
            return

        head_node = expr.elems[0]
        args = expr.elems[1:]

        if isinstance(head_node, _Sym):
            head = head_node.name
            if head in ("quote", "define-syntax", "syntax-rules", "define-language", "define-value-repr", "define-record-type", "%declare-extern-identifiers", "declare", "import", "export"):
                return
            if head == "quasiquote":
                if args:
                    check_expr(args[0], qq_depth + 1)
                return
            if head in ("unquote", "unquote-splicing"):
                if qq_depth > 0 and args:
                    check_expr(args[0], qq_depth - 1)
                return
            if head == "cond-expand":
                has_ulisp = False
                for br in args:
                    if isinstance(br, _ListExpr) and br.elems and isinstance(br.elems[0], _Sym) and br.elems[0].name == "ulisp":
                        has_ulisp = True
                        for sub in br.elems[1:]:
                            check_expr(sub, 0)
                if not has_ulisp:
                    for br in args:
                        if isinstance(br, _ListExpr) and br.elems and isinstance(br.elems[0], _Sym) and br.elems[0].name == "else":
                            for sub in br.elems[1:]:
                                check_expr(sub, 0)
                return
            if head in ("define", "define-macro"):
                if not args:
                    return
                target = args[0]
                if isinstance(target, _ListExpr) and target.dotted_tail is not None and head == "define":
                    add_err(
                        target.line,
                        target.col,
                        "dotted variadic (define (... . rest) ...) is incompatible with bin/ulisp-boot ABI; use fixed-arity helpers or case-lambda (<= 6 params)",
                    )
                for body_form in args[1:]:
                    if not (
                        isinstance(body_form, _ListExpr)
                        and body_form.elems
                        and isinstance(body_form.elems[0], _Sym)
                        and body_form.elems[0].name == "declare"
                    ):
                        check_expr(body_form, 0)
                return
            if head == "lambda":
                if len(args) >= 2:
                    formals = args[0]
                    if isinstance(formals, _ListExpr) and formals.dotted_tail is not None:
                        add_err(
                            formals.line,
                            formals.col,
                            "dotted variadic (lambda (... . rest) ...) is incompatible with bin/ulisp-boot ABI; use fixed-arity helpers or case-lambda (<= 6 params)",
                        )
                    for body_form in args[1:]:
                        check_expr(body_form, 0)
                return
            if head == "case-lambda":
                for cl in args:
                    if isinstance(cl, _ListExpr) and len(cl.elems) >= 2:
                        formals = cl.elems[0]
                        if isinstance(formals, _ListExpr) and len(formals.elems) > 6:
                            add_err(
                                formals.line,
                                formals.col,
                                f"case-lambda clause with {len(formals.elems)} (> 6) fixed parameters corrupts stack arguments in bin/ulisp-boot; split into helper or pass an options list",
                            )
                        for body_form in cl.elems[1:]:
                            check_expr(body_form, 0)
                return
            if head in ("let", "let*", "letrec", "letrec*"):
                if not args:
                    return
                idx = 0
                if isinstance(args[0], _Sym):
                    idx = 1
                if idx < len(args):
                    bindings = args[idx]
                    if isinstance(bindings, _ListExpr):
                        for b in bindings.elems:
                            if isinstance(b, _ListExpr) and len(b.elems) >= 2:
                                for init_expr in b.elems[1:]:
                                    check_expr(init_expr, 0)
                    for body_form in args[idx + 1 :]:
                        check_expr(body_form, 0)
                return
            if head == "do":
                if len(args) >= 2:
                    if isinstance(args[0], _ListExpr):
                        for b in args[0].elems:
                            if isinstance(b, _ListExpr):
                                for sub in b.elems[1:]:
                                    check_expr(sub, 0)
                    if isinstance(args[1], _ListExpr):
                        for sub in args[1].elems:
                            check_expr(sub, 0)
                    for cmd in args[2:]:
                        check_expr(cmd, 0)
                return
            if head == "cond":
                for cl in args:
                    if isinstance(cl, _ListExpr) and cl.elems:
                        if not (isinstance(cl.elems[0], _Sym) and cl.elems[0].name == "else"):
                            check_expr(cl.elems[0], 0)
                        for sub in cl.elems[1:]:
                            if not (isinstance(sub, _Sym) and sub.name == "=>"):
                                check_expr(sub, 0)
                return
            if head == "case":
                if args:
                    check_expr(args[0], 0)
                    for cl in args[1:]:
                        if isinstance(cl, _ListExpr) and len(cl.elems) >= 2:
                            if len(cl.elems) >= 3 and isinstance(cl.elems[1], _Sym) and cl.elems[1].name == "=>":
                                for sub in cl.elems[2:]:
                                    check_expr(sub, 0)
                            else:
                                for sub in cl.elems[1:]:
                                    check_expr(sub, 0)
                return
            if head == "guard":
                if args and isinstance(args[0], _ListExpr) and len(args[0].elems) >= 2:
                    for cl in args[0].elems[1:]:
                        if isinstance(cl, _ListExpr) and cl.elems:
                            if not (isinstance(cl.elems[0], _Sym) and cl.elems[0].name == "else"):
                                check_expr(cl.elems[0], 0)
                            for sub in cl.elems[1:]:
                                check_expr(sub, 0)
                for body_form in args[1:]:
                    check_expr(body_form, 0)
                return
            if head == "define-picopass":
                for nt_clause in args[1:]:
                    if isinstance(nt_clause, _ListExpr) and len(nt_clause.elems) >= 2:
                        for rule in nt_clause.elems[1:]:
                            if isinstance(rule, _ListExpr) and len(rule.elems) >= 2:
                                for sub in rule.elems[1:]:
                                    if isinstance(sub, _ListExpr) and sub.elems and isinstance(sub.elems[0], _Sym) and sub.elems[0].name == "guard":
                                        for g in sub.elems[1:]:
                                            check_expr(g, 0)
                                    else:
                                        check_expr(sub, 0)
                return
            if head == "define-pass":
                # Check body sub-forms of each transformer clause while skipping language headers
                for item in args:
                    if isinstance(item, _ListExpr) and item.elems and isinstance(item.elems[0], _Sym):
                        nt_head = item.elems[0].name
                        if nt_head in ("fuse-rules", "begin") or (
                            len(item.elems) >= 4
                            and isinstance(item.elems[1], _Sym)
                            and item.elems[1].name == ":"
                        ):
                            if nt_head in ("fuse-rules", "begin"):
                                check_expr(item, 0)
                            else:
                                # Nonterminal transformer: scan clauses after '-> ReturnNT ()'
                                saw_arrow = False
                                for sub in item.elems:
                                    if isinstance(sub, _Sym) and sub.name == "->":
                                        saw_arrow = True
                                    elif saw_arrow and isinstance(sub, _ListExpr) and len(sub.elems) >= 2:
                                        for action in sub.elems[1:]:
                                            if isinstance(action, _ListExpr) and action.elems and isinstance(action.elems[0], _Sym) and action.elems[0].name == "guard":
                                                for g in action.elems[1:]:
                                                    check_expr(g, 0)
                                            else:
                                                check_expr(action, 0)
                return
            if head == "set!" and len(args) >= 2:
                check_expr(args[1], 0)
                return
            if head in _BINARY_ARITH_OPS and expr.dotted_tail is None and len(args) != 2:
                add_err(
                    head_node.line,
                    head_node.col,
                    f"builtin '{head}' expects 2 arguments in bin/ulisp-boot, got {len(args)}",
                )
            elif head == "-" and expr.dotted_tail is None and (len(args) == 0 or len(args) >= 3):
                add_err(
                    head_node.line,
                    head_node.col,
                    f"builtin '-' expects 1 or 2 arguments in bin/ulisp-boot, got {len(args)}",
                )
            elif head == "make-string" and expr.dotted_tail is None and len(args) == 2:
                add_err(
                    head_node.line,
                    head_node.col,
                    "builtin 'make-string' with 2 args (k ch) is unsupported by bin/ulisp-boot; use 1-arg (make-string k) or loop/string",
                )

            # First-class primitive check in argument positions
            for arg in args:
                if isinstance(arg, _Sym) and arg.name in _FIRST_CLASS_PRIMITIVES:
                    add_err(
                        arg.line,
                        arg.col,
                        f"first-class primitive '{arg.name}' cannot be referenced as a value in ulisp; use '{arg.name}*' instead",
                    )
        else:
            check_expr(head_node, 0)
            for arg in args:
                if isinstance(arg, _Sym) and arg.name in _FIRST_CLASS_PRIMITIVES:
                    add_err(
                        arg.line,
                        arg.col,
                        f"first-class primitive '{arg.name}' cannot be referenced as a value in ulisp; use '{arg.name}*' instead",
                    )

        for arg in args:
            check_expr(arg, 0)

    for top_form in forms:
        check_expr(top_form, 0)

    return errors


def lint_scheme_source(filepath: str, content: str, check_compat: Optional[bool] = None) -> List[LintError]:
    errors: List[LintError] = []
    lines = content.splitlines(keepends=True)

    def get_line_text(l_num: int) -> str:
        if 1 <= l_num <= len(lines):
            return lines[l_num - 1]
        return ""

    n = len(content)
    i = 0
    line = 1
    col = 1

    # stack contains tuples of (line, col, char)
    paren_stack: List[Tuple[int, int, str]] = []

    while i < n:
        c = content[i]

        # 1. Newline tracking
        if c == '\n':
            line += 1
            col = 1
            i += 1
            continue

        # 2. Line comment (; ... \n)
        if c == ';':
            while i < n and content[i] != '\n':
                i += 1
                col += 1
            continue

        # 3. String literal ("...")
        if c == '"':
            str_line = line
            str_col = col
            i += 1
            col += 1
            closed = False
            while i < n:
                sc = content[i]
                if sc == '\\':
                    i += 1
                    col += 1
                    if i < n:
                        if content[i] == '\n':
                            line += 1
                            col = 1
                        else:
                            col += 1
                        i += 1
                elif sc == '"':
                    i += 1
                    col += 1
                    closed = True
                    break
                elif sc == '\n':
                    line += 1
                    col = 1
                    i += 1
                else:
                    col += 1
                    i += 1
            if not closed:
                errors.append(
                    LintError(
                        filepath,
                        str_line,
                        str_col,
                        "unclosed string literal starting here",
                        get_line_text(str_line),
                    )
                )
                return errors
            continue

        # 4. Hash-prefixed forms (#\, #|, etc.)
        if c == '#' and i + 1 < n:
            next_c = content[i + 1]

            # 4a. Character literal: #\
            if next_c == '\\':
                # Skip '#' and '\'
                i += 2
                col += 2
                if i < n:
                    char_c = content[i]
                    if char_c in ('(', ')'):
                        # #\( or #\) - single paren character literal
                        i += 1
                        col += 1
                    elif char_c in (' ', '\t', '\r', '\n', ';', '"'):
                        # #\ followed by whitespace/delimiter (e.g. #\ )
                        i += 1
                        col += 1
                    else:
                        # Named character or hex code (e.g. #\newline, #\space, #\alarm, #\x0A)
                        while i < n and content[i] not in (' ', '\t', '\r', '\n', '(', ')', ';', '"'):
                            i += 1
                            col += 1
                continue

            # 4b. Block comment: #| ... |# (with nesting support)
            if next_c == '|':
                blk_line = line
                blk_col = col
                i += 2
                col += 2
                depth = 1
                while i < n and depth > 0:
                    if content[i] == '\n':
                        line += 1
                        col = 1
                        i += 1
                    elif content[i] == '#' and i + 1 < n and content[i + 1] == '|':
                        depth += 1
                        i += 2
                        col += 2
                    elif content[i] == '|' and i + 1 < n and content[i + 1] == '#':
                        depth -= 1
                        i += 2
                        col += 2
                    else:
                        col += 1
                        i += 1
                if depth > 0:
                    errors.append(
                        LintError(
                            filepath,
                            blk_line,
                            blk_col,
                            "unclosed block comment '#|' starting here",
                            get_line_text(blk_line),
                        )
                    )
                    return errors
                continue

        # 5. Parentheses
        if c == '(':
            paren_stack.append((line, col, '('))
            i += 1
            col += 1
            continue

        if c == ')':
            if not paren_stack:
                errors.append(
                    LintError(
                        filepath,
                        line,
                        col,
                        "unexpected closing ')' without matching opening parenthesis",
                        get_line_text(line),
                    )
                )
                return errors
            paren_stack.pop()
            i += 1
            col += 1
            continue

        # Any other character
        col += 1
        i += 1

    # Check for unclosed parens at EOF
    if paren_stack:
        for p_line, p_col, p_char in reversed(paren_stack):
            errors.append(
                LintError(
                    filepath,
                    p_line,
                    p_col,
                    f"unclosed '{p_char}' (depth {len(paren_stack)} remaining at EOF)",
                    get_line_text(p_line),
                )
            )
            # Report the innermost/first problematic unclosed paren prominently
            break

    if not errors:
        should_check_compat = (
            is_compiler_source_path(filepath) if check_compat is None else check_compat
        )
        if should_check_compat:
            errors.extend(check_ulisp_compat(filepath, content))

    return errors


def lint_file(filepath: str, check_compat: Optional[bool] = None) -> List[LintError]:
    try:
        with open(filepath, 'r', encoding='utf-8', errors='replace') as f:
            content = f.read()
    except Exception as e:
        return [LintError(filepath, 1, 1, f"failed to read file: {e}")]
    return lint_scheme_source(filepath, content, check_compat=check_compat)


def main() -> int:
    args = sys.argv[1:]
    if not args or "--help" in args or "-h" in args:
        print("Usage: lint_sexpr.py [--quiet] <file1.scm> [file2.scm ...]")
        return 0

    quiet = False
    files: List[str] = []
    for a in args:
        if a == "--quiet" or a == "-q":
            quiet = True
        else:
            files.append(a)

    all_errors: List[LintError] = []
    file_count = 0

    for fpath in files:
        if not os.path.exists(fpath):
            all_errors.append(LintError(fpath, 1, 1, "file not found"))
            continue
        file_count += 1
        errs = lint_file(fpath)
        all_errors.extend(errs)

    if all_errors:
        for err in all_errors:
            print(str(err), file=sys.stderr)
        if not quiet:
            print(f"\n[FAIL] S-expression parenthesis linter detected {len(all_errors)} error(s) across {file_count} file(s).", file=sys.stderr)
        return 1
    else:
        if not quiet:
            print(f"[PASS] S-expression parenthesis check passed for {file_count} file(s) (all balanced).")
        return 0


if __name__ == "__main__":
    sys.exit(main())
