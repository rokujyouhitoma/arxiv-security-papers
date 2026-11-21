#!/usr/bin/env python3
"""
Meta-Grammar Parser for .peg grammar specifications using Packrat PEG combinators.
Bootstrapped using src/core/structures/peg.py.
Conforms to DSN-25 Phase 2 Ahead-of-Time PEG Compiler specification.
Zero external dependencies.
"""

from __future__ import annotations

import re
from typing import Any, Dict, List, Match, Optional, Tuple, cast

from core.peg.compiler.ast_nodes import (
    ActionExpr,
    AnyCharExpr,
    CharClassExpr,
    ChoiceExpr,
    CutExpr,
    Expression,
    GatherExpr,
    GrammarDef,
    LitExpr,
    NamedExpr,
    OptExpr,
    PredExpr,
    RegexExpr,
    RepeatExpr,
    RuleDef,
    RuleRefExpr,
    SeqExpr,
)
from core.peg.runtime import (
    Choice,
    Lit,
    NotPred,
    OneOrMore,
    Opt,
    ParseContext,
    Parser,
    ParseResult,
    Reg,
    RuleRef,
    Seq,
    ZeroOrMore,
)


def _unescape_char(char: str) -> str:
    escapes = {"n": "\n", "t": "\t", "r": "\r", '"': '"', "'": "'", "\\": "\\"}
    return escapes.get(char, char)


def _unescape_match(m: Match[str]) -> str:
    return _unescape_char(m.group(1))


def _unescape_string(raw: str) -> str:
    """Decodes escaped characters in string literals."""
    content = raw[1:-1]
    return re.sub(r"\\(.)", _unescape_match, content)


def _step_quote(ch: str, in_quote: Optional[str]) -> Optional[str]:
    if in_quote is None and ch in ('"', "'"):
        return ch
    if in_quote is not None and ch == in_quote:
        return None
    return in_quote


def _step_brace(ch: str, depth: int) -> int:
    if ch == "{":
        return depth + 1
    if ch == "}":
        return depth - 1
    return depth


def _is_closing_brace(in_quote: Optional[str], depth: int, i: int, start: int) -> bool:
    return in_quote is None and depth == 0 and i > start


def _scan_step(
    text: str, i: int, in_quote: Optional[str], depth: int, start: int
) -> Tuple[int, Optional[str], int, bool]:
    ch = text[i]
    if in_quote is not None and ch == "\\":
        return (i + 2, in_quote, depth, False)
    new_quote = _step_quote(ch, in_quote)
    new_depth = depth if new_quote is not None else _step_brace(ch, depth)
    is_closed = _is_closing_brace(new_quote, new_depth, i, start)
    return (i + 1, new_quote, new_depth, is_closed)


def _is_preceded_by_newline(text: str, pos: int) -> bool:
    i = pos - 1
    while i >= 0 and text[i] in (" ", "\t", "\r"):
        i -= 1
    return i < 0 or text[i] == "\n"


class LineStartParser(Parser[None]):
    """Zero-width assertion parser that succeeds if at pos 0 or preceded by a newline."""

    def __init__(self) -> None:
        super().__init__("line_start")

    def parse_at(self, ctx: ParseContext, pos: int) -> ParseResult[None]:
        if pos == 0 or _is_preceded_by_newline(ctx.text, pos):
            return ParseResult(True, None, pos)
        return ParseResult(False, None, pos, "Not at line start")


class ActionBlockParser(Parser[str]):
    """PEG parser that extracts semantic action code '{ ... }' handling strings and nested braces."""

    def parse_at(self, ctx: ParseContext, pos: int) -> ParseResult[str]:
        text = ctx.text
        if pos >= len(text) or text[pos] != "{":
            ctx.update_max_pos(pos, "'{'")
            return ParseResult(False, None, pos, "Expected '{'")

        end_pos = self._find_matching_brace(text, pos)
        if end_pos < 0:
            ctx.update_max_pos(pos, "'}'")
            return ParseResult(False, None, pos, "Unclosed action block '{'")

        body = text[pos + 1 : end_pos]
        return ParseResult(True, body, end_pos + 1)

    def _find_matching_brace(self, text: str, start: int) -> int:
        depth = 0
        i = start
        n = len(text)
        in_quote: Optional[str] = None
        while i < n:
            next_i, in_quote, depth, is_closed = _scan_step(
                text, i, in_quote, depth, start
            )
            if is_closed:
                return i
            i = next_i
        return -1


