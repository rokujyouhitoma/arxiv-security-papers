#!/usr/bin/env python3
"""
Meta-Grammar Parser for .peg grammar specifications using Packrat PEG combinators.
Bootstrapped using src/core/structures/peg.py.
Conforms to DSN-25 Phase 2 Ahead-of-Time PEG Compiler specification.
Zero external dependencies.
"""

from __future__ import annotations

import re
from typing import Any, List, Match, Optional, Tuple, cast

from core.structures.peg import (
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
from core.structures.peg_compiler.ast_nodes import (
    ActionExpr,
    ChoiceExpr,
    Expression,
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
            from core.structures.peg_compiler.generated_meta_parser import (
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
        """Builds PEG combinator rules for parsing .peg files."""
        # Whitespace and comments
        ws = Reg(r"(?:\s+|#[^\r\n]*)*")

        def lex(p: Parser[Any]) -> Parser[Any]:
            return Seq(p, ws).map(lambda res: res[0])

        # Atomic tokens
        ident_tok = lex(Reg(r"[A-Za-z_][A-Za-z0-9_]*"))
        str_dq = lex(Reg(r'"(?:[^"\\]|\\.)*"'))
        str_sq = lex(Reg(r"'(?:[^'\\]|\\.)*'"))
        regex_tok = lex(Reg(r"/(?![ \t\r\n])((?:[^\r\n/\\]|\\.)+)/"))

        # Semantic action code block: { ... }
        action_tok = lex(ActionBlockParser())

        # Punctuation
        eq_tok = lex(Lit("="))
        slash_tok = lex(Choice(Lit("/"), Lit("|")))
        colon_tok = lex(Lit(":"))
        lparen = lex(Lit("("))
        rparen = lex(Lit(")"))
        star_tok = lex(Lit("*"))
        plus_tok = lex(Lit("+"))
        question_tok = lex(Lit("?"))
        amp_tok = lex(Lit("&"))
        excl_tok = lex(Lit("!"))

        # Directives
        grammar_kw = lex(Lit("grammar"))
        header_kw = lex(Lit("@header"))

        # Forward references for mutual recursion
        choice_ref = RuleRef("choice_expr")

        # Primary expressions
        lit_p = Choice(str_dq, str_sq).map(
            lambda s: LitExpr(_unescape_string(cast(str, s)))
        )
        reg_p = regex_tok.map(
            lambda m: RegexExpr(cast(str, m)[1:-1].replace(r"\/", "/"))
        )
        group_p = Seq(lparen, choice_ref, rparen).map(lambda res: res[1])
        ref_p = ident_tok.map(lambda name: RuleRefExpr(cast(str, name)))

        primary = Choice(lit_p, reg_p, group_p, ref_p)

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
        suffixed = Seq(primary, Opt(suffix_op)).map(_apply_suffix)

        # Prefix: &, !, or name:
        def _make_named(res: List[Any]) -> Expression:
            return NamedExpr(name=cast(str, res[0]), expr=cast(Expression, res[2]))

        named_p = Seq(ident_tok, colon_tok, suffixed).map(_make_named)
        pos_pred = Seq(amp_tok, suffixed).map(
            lambda res: PredExpr(cast(Expression, res[1]), is_positive=True)
        )
        neg_pred = Seq(excl_tok, suffixed).map(
            lambda res: PredExpr(cast(Expression, res[1]), is_positive=False)
        )
        prefixed_item = Choice(named_p, pos_pred, neg_pred, suffixed)
        new_rule_head = Seq(ident_tok, eq_tok)
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

        # Choice of sequences
        def _make_choice(res: List[Any]) -> Expression:
            first = cast(Expression, res[0])
            rest = cast(List[Any], res[1])
            if not rest:
                return first
            alts = [first] + [cast(Expression, r[1]) for r in rest]
            return ChoiceExpr(alts)

        choice_p = Seq(alt_expr, ZeroOrMore(Seq(slash_tok, alt_expr))).map(_make_choice)
        choice_ref.define(choice_p)

        # Rule definition: name = choice [action]
        def _make_rule(res: List[Any]) -> RuleDef:
            name = cast(str, res[0])
            final_expr = cast(Expression, res[2])
            act = res[3]
            if act is not None:
                final_expr = ActionExpr(final_expr, cast(str, act))
            return RuleDef(name=name, expr=final_expr)

        rule_def = Seq(ident_tok, eq_tok, choice_p, Opt(action_tok)).map(_make_rule)

        # Directives
        grammar_decl = Seq(grammar_kw, ident_tok).map(lambda res: res[1])
        header_decl = Seq(header_kw, action_tok).map(lambda res: cast(str, res[1]))

        # Complete Grammar
        def _assemble_grammar(res: List[Any]) -> GrammarDef:
            g_name = res[1]
            hdr = res[2]
            rules = cast(List[Any], res[3])
            name_str = cast(str, g_name) if g_name is not None else "GeneratedParser"
            hdr_str = cast(str, hdr) if hdr is not None else ""
            rule_list = [cast(RuleDef, r) for r in rules]
            start_r = rule_list[0].name if rule_list else None
            return GrammarDef(
                name=name_str,
                rules=rule_list,
                header_code=hdr_str,
                start_rule=start_r,
            )

        complete_grammar = Seq(
            ws,
            Opt(grammar_decl),
            Opt(header_decl),
            OneOrMore(rule_def),
            Opt(ws),
        ).map(_assemble_grammar)

        return complete_grammar
