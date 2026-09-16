#!/usr/bin/env python3
"""Comprehensive Unit Tests for Packrat PEG SQL Admin, TCL, DCL & Utility Parser.

Tests cover:
- TCL: BEGIN, COMMIT, ROLLBACK, SAVEPOINT, RELEASE
- DCL: GRANT, REVOKE
- Admin/Utility: PRAGMA, VACUUM, ANALYZE, ATTACH, DETACH, EXPLAIN, SHOW
- Caching: LRU cache hit/miss and clear_admin_cache()
- Error handling: syntax errors, empty queries
- SQLParser integration: unified parsing and dispatch
"""

import pytest

from database.sql.admin_parser import (
    SQLAdminParser,
    SQLParseError,
    clear_admin_cache,
    parse_admin,
)
from database.sql.ast import (
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
    VacuumStatement,
)
from database.sql.parser import SQLParser, clear_sql_parser_caches, parse_sql


class TestTCLStatements:
    """Tests for Transaction Control Language statements."""

    def test_begin_variants(self) -> None:
        stmt1 = parse_admin("BEGIN")
        assert isinstance(stmt1, BeginStatement)
        assert stmt1.command_type == SQLCommandType.BEGIN

        stmt2 = parse_admin("BEGIN TRANSACTION")
        assert isinstance(stmt2, BeginStatement)

        stmt3 = parse_admin("BEGIN DEFERRED TRANSACTION")
        assert isinstance(stmt3, BeginStatement)

        stmt4 = parse_admin("BEGIN IMMEDIATE")
        assert isinstance(stmt4, BeginStatement)

        stmt5 = parse_admin("BEGIN EXCLUSIVE TRANSACTION")
        assert isinstance(stmt5, BeginStatement)

    def test_commit_variants(self) -> None:
        stmt1 = parse_admin("COMMIT")
        assert isinstance(stmt1, CommitStatement)
        assert stmt1.command_type == SQLCommandType.COMMIT

        stmt2 = parse_admin("COMMIT TRANSACTION")
        assert isinstance(stmt2, CommitStatement)

    def test_rollback_variants(self) -> None:
        stmt1 = parse_admin("ROLLBACK")
        assert isinstance(stmt1, RollbackStatement)
        assert stmt1.command_type == SQLCommandType.ROLLBACK

        stmt2 = parse_admin("ROLLBACK TRANSACTION")
        assert isinstance(stmt2, RollbackStatement)

    def test_savepoint_and_release(self) -> None:
        sp = parse_admin("SAVEPOINT my_savepoint")
        assert isinstance(sp, SavepointStatement)
        assert sp.command_type == SQLCommandType.SAVEPOINT
        assert sp.name == "my_savepoint"
        assert sp.action == "SAVEPOINT"

        rel1 = parse_admin("RELEASE my_savepoint")
        assert isinstance(rel1, SavepointStatement)
        assert rel1.command_type == SQLCommandType.RELEASE
        assert rel1.name == "my_savepoint"
        assert rel1.action == "RELEASE"

        rel2 = parse_admin("RELEASE SAVEPOINT `my_savepoint`")
        assert isinstance(rel2, SavepointStatement)
        assert rel2.name == "my_savepoint"

        rb_to = parse_admin("ROLLBACK TO SAVEPOINT my_savepoint")
        assert isinstance(rb_to, SavepointStatement)
        assert rb_to.command_type == SQLCommandType.ROLLBACK_TO
        assert rb_to.name == "my_savepoint"
        assert rb_to.action == "ROLLBACK_TO"

        rb_to_short = parse_admin("ROLLBACK TO my_savepoint")
        assert isinstance(rb_to_short, SavepointStatement)
        assert rb_to_short.name == "my_savepoint"


