#!/usr/bin/env python3
"""
Unit tests for Packrat PEG DDL, TCL, DCL, and Admin SQL Parsers.
Verifies pure Python PEG parsing of schema definitions, migrations, transactions, and administration statements.
"""

import pytest

from database.sql.admin_parser import parse_admin
from database.sql.ast import (
    AlterTableAction,
    AlterTableStatement,
    AnalyzeStatement,
    AttachStatement,
    BeginStatement,
    CommitStatement,
    CreateIndexStatement,
    CreateTableStatement,
    CreateTriggerStatement,
    CreateViewStatement,
    CreateVirtualTableStatement,
    DetachStatement,
    DropIndexStatement,
    DropTableStatement,
    DropTriggerStatement,
    DropViewStatement,
    ExplainStatement,
    GrantStatement,
    PragmaStatement,
    ReindexStatement,
    RevokeStatement,
    RollbackStatement,
    SavepointStatement,
    ShowStatement,
    VacuumStatement,
)
from database.sql.ddl_parser import parse_ddl
from database.sql.parser import SQLParseError, SQLParser, parse_sql


class TestDDLCreateTable:
    def test_create_table_basic(self) -> None:
        sql = "CREATE TABLE users (id INTEGER PRIMARY KEY, name TEXT NOT NULL, age INT)"
        stmt = parse_ddl(sql)
        assert isinstance(stmt, CreateTableStatement)
        assert stmt.table_name == "users"
        assert len(stmt.columns) == 3
        assert stmt.columns[0].name == "id"
        assert stmt.columns[0].is_primary_key is True
        assert stmt.columns[1].name == "name"
        assert stmt.columns[1].is_nullable is False
        assert stmt.strict is False

    def test_create_table_if_not_exists_and_strict(self) -> None:
        sql = "CREATE TABLE IF NOT EXISTS audit_log (id INT PRIMARY KEY, action TEXT) STRICT"
        stmt = parse_ddl(sql)
        assert isinstance(stmt, CreateTableStatement)
        assert stmt.if_not_exists is True
        assert stmt.strict is True

    def test_create_table_generated_column_and_collate(self) -> None:
        sql = (
            "CREATE TABLE items ("
            "price REAL, "
            "tax REAL, "
            "total REAL GENERATED ALWAYS AS (price + tax) STORED, "
            "code TEXT COLLATE NOCASE"
            ")"
        )
        stmt = parse_ddl(sql)
        assert isinstance(stmt, CreateTableStatement)
        cols = {c.name: c for c in stmt.columns}
        assert cols["total"].generated_expr == "price + tax"
        assert cols["total"].is_stored is True
        assert cols["code"].collate == "NOCASE"

    def test_create_table_foreign_keys(self) -> None:
        sql = (
            "CREATE TABLE orders ("
            "id INT PRIMARY KEY, "
            "user_id INT REFERENCES users(id) ON DELETE CASCADE ON UPDATE RESTRICT, "
            "CONSTRAINT fk_item FOREIGN KEY (item_id) REFERENCES items(id) ON DELETE SET NULL"
            ")"
        )
        stmt = parse_ddl(sql)
        assert isinstance(stmt, CreateTableStatement)
        assert len(stmt.foreign_keys) == 2
        fk1 = stmt.foreign_keys[0]
        assert fk1.child_column == "user_id"
        assert fk1.parent_table == "users"
        assert fk1.parent_column == "id"
        assert fk1.on_delete == "CASCADE"
        assert fk1.on_update == "RESTRICT"

    def test_create_virtual_table(self) -> None:
        sql = "CREATE VIRTUAL TABLE docs USING fts5(title, body)"
        stmt = parse_ddl(sql)
        assert isinstance(stmt, CreateVirtualTableStatement)
        assert stmt.table_name == "docs"
        assert stmt.module_name == "fts5"
        assert stmt.module_args == ["title", "body"]

    def test_create_index_and_unique(self) -> None:
        sql = "CREATE UNIQUE INDEX idx_user_email ON users (email)"
        stmt = parse_ddl(sql)
        assert isinstance(stmt, CreateIndexStatement)
        assert stmt.index_name == "idx_user_email"
        assert stmt.table_name == "users"
        assert stmt.column_name == "email"

    def test_create_view(self) -> None:
        sql = "CREATE VIEW active_users AS SELECT id, name FROM users WHERE active = 1"
        stmt = parse_ddl(sql)
        assert isinstance(stmt, CreateViewStatement)
        assert stmt.view_name == "active_users"
        assert stmt.select_stmt is not None
        assert stmt.select_stmt.table_name == "users"

    def test_create_trigger(self) -> None:
        sql = (
            "CREATE TRIGGER trg_audit AFTER INSERT ON users BEGIN "
            "INSERT INTO audit_log (action) VALUES ('insert'); "
            "END"
        )
        stmt = parse_ddl(sql)
        assert isinstance(stmt, CreateTriggerStatement)
        assert stmt.trigger_name == "trg_audit"
        assert stmt.timing == "AFTER"
        assert stmt.event == "INSERT"
        assert stmt.table_name == "users"
        assert len(stmt.body_sqls) == 1


