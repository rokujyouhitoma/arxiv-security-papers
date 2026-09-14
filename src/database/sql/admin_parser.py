#!/usr/bin/env python3
"""
Pure Python Packrat PEG Parser for SQL TCL, DCL, Admin, and Utility Statements.
Parses BEGIN, COMMIT, ROLLBACK, SAVEPOINT, RELEASE, GRANT, REVOKE,
PRAGMA, VACUUM, ANALYZE, ATTACH, DETACH, EXPLAIN, SHOW
into typed AST objects without external dependencies.
"""

from __future__ import annotations

import re
from typing import Any

from core.structures.peg import Choice, NotPred, Opt, Parser, PEGSyntaxError, Regex, Seq

from .ast import (
    AnalyzeStatement,
    AttachStatement,
    BeginStatement,
    CommitStatement,
    DetachStatement,
    ExplainStatement,
    GrantStatement,
    PragmaStatement,
    RevokeStatement,
    RollbackStatement,
    SavepointStatement,
    ShowStatement,
    SQLCommandType,
    SQLStatement,
    VacuumStatement,
)


def _tok(p: Parser[Any]) -> Parser[Any]:
    ws = Regex(r"(\s+|#[^\r\n]*|--[^\r\n]*)*")
    return Seq(p, ws).map(lambda r: r[0])


def _kw(word: str) -> Parser[str]:
    return _tok(Regex(rf"(?i)\b{re.escape(word)}\b"))


def _ident_p() -> Parser[str]:
    p = Regex(r"[a-zA-Z_][a-zA-Z0-9_]*|\`[^\`]+\`|\[[^\]]+\]|\"[^\"]+\"|[a-zA-Z0-9_.]+")
    return _tok(p).map(lambda s: s.strip('`[]"'))


def _str_lit_p() -> Parser[str]:
    return _tok(Regex(r"'([^']*)'|\"([^\"]*)\"")).map(
        lambda s: s[1:-1] if len(s) >= 2 else s
    )


# -------------------------------------------------------------------------
# TCL Statements
# -------------------------------------------------------------------------


def _build_begin_parser() -> Parser[BeginStatement]:
    iso_p = Choice(_kw("DEFERRED"), _kw("IMMEDIATE"), _kw("EXCLUSIVE"))
    prefix = Seq(
        _kw("BEGIN"),
        Opt(iso_p),
        Opt(_kw("TRANSACTION")),
    )
    return prefix.map(
        lambda _: BeginStatement(
            command_type=SQLCommandType.BEGIN,
            raw_sql="",
        )
    )


def _build_commit_parser() -> Parser[CommitStatement]:
    return Seq(_kw("COMMIT"), Opt(_kw("TRANSACTION"))).map(
        lambda _: CommitStatement(command_type=SQLCommandType.COMMIT, raw_sql="")
    )


def _build_rollback_parser() -> Parser[SQLStatement]:
    rollback_to = Seq(
        _kw("ROLLBACK"),
        Opt(_kw("TRANSACTION")),
        _kw("TO"),
        Opt(_kw("SAVEPOINT")),
        _ident_p(),
    ).map(
        lambda r: SavepointStatement(
            command_type=SQLCommandType.ROLLBACK_TO,
            raw_sql="",
            name=str(r[4]),
            action="ROLLBACK_TO",
        )
    )

    rollback_plain = Seq(_kw("ROLLBACK"), Opt(_kw("TRANSACTION"))).map(
        lambda _: RollbackStatement(command_type=SQLCommandType.ROLLBACK, raw_sql="")
    )

    return Choice(rollback_to, rollback_plain)


def _build_savepoint_parser() -> Parser[SavepointStatement]:
    sp = Seq(_kw("SAVEPOINT"), _ident_p()).map(
        lambda r: SavepointStatement(
            command_type=SQLCommandType.SAVEPOINT,
            raw_sql="",
            name=str(r[1]),
            action="SAVEPOINT",
        )
    )

    rel = Seq(
        _kw("RELEASE"),
        Opt(_kw("SAVEPOINT")),
        _ident_p(),
    ).map(
        lambda r: SavepointStatement(
            command_type=SQLCommandType.RELEASE,
            raw_sql="",
            name=str(r[2]),
            action="RELEASE",
        )
    )

    return Choice(sp, rel)


