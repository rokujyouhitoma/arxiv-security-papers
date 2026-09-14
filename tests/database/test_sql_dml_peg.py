#!/usr/bin/env python3
"""Comprehensive Unit Tests for Packrat PEG DML (Data Manipulation Language) Parser.

Validates INSERT, REPLACE, UPDATE, DELETE, UPSERT, and RETURNING statements.
"""

from __future__ import annotations

import pytest

from database.sql.ast import (
    DeleteStatement,
    InsertStatement,
    SQLCommandType,
    UpdateStatement,
)
from database.sql.dml_parser import SQLParseError, parse_dml


class TestDMLInsert:
    """Tests for INSERT and REPLACE statements."""

    def test_insert_single_row(self) -> None:
        sql = "INSERT INTO users (id, name, age) VALUES (1, 'Alice', 30)"
        stmt = parse_dml(sql)
        assert isinstance(stmt, InsertStatement)
        assert stmt.command_type == SQLCommandType.INSERT
        assert stmt.table_name == "users"
        assert stmt.columns == ["id", "name", "age"]
        assert stmt.values == [1, "Alice", 30]
        assert len(stmt.rows_values) == 1

    def test_insert_multiple_rows(self) -> None:
        sql = "INSERT INTO metrics VALUES (10, 0.95), (20, 0.98), (30, 0.99)"
        stmt = parse_dml(sql)
        assert isinstance(stmt, InsertStatement)
        assert stmt.table_name == "metrics"
        assert stmt.columns == []
        assert len(stmt.rows_values) == 3
        assert stmt.rows_values[0] == [10, 0.95]
        assert stmt.rows_values[1] == [20, 0.98]
        assert stmt.rows_values[2] == [30, 0.99]

    def test_insert_select(self) -> None:
        sql = "INSERT INTO archived_papers (id, title) SELECT id, title FROM papers WHERE year < 2020"
        stmt = parse_dml(sql)
        assert isinstance(stmt, InsertStatement)
        assert stmt.table_name == "archived_papers"
        assert stmt.columns == ["id", "title"]
        assert stmt.select_stmt is not None
        assert stmt.select_stmt.table_name == "papers"

    def test_replace_into(self) -> None:
        sql = "REPLACE INTO settings (key, value) VALUES ('theme', 'dark')"
        stmt = parse_dml(sql)
        assert isinstance(stmt, InsertStatement)
        assert stmt.table_name == "settings"
        assert stmt.upsert_action == "UPDATE"

    def test_insert_upsert_do_nothing(self) -> None:
        sql = "INSERT INTO tags (id, name) VALUES (1, 'crypto') ON CONFLICT (name) DO NOTHING"
        stmt = parse_dml(sql)
        assert isinstance(stmt, InsertStatement)
        assert stmt.upsert_target == ["name"]
        assert stmt.upsert_action == "NOTHING"

    def test_insert_upsert_do_update(self) -> None:
        sql = (
            "INSERT INTO counts (id, count) VALUES ('p1', 1) "
            "ON CONFLICT (id) DO UPDATE SET count = 2"
        )
        stmt = parse_dml(sql)
        assert isinstance(stmt, InsertStatement)
        assert stmt.upsert_target == ["id"]
        assert stmt.upsert_action == "UPDATE"
        assert stmt.upsert_update_set.get("count") == 2

    def test_insert_returning(self) -> None:
        sql = "INSERT INTO logs (msg) VALUES ('started') RETURNING id, msg"
        stmt = parse_dml(sql)
        assert isinstance(stmt, InsertStatement)
        assert stmt.returning_cols == ["id", "msg"]


class TestDMLUpdate:
    """Tests for UPDATE statements."""

    def test_update_simple_set(self) -> None:
        sql = "UPDATE accounts SET balance = 500, status = 'active' WHERE id = 1"
        stmt = parse_dml(sql)
        assert isinstance(stmt, UpdateStatement)
        assert stmt.table_name == "accounts"
        assert stmt.assignments.get("balance") == 500
        assert stmt.assignments.get("status") == "active"
        assert len(stmt.where_clauses) == 1
        assert stmt.where_clauses[0]["column"] == "id"

    def test_update_with_from_join(self) -> None:
        sql = "UPDATE accounts SET balance = 1000 FROM users WHERE accounts.user_id = users.id"
        stmt = parse_dml(sql)
        assert isinstance(stmt, UpdateStatement)
        assert stmt.table_name == "accounts"
        assert stmt.from_table is not None
        assert stmt.from_table.name == "users"

    def test_update_with_order_and_limit(self) -> None:
        sql = "UPDATE queue SET status = 'processing' ORDER BY priority DESC LIMIT 5"
        stmt = parse_dml(sql)
        assert isinstance(stmt, UpdateStatement)
        assert stmt.order_by == "priority"
        assert stmt.order_desc is True
        assert stmt.limit == 5

    def test_update_returning(self) -> None:
        sql = "UPDATE users SET active = TRUE WHERE id = 42 RETURNING *"
        stmt = parse_dml(sql)
        assert isinstance(stmt, UpdateStatement)
        assert stmt.returning_cols == ["*"]


class TestDMLDelete:
    """Tests for DELETE statements."""

    def test_delete_simple(self) -> None:
        sql = "DELETE FROM cache WHERE expire_at < 1000"
        stmt = parse_dml(sql)
        assert isinstance(stmt, DeleteStatement)
        assert stmt.table_name == "cache"
        assert len(stmt.where_clauses) == 1

    def test_delete_with_order_limit_and_returning(self) -> None:
        sql = (
            "DELETE FROM tasks WHERE done = TRUE ORDER BY id ASC LIMIT 10 RETURNING id"
        )
        stmt = parse_dml(sql)
        assert isinstance(stmt, DeleteStatement)
        assert stmt.table_name == "tasks"
        assert stmt.order_by == "id"
        assert stmt.order_desc is False
        assert stmt.limit == 10
        assert stmt.returning_cols == ["id"]


class TestDMLErrorsAndEdgeCases:
    """Tests for DML error handling."""

    def test_empty_query(self) -> None:
        with pytest.raises(SQLParseError):
            parse_dml("")

    def test_insert_column_count_mismatch(self) -> None:
        with pytest.raises(SQLParseError):
            parse_dml("INSERT INTO users (a, b) VALUES (1, 2, 3)")

    def test_malformed_dml(self) -> None:
        with pytest.raises(SQLParseError):
            parse_dml("UPDATE SET balance = 10")