class MetaGrammarParser:
    """Packrat PEG parser that parses .peg grammar files into GrammarDef AST.

    Uses AOT compiled generated_meta_parser if available, falling back to combinators.
    """

    def __init__(self, use_aot: bool = True) -> None:
        self.use_aot = use_aot
        self._aot_parser: Optional[Any] = None
        self._combinator_parser: Optional[Parser[GrammarDef]] = None

        if self.use_aot:
            self._try_load_aot()

        if self._aot_parser is None:
            self._combinator_parser = self._build_grammar()

    def _try_load_aot(self) -> None:
        try:
            from core.peg.compiler.generated_meta_parser import (
                MetaGrammarParser as GeneratedParser,
            )

            self._aot_parser = GeneratedParser()
        except ImportError:
            self._aot_parser = None

    def parse(self, text: str) -> GrammarDef:
        """Parses PEG grammar specification text into GrammarDef AST."""
        if self._aot_parser is not None:
            try:
                return cast(GrammarDef, self._aot_parser.parse(text))
            except Exception:
                if self._combinator_parser is None:
                    self._combinator_parser = self._build_grammar()
                return self._combinator_parser.parse(text)

        if self._combinator_parser is None:
            self._combinator_parser = self._build_grammar()
        return self._combinator_parser.parse(text)

    def _build_grammar(self) -> Parser[GrammarDef]:
        """Builds PEG combinator rules for parsing .peg and .gram files."""
        # Whitespace and comments (including blank lines)
        ws = Reg(r"(?:\s+|#[^\r\n]*)*")

        def lex(p: Parser[Any]) -> Parser[Any]:
            return Seq(p, ws).map(lambda res: res[0])

        # Atomic tokens
        ident_tok = lex(Reg(r"[A-Za-z_][A-Za-z0-9_]*"))
        # Strings: support triple quotes (''' or """) as well as single/double
        str_tq_sq = lex(Reg(r"'''(?:[^'\\]|\\.|'(?!'')|''(?!'))*'''"))
        str_tq_dq = lex(Reg(r'"""(?:[^"\\]|\\.|"(?!"")|""(?!"))*"""'))
        str_dq = lex(Reg(r'"(?:[^"\\]|\\.)*"'))
        str_sq = lex(Reg(r"'(?:[^'\\]|\\.)*'"))
        regex_tok = lex(Reg(r"/(?![ \t\r\n])((?:[^\r\n/\\]|\\.)+)/"))

        # Semantic action code block: { ... }
        action_tok = lex(ActionBlockParser())

        # Punctuation & Operators
        arrow_tok = lex(Choice(Lit("<-"), Lit(":"), Lit("=")))
        slash_tok = lex(Choice(Lit("/"), Lit("|")))
        pipe_tok = lex(Lit("|"))
        colon_tok = lex(Lit(":"))
        equal_tok = lex(Lit("="))
        tilde_tok = lex(Lit("~"))
        lparen = lex(Lit("("))
        rparen = lex(Lit(")"))
        lbracket = lex(Lit("["))
        rbracket = lex(Lit("]"))
        star_tok = lex(Lit("*"))
        plus_tok = lex(Lit("+"))
        question_tok = lex(Lit("?"))
        amp_tok = lex(Choice(Lit("&&"), Lit("&")))
        excl_tok = lex(Lit("!"))
        dot_tok = lex(Lit("."))

        # Directives
        grammar_kw = lex(Reg(r"grammar\b"))
        directive_prefix = lex(Reg(r"@[A-Za-z_][A-Za-z0-9_]*"))

        # Forward references for mutual recursion
        choice_ref = RuleRef("choice_expr")

        # String literals (single, double, or triple quoted)
        def _parse_str_lit(s: Any) -> Expression:
            raw = cast(str, s)
            if raw.startswith("'''") or raw.startswith('"""'):
                content = raw[3:-3]
            else:
                content = _unescape_string(raw)
            return LitExpr(content)

        lit_p = Choice(str_tq_sq, str_tq_dq, str_dq, str_sq).map(_parse_str_lit)
        reg_p = regex_tok.map(
            lambda m: RegexExpr(cast(str, m)[1:-1].replace(r"\/", "/"))
        )

        # Character classes vs Optional bracketed expressions:
        # e.g. [a-z0-9], [^0-9], [ \t\r\n] vs [statements], [';'], [a | b]
        bracket_tok = lex(Reg(r"\[(?:\^)?(?:\\\]|[^\]])+\]"))

        def _parse_bracket_expr(raw: Any) -> Expression:
            s = cast(str, raw)
            if s.startswith("[^"):
                return CharClassExpr(raw_spec=s[2:-1], inverted=True)
            inner_content = s[1:-1]
            stripped = inner_content.strip()
            if stripped:
                try:
                    sub_ctx = ParseContext(stripped)
                    sub_res = choice_ref.parse_at(sub_ctx, 0)
                    if sub_res.success and sub_res.next_pos == len(stripped):
                        return OptExpr(cast(Expression, sub_res.value))
                except Exception:
                    pass
            return CharClassExpr(raw_spec=inner_content, inverted=False)

        bracket_p = bracket_tok.map(_parse_bracket_expr)
        dot_p = dot_tok.map(lambda _: AnyCharExpr())
        group_p = Seq(lparen, choice_ref, rparen).map(lambda res: res[1])
        ref_p = ident_tok.map(lambda name: RuleRefExpr(cast(str, name)))

        primary = Choice(lit_p, reg_p, bracket_p, dot_p, group_p, ref_p)

        # Separator-delimited list: sep.rule+ or sep.rule*
        # (e.g. ','.statement+ or ';'.simple_stmt+)
        def _make_gather(res: List[Any]) -> Expression:
            sep = cast(Expression, res[0])
            elem = cast(Expression, res[2])
            op = cast(str, res[3])
            return GatherExpr(separator=sep, element=elem, is_one_or_more=(op == "+"))

        gather_p = Seq(primary, dot_tok, primary, Choice(plus_tok, star_tok)).map(
            _make_gather
        )

        primary_or_gather = Choice(gather_p, primary)

        # Suffix: *, +, ?
        def _apply_suffix(res: List[Any]) -> Expression:
            node = cast(Expression, res[0])
            suff = res[1]
            if suff == "*":
                return RepeatExpr(node, min_count=0)
            if suff == "+":
                return RepeatExpr(node, min_count=1)
            if suff == "?":
                return OptExpr(node)
            return node

        suffix_op = Choice(star_tok, plus_tok, question_tok)
        suffixed = Seq(primary_or_gather, Opt(suffix_op)).map(_apply_suffix)

        # Prefix: &, !, name=, name:, name[type]=, or cut ~
        cut_item = tilde_tok.map(lambda _: CutExpr())

        # Type annotation in brackets: e.g. [asdl_stmt_seq*] or [expr_ty]
        type_annotation = Seq(lbracket, Reg(r"[^\]]+"), rbracket).map(
            lambda r: cast(str, r[1]).strip()
        )

        def _make_named(res: List[Any]) -> Expression:
            name = cast(str, res[0])
            # res[1] is optional type annotation
            # res[2] is = or :
            inner = cast(Expression, res[3])
            return NamedExpr(name=name, expr=inner)

        name_binder = Seq(
            ident_tok, Opt(type_annotation), Choice(equal_tok, colon_tok), suffixed
        ).map(_make_named)

        pos_pred = Seq(amp_tok, suffixed).map(
            lambda res: PredExpr(cast(Expression, res[1]), is_positive=True)
        )
        neg_pred = Seq(excl_tok, suffixed).map(
            lambda res: PredExpr(cast(Expression, res[1]), is_positive=False)
        )

        prefixed_item = Choice(cut_item, name_binder, pos_pred, neg_pred, suffixed)

        # Line start assertion
        line_start = LineStartParser()

        # Check for start of a new rule definition:
        # Ford syntax (ident <-) is always a rule head.
        # CPython syntax (ident:) or equals (ident=) must be at line start.
        memo_modifier = Seq(lparen, ident_tok, rparen).map(lambda r: cast(str, r[1]))
        ford_rule_head = Seq(ident_tok, Lit("<-"))
        cpython_rule_head = Seq(
            line_start,
            ident_tok,
            Opt(type_annotation),
            Opt(memo_modifier),
            Choice(Lit(":"), Lit("=")),
        )
        new_rule_head = Choice(ford_rule_head, cpython_rule_head)

        prefixed = Seq(NotPred(new_rule_head), prefixed_item).map(
            lambda res: cast(Expression, res[1])
        )

        # Sequence of prefixed elements
        def _make_seq(items: List[Any]) -> Expression:
            exprs = [cast(Expression, x) for x in items]
            return exprs[0] if len(exprs) == 1 else SeqExpr(exprs)

        seq_expr = OneOrMore(prefixed).map(_make_seq)

        # Sequence with optional semantic action
        def _make_seq_with_action(res: List[Any]) -> Expression:
            base_ast = cast(Expression, res[0])
            act = res[1]
            if act is not None:
                return ActionExpr(base_ast, cast(str, act))
            return base_ast

        alt_expr = Seq(seq_expr, Opt(action_tok)).map(_make_seq_with_action)

        # Choice of sequences, supporting leading '|' (CPython syntax)
        def _make_choice(res: List[Any]) -> Expression:
            # res[0] is optional leading pipe '|'
            first = cast(Expression, res[1])
            rest = cast(List[Any], res[2])
            if not rest:
                return first
            alts = [first] + [cast(Expression, r[1]) for r in rest]
            return ChoiceExpr(alts)

        choice_p = Seq(
            Opt(pipe_tok), alt_expr, ZeroOrMore(Seq(slash_tok, alt_expr))
        ).map(_make_choice)
        choice_ref.define(choice_p)

        # Rule definition:
        # rule_name [type]? (modifier)? <-/:/= choice [action]?
        def _make_rule(res: List[Any]) -> RuleDef:
            name = cast(str, res[0])
            ret_type = cast(Optional[str], res[1])
            modifier = cast(Optional[str], res[2])
            # res[3] is arrow_tok
            final_expr = cast(Expression, res[4])
            act = res[5]
            if act is not None:
                final_expr = ActionExpr(final_expr, cast(str, act))
            modifiers = [modifier] if modifier else []
            return RuleDef(
                name=name,
                expr=final_expr,
                return_type=ret_type,
                modifiers=modifiers,
            )

        rule_def = Seq(
            ident_tok,
            Opt(type_annotation),
            Opt(memo_modifier),
            arrow_tok,
            choice_p,
            Opt(action_tok),
        ).map(_make_rule)

        # Directives
        # grammar <name>
        grammar_decl = Seq(grammar_kw, ident_tok).map(
            lambda res: ("grammar", cast(str, res[1]))
        )

        # Generic directives: @directive_name <action_block or string or ident>
        directive_val = Choice(
            action_tok,
            str_tq_sq.map(lambda s: cast(str, s)[3:-3]),
            str_tq_dq.map(lambda s: cast(str, s)[3:-3]),
            str_dq.map(lambda s: _unescape_string(cast(str, s))),
            str_sq.map(lambda s: _unescape_string(cast(str, s))),
            ident_tok,
        )
        directive_decl = Seq(directive_prefix, directive_val).map(
            lambda res: (cast(str, res[0]), cast(str, res[1]))
        )

        header_or_directive = Choice(grammar_decl, directive_decl)

        # Complete Grammar
        def _assemble_grammar(res: List[Any]) -> GrammarDef:
            directives_list = cast(List[Tuple[str, str]], res[1])
            rules = cast(List[Any], res[2])

            directives_dict: Dict[str, str] = {}
            g_name = "GeneratedParser"
            header_code = ""

            for k, v in directives_list:
                directives_dict[k] = v
                if k in ("grammar", "@class"):
                    g_name = v
                elif k == "@header":
                    header_code = v

            rule_list = [cast(RuleDef, r) for r in rules]
            start_r = rule_list[0].name if rule_list else None
            return GrammarDef(
                name=g_name,
                rules=rule_list,
                header_code=header_code,
                start_rule=start_r,
                directives=directives_dict,
            )

        complete_grammar = Seq(
            ws,
            ZeroOrMore(header_or_directive),
            OneOrMore(rule_def),
            Opt(ws),
        ).map(_assemble_grammar)

        return complete_grammar