class TestDCLStatements:
    """Tests for Data Control Language statements (GRANT / REVOKE)."""

    def test_grant_statements(self) -> None:
        g1 = parse_admin("GRANT ALL PRIVILEGES ON users TO admin_role")
        assert isinstance(g1, GrantStatement)
        assert g1.command_type == SQLCommandType.GRANT
        assert g1.permission == "ALL"
        assert g1.table_name == "users"
        assert g1.role == "admin_role"

        g2 = parse_admin("GRANT SELECT ON * TO guest")
        assert isinstance(g2, GrantStatement)
        assert g2.permission == "SELECT"
        assert g2.table_name == "*"
        assert g2.role == "guest"

        g3 = parse_admin("GRANT ALL TO superuser")
        assert isinstance(g3, GrantStatement)
        assert g3.permission == "ALL"
        assert g3.table_name == "*"
        assert g3.role == "superuser"

    def test_revoke_statements(self) -> None:
        r1 = parse_admin("REVOKE ALL PRIVILEGES ON users FROM bad_actor")
        assert isinstance(r1, RevokeStatement)
        assert r1.command_type == SQLCommandType.REVOKE
        assert r1.permission == "ALL"
        assert r1.table_name == "users"
        assert r1.role == "bad_actor"

        r2 = parse_admin("REVOKE INSERT ON * FROM operator")
        assert isinstance(r2, RevokeStatement)
        assert r2.permission == "INSERT"
        assert r2.table_name == "*"
        assert r2.role == "operator"


class TestAdminUtilityStatements:
    """Tests for Database Admin and Utility statements."""

    def test_pragma_statements(self) -> None:
        p1 = parse_admin("PRAGMA foreign_keys = ON")
        assert isinstance(p1, PragmaStatement)
        assert p1.command_type == SQLCommandType.PRAGMA
        assert p1.pragma_name == "foreign_keys"
        assert p1.value == "ON"
        assert p1.argument is None

        p2 = parse_admin("PRAGMA table_info('users')")
        assert isinstance(p2, PragmaStatement)
        assert p2.pragma_name == "table_info"
        assert p2.argument == "users"
        assert p2.value is None

        p3 = parse_admin("PRAGMA cache_size = -2000")
        assert isinstance(p3, PragmaStatement)
        assert p3.pragma_name == "cache_size"
        assert p3.value == "-2000"

        p4 = parse_admin("PRAGMA main.cache_size")
        assert isinstance(p4, PragmaStatement)
        assert p4.pragma_name == "main.cache_size"

    def test_vacuum_statements(self) -> None:
        v1 = parse_admin("VACUUM")
        assert isinstance(v1, VacuumStatement)
        assert v1.command_type == SQLCommandType.VACUUM
        assert v1.target_table is None
        assert v1.into_file is None

        v2 = parse_admin("VACUUM users")
        assert isinstance(v2, VacuumStatement)
        assert v2.target_table == "users"

        v3 = parse_admin("VACUUM INTO 'archive.db'")
        assert isinstance(v3, VacuumStatement)
        assert v3.into_file == "archive.db"

        v4 = parse_admin("VACUUM temp_tbl INTO 'backup.sqlite'")
        assert isinstance(v4, VacuumStatement)
        assert v4.target_table == "temp_tbl"
        assert v4.into_file == "backup.sqlite"

    def test_analyze_statements(self) -> None:
        a1 = parse_admin("ANALYZE")
        assert isinstance(a1, AnalyzeStatement)
        assert a1.command_type == SQLCommandType.ANALYZE
        assert a1.schema_name is None
        assert a1.target_name is None

        a2 = parse_admin("ANALYZE users")
        assert isinstance(a2, AnalyzeStatement)
        assert a2.schema_name is None
        assert a2.target_name == "users"

        a3 = parse_admin("ANALYZE main.users")
        assert isinstance(a3, AnalyzeStatement)
        assert a3.schema_name == "main"
        assert a3.target_name == "users"

    def test_attach_and_detach(self) -> None:
        att1 = parse_admin("ATTACH DATABASE 'test.db' AS test_db")
        assert isinstance(att1, AttachStatement)
        assert att1.command_type == SQLCommandType.ATTACH
        assert att1.filename == "test.db"
        assert att1.schema_name == "test_db"

        att2 = parse_admin("ATTACH 'mydb.vdb' AS secondary")
        assert isinstance(att2, AttachStatement)
        assert att2.filename == "mydb.vdb"
        assert att2.schema_name == "secondary"

        det1 = parse_admin("DETACH DATABASE test_db")
        assert isinstance(det1, DetachStatement)
        assert det1.command_type == SQLCommandType.DETACH
        assert det1.schema_name == "test_db"

        det2 = parse_admin("DETACH secondary")
        assert isinstance(det2, DetachStatement)
        assert det2.schema_name == "secondary"

    def test_explain_statements(self) -> None:
        exp1 = parse_admin("EXPLAIN SELECT 1")
        assert isinstance(exp1, ExplainStatement)
        assert exp1.command_type == SQLCommandType.EXPLAIN
        assert exp1.query_plan is False
        assert exp1.statement is not None

        exp2 = parse_admin("EXPLAIN QUERY PLAN SELECT * FROM users WHERE id = 1")
        assert isinstance(exp2, ExplainStatement)
        assert exp2.query_plan is True
        assert exp2.statement is not None

    def test_show_statements(self) -> None:
        s1 = parse_admin("SHOW DATABASES")
        assert isinstance(s1, ShowStatement)
        assert s1.target == "DATABASES"

        s2 = parse_admin("SHOW SCHEMAS")
        assert isinstance(s2, ShowStatement)
        assert s2.target == "DATABASES"

        s3 = parse_admin("SHOW TABLE STATUS")
        assert isinstance(s3, ShowStatement)
        assert s3.target == "TABLE_STATUS"

        s4 = parse_admin("SHOW TABLES")
        assert isinstance(s4, ShowStatement)
        assert s4.target == "TABLES"

        s5 = parse_admin("SHOW TABLES FROM catalog")
        assert isinstance(s5, ShowStatement)
        assert s5.target == "TABLES"
        assert s5.from_database == "catalog"

        s6 = parse_admin("SHOW TABLES LIKE 'user_%'")
        assert isinstance(s6, ShowStatement)
        assert s6.target == "TABLES"
        assert s6.like_pattern == "user_%"

        s7 = parse_admin("SHOW COLUMNS FROM users")
        assert isinstance(s7, ShowStatement)
        assert s7.target == "COLUMNS"
        assert s7.from_database == "users"

        s8 = parse_admin("SHOW INDEXES FROM users")
        assert isinstance(s8, ShowStatement)
        assert s8.target == "INDEXES"
        assert s8.from_database == "users"


