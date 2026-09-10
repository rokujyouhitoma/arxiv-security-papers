#!/usr/bin/env python3
"""src/cli/completer.py

Context-aware Tab Autocompletion Engine for SQL and meta-commands.
Conforms to DSN-24 Section 4.6. Pure Python, readline integration, Xenon CC <= 5.
"""

from __future__ import annotations

import re
from typing import List, Optional, Set

from database.sql.executor import SQLExecutor

SQL_KEYWORDS = [
    "SELECT",
    "FROM",
    "WHERE",
    "INSERT INTO",
    "CREATE TABLE",
    "USING",
    "LOCATION",
    "INNER JOIN",
    "LEFT JOIN",
    "RIGHT JOIN",
    "JOIN",
    "ON",
    "GROUP BY",
    "ORDER BY",
    "LIMIT",
    "OFFSET",
    "UNION ALL",
    "UNION",
    "AS",
    "AND",
    "OR",
    "NOT",
    "IN",
    "LIKE",
    "IS NULL",
    "IS NOT NULL",
    "DESC",
    "ASC",
    "DISTINCT",
]

META_COMMANDS = [
    ".tables",
    ".schema",
    ".explain",
    ".mode",
    ".sync",
    ".help",
    ".quit",
    ".exit",
]


def _extract_previous_token(line_prefix: str, current_word: str) -> str:
    """Extracts the non-empty token immediately before the current word."""
    prefix = line_prefix
    if current_word and prefix.endswith(current_word):
        prefix = prefix[: -len(current_word)]
    tokens = re.findall(r"[\w.]+", prefix.rstrip())
    if tokens:
        return str(tokens[-1]).upper()
    return ""


def _find_tables_in_line(line_prefix: str, known_tables: Set[str]) -> Set[str]:
    """Finds known tables mentioned earlier in the statement."""
    tokens = [t.lower() for t in re.findall(r"[\w]+", line_prefix)]
    return {t for t in tokens if t in known_tables}


class SQLCompleter:
    """Stateful tab completer for readline in dbshell."""

    def __init__(self, engine: SQLExecutor) -> None:
        self.engine = engine
        self._matches: List[str] = []

    def _get_table_names(self) -> List[str]:
        return sorted(self.engine.tables.keys())

    def _get_column_candidates(self, line_prefix: str) -> List[str]:
        known = set(self._get_table_names())
        active_tables = _find_tables_in_line(line_prefix, known)
        target_tables = active_tables if active_tables else known

        cols: Set[str] = set()
        for tname in target_tables:
            if tname in self.engine.tables:
                cols.update(self.engine.tables[tname].schema.keys())
        return sorted(cols)

    def _filter_meta(self, text: str) -> List[str]:
        low = text.lower()
        return [cmd for cmd in META_COMMANDS if cmd.startswith(low)]

    def _filter_tables(self, text: str) -> List[str]:
        low = text.lower()
        return [t for t in self._get_table_names() if t.lower().startswith(low)]

    def _filter_columns(self, line_buffer: str, text: str) -> List[str]:
        cols = self._get_column_candidates(line_buffer)
        low = text.lower()
        return [c for c in cols if c.lower().startswith(low)]

    def _filter_keywords(self, text: str) -> List[str]:
        low = text.lower()
        return [kw for kw in SQL_KEYWORDS if kw.lower().startswith(low)]

    def _determine_candidates(self, line_buffer: str, text: str) -> List[str]:
        if line_buffer.lstrip().startswith("."):
            return self._filter_meta(text)

        prev = _extract_previous_token(line_buffer, text)
        if prev in ("FROM", "JOIN"):
            return self._filter_tables(text)

        if prev in ("SELECT", "WHERE", "AND", "OR", "ON", "BY"):
            matched = self._filter_columns(line_buffer, text)
            if matched:
                return matched

        return self._filter_keywords(text)

    def complete(self, text: str, state: int) -> Optional[str]:
        """Readline complete callback."""
        if state == 0:
            line_buf = text
            try:
                import readline

                buf = readline.get_line_buffer()
                if buf:
                    line_buf = buf
            except Exception:
                pass
            raw_candidates = self._determine_candidates(line_buf, text)
            self._matches = raw_candidates

        if state < len(self._matches):
            return self._matches[state]
        return None