# -------------------------------------------------------------------------
# DCL Statements
# -------------------------------------------------------------------------


def _build_grant_parser() -> Parser[GrantStatement]:
    perm_p = Choice(
        Seq(_kw("ALL"), Opt(_kw("PRIVILEGES"))).map(lambda _: "ALL"),
        _ident_p(),
    )
    tbl_p = Choice(Regex(r"\*"), _ident_p())

    return Seq(
        _kw("GRANT"),
        perm_p,
        Opt(Seq(_kw("ON"), tbl_p)),
        _kw("TO"),
        _ident_p(),
    ).map(
        lambda r: GrantStatement(
            command_type=SQLCommandType.GRANT,
            raw_sql="",
            permission=str(r[1]).upper(),
            table_name=str(r[2][1]) if r[2] else "*",
            role=str(r[4]),
        )
    )


def _build_revoke_parser() -> Parser[RevokeStatement]:
    perm_p = Choice(
        Seq(_kw("ALL"), Opt(_kw("PRIVILEGES"))).map(lambda _: "ALL"),
        _ident_p(),
    )
    tbl_p = Choice(Regex(r"\*"), _ident_p())

    return Seq(
        _kw("REVOKE"),
        perm_p,
        Opt(Seq(_kw("ON"), tbl_p)),
        _kw("FROM"),
        _ident_p(),
    ).map(
        lambda r: RevokeStatement(
            command_type=SQLCommandType.REVOKE,
            raw_sql="",
            permission=str(r[1]).upper(),
            table_name=str(r[2][1]) if r[2] else "*",
            role=str(r[4]),
        )
    )


# -------------------------------------------------------------------------
# Admin / Utility Statements
# -------------------------------------------------------------------------


def _build_pragma_parser() -> Parser[PragmaStatement]:
    val_p = Choice(_str_lit_p(), Regex(r"[a-zA-Z0-9_\-]+"))
    call_arg = _tok(Regex(r"\(\s*([a-zA-Z0-9_'\"]+)\s*\)")).map(
        lambda s: ("call", s.strip("()").strip("'\""))
    )
    eq_arg = Seq(_tok(Regex(r"=")), val_p).map(lambda r: ("eq", str(r[1]).strip("'\"")))

    return Seq(
        _kw("PRAGMA"),
        _ident_p(),
        Opt(Choice(call_arg, eq_arg)),
    ).map(
        lambda r: PragmaStatement(
            command_type=SQLCommandType.PRAGMA,
            raw_sql="",
            pragma_name=str(r[1]).lower(),
            argument=r[2][1] if (r[2] and r[2][0] == "call") else None,
            value=r[2][1] if (r[2] and r[2][0] == "eq") else None,
        )
    )


def _build_vacuum_parser() -> Parser[VacuumStatement]:
    target_p = Seq(NotPred(_kw("INTO")), _ident_p()).map(lambda r: str(r[1]))
    into_p = Seq(_kw("INTO"), _str_lit_p()).map(lambda r: str(r[1]))
    return Seq(
        _kw("VACUUM"),
        Opt(target_p),
        Opt(into_p),
    ).map(
        lambda r: VacuumStatement(
            command_type=SQLCommandType.VACUUM,
            raw_sql="",
            target_table=r[1],
            into_file=r[2],
        )
    )


def _build_analyze_parser() -> Parser[AnalyzeStatement]:
    target_p = Seq(Opt(Seq(_ident_p(), Regex(r"\."))), _ident_p()).map(
        lambda r: (str(r[0][0]) if r[0] else None, str(r[1]))
    )

    return Seq(_kw("ANALYZE"), Opt(target_p)).map(
        lambda r: AnalyzeStatement(
            command_type=SQLCommandType.ANALYZE,
            raw_sql="",
            schema_name=r[1][0] if r[1] else None,
            target_name=r[1][1] if r[1] else None,
        )
    )