class TestSQLAdminParserClassAndErrors:
    """Tests for SQLAdminParser class, error handling, and cache management."""

    def test_parser_class_instance(self) -> None:
        parser = SQLAdminParser()
        res = parser.parse("COMMIT")
        assert isinstance(res, CommitStatement)

    def test_empty_input_raises_error(self) -> None:
        with pytest.raises(SQLParseError, match="Empty SQL query"):
            parse_admin("")
        with pytest.raises(SQLParseError, match="Empty SQL query"):
            parse_admin("   ;; ")

    def test_invalid_syntax_raises_error(self) -> None:
        with pytest.raises(SQLParseError, match="SQL Admin syntax error"):
            parse_admin("BEGIN INVALID SYNTAX EXTRA")

    def test_cache_clearing(self) -> None:
        parse_admin("BEGIN")
        clear_admin_cache()
        clear_sql_parser_caches()

    def test_dispatcher_integration(self) -> None:
        res = parse_sql("BEGIN TRANSACTION")
        assert isinstance(res, BeginStatement)

        res_show = parse_sql("SHOW TABLES;")
        assert isinstance(res_show, ShowStatement)

        dispatcher = SQLParser()
        res_class = dispatcher.parse("COMMIT")
        assert isinstance(res_class, CommitStatement)