class TestDDLAlterAndDrop:
    def test_alter_table_rename_table(self) -> None:
        sql = "ALTER TABLE users RENAME TO accounts"
        stmt = parse_ddl(sql)
        assert isinstance(stmt, AlterTableStatement)
        assert stmt.action == AlterTableAction.RENAME_TABLE
        assert stmt.new_table_name == "accounts"

    def test_alter_table_rename_column(self) -> None:
        sql = "ALTER TABLE users RENAME COLUMN name TO full_name"
        stmt = parse_ddl(sql)
        assert isinstance(stmt, AlterTableStatement)
        assert stmt.action == AlterTableAction.RENAME_COLUMN
        assert stmt.old_column_name == "name"
        assert stmt.new_column_name == "full_name"

    def test_alter_table_add_column(self) -> None:
        sql = "ALTER TABLE users ADD COLUMN bio TEXT DEFAULT 'N/A'"
        stmt = parse_ddl(sql)
        assert isinstance(stmt, AlterTableStatement)
        assert stmt.action == AlterTableAction.ADD_COLUMN
        assert stmt.column_def is not None
        assert stmt.column_def.name == "bio"
        assert stmt.default_value == "N/A"

    def test_alter_table_drop_column(self) -> None:
        sql = "ALTER TABLE users DROP COLUMN old_notes"
        stmt = parse_ddl(sql)
        assert isinstance(stmt, AlterTableStatement)
        assert stmt.action == AlterTableAction.DROP_COLUMN
        assert stmt.drop_column_name == "old_notes"

    def test_drop_statements(self) -> None:
        assert isinstance(parse_ddl("DROP TABLE IF EXISTS users"), DropTableStatement)
        assert isinstance(
            parse_ddl("DROP INDEX IF EXISTS idx_email"), DropIndexStatement
        )
        assert isinstance(parse_ddl("DROP VIEW IF EXISTS v_active"), DropViewStatement)
        assert isinstance(
            parse_ddl("DROP TRIGGER IF EXISTS trg_audit"), DropTriggerStatement
        )
        assert isinstance(parse_ddl("REINDEX users"), ReindexStatement)


class TestAdminTCLAndDCL:
    def test_tcl_statements(self) -> None:
        assert isinstance(parse_admin("BEGIN TRANSACTION"), BeginStatement)
        assert isinstance(parse_admin("COMMIT"), CommitStatement)
        assert isinstance(parse_admin("ROLLBACK"), RollbackStatement)
        assert isinstance(parse_admin("SAVEPOINT sp1"), SavepointStatement)
        assert isinstance(parse_admin("ROLLBACK TO SAVEPOINT sp1"), SavepointStatement)
        assert isinstance(parse_admin("RELEASE SAVEPOINT sp1"), SavepointStatement)

    def test_dcl_grant_and_revoke(self) -> None:
        g = parse_admin("GRANT ALL PRIVILEGES ON users TO admin")
        assert isinstance(g, GrantStatement)
        assert g.permission == "ALL"
        assert g.table_name == "users"
        assert g.role == "admin"

        r = parse_admin("REVOKE SELECT ON users FROM guest")
        assert isinstance(r, RevokeStatement)
        assert r.permission == "SELECT"
        assert r.table_name == "users"
        assert r.role == "guest"

    def test_admin_utilities(self) -> None:
        p = parse_admin("PRAGMA foreign_keys = ON")
        assert isinstance(p, PragmaStatement)
        assert p.pragma_name == "foreign_keys"

        v = parse_admin("VACUUM INTO 'backup.db'")
        assert isinstance(v, VacuumStatement)
        assert v.into_file == "backup.db"

        an = parse_admin("ANALYZE main.users")
        assert isinstance(an, AnalyzeStatement)
        assert an.schema_name == "main"
        assert an.target_name == "users"

        att = parse_admin("ATTACH DATABASE 'test.db' AS test_db")
        assert isinstance(att, AttachStatement)
        assert att.schema_name == "test_db"

        det = parse_admin("DETACH DATABASE test_db")
        assert isinstance(det, DetachStatement)
        assert det.schema_name == "test_db"

        sh = parse_admin("SHOW TABLES")
        assert isinstance(sh, ShowStatement)
        assert sh.target == "TABLES"

        exp = parse_admin("EXPLAIN QUERY PLAN SELECT * FROM users")
        assert isinstance(exp, ExplainStatement)
        assert exp.query_plan is True


class TestUnifiedSQLParser:
    def test_unified_dispatcher(self) -> None:
        parser = SQLParser()
        # DQL
        assert parser.parse("SELECT * FROM users").command_type.name == "SELECT"
        # DML
        assert (
            parser.parse("INSERT INTO users VALUES (1, 'alice')").command_type.name
            == "INSERT"
        )
        # DDL
        assert (
            parser.parse("CREATE TABLE t1 (id INT)").command_type.name == "CREATE_TABLE"
        )
        # Admin
        assert parser.parse("PRAGMA journal_mode = WAL").command_type.name == "PRAGMA"

    def test_empty_and_error(self) -> None:
        with pytest.raises(SQLParseError):
            parse_sql("")
        with pytest.raises(SQLParseError):
            parse_sql("SOMETHING UNRECOGNIZED")