def _build_attach_parser() -> Parser[AttachStatement]:
    fn_p = Choice(_str_lit_p(), Regex(r"\S+"))
    return Seq(
        _kw("ATTACH"),
        Opt(_kw("DATABASE")),
        fn_p,
        _kw("AS"),
        _ident_p(),
    ).map(
        lambda r: AttachStatement(
            command_type=SQLCommandType.ATTACH,
            raw_sql="",
            filename=str(r[2]),
            schema_name=str(r[4]),
        )
    )


def _build_detach_parser() -> Parser[DetachStatement]:
    return Seq(
        _kw("DETACH"),
        Opt(_kw("DATABASE")),
        _ident_p(),
    ).map(
        lambda r: DetachStatement(
            command_type=SQLCommandType.DETACH,
            raw_sql="",
            schema_name=str(r[2]),
        )
    )


def _build_show_parser() -> Parser[ShowStatement]:
    target_p = Choice(
        Seq(_kw("DATABASES")).map(lambda _: "DATABASES"),
        Seq(_kw("SCHEMAS")).map(lambda _: "DATABASES"),
        Seq(_kw("TABLE"), _kw("STATUS")).map(lambda _: "TABLE_STATUS"),
        Seq(_kw("TABLES")).map(lambda _: "TABLES"),
        Seq(_kw("COLUMNS")).map(lambda _: "COLUMNS"),
        Seq(_kw("INDEXES")).map(lambda _: "INDEXES"),
    )

    from_p = Seq(_kw("FROM"), _ident_p()).map(lambda r: str(r[1]))
    like_p = Seq(_kw("LIKE"), _str_lit_p()).map(lambda r: str(r[1]))

    return Seq(
        _kw("SHOW"),
        target_p,
        Opt(from_p),
        Opt(like_p),
    ).map(
        lambda r: ShowStatement(
            command_type=SQLCommandType.SHOW,
            raw_sql="",
            target=str(r[1]),
            from_database=r[2],
            like_pattern=r[3],
        )
    )


def _build_explain_parser() -> Parser[ExplainStatement]:
    from .parser import SQLParser

    qp_p = Seq(_kw("QUERY"), _kw("PLAN")).map(lambda _: True)

    return Seq(
        _kw("EXPLAIN"),
        Opt(qp_p),
        Regex(r".*"),
    ).map(
        lambda r: ExplainStatement(
            command_type=SQLCommandType.EXPLAIN,
            raw_sql="",
            statement=SQLParser().parse(str(r[2]).strip()),
            query_plan=bool(r[1]),
        )
    )


def _build_admin_grammar() -> Parser[SQLStatement]:
    return Choice(
        _build_begin_parser(),
        _build_commit_parser(),
        _build_rollback_parser(),
        _build_savepoint_parser(),
        _build_grant_parser(),
        _build_revoke_parser(),
        _build_pragma_parser(),
        _build_vacuum_parser(),
        _build_analyze_parser(),
        _build_attach_parser(),
        _build_detach_parser(),
        _build_explain_parser(),
        _build_show_parser(),
    )


class SQLAdminParser:
    """Packrat PEG Parser for SQL TCL, DCL, Admin, and Utility statements."""

    def __init__(self) -> None:
        self._grammar = _build_admin_grammar()

    def parse(self, text: str) -> SQLStatement:
        from .parser import SQLParseError

        stripped = text.strip().rstrip(";")
        if not stripped:
            raise SQLParseError("Empty SQL query")
        try:
            stmt = self._grammar.parse(stripped)
            stmt.raw_sql = text
            return stmt
        except PEGSyntaxError as exc:
            raise SQLParseError(
                f"SQL Admin syntax error at line {exc.line}, col {exc.col}: {exc.message}"
            ) from exc


def parse_admin(text: str) -> SQLStatement:
    """Convenience helper to parse an admin SQL string into SQLStatement AST."""
    parser = SQLAdminParser()
    return parser.parse(text)
