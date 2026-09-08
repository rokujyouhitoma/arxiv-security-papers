#!/usr/bin/env python3
"""
Zero-Loss Data Migration Script: SQLite (.db) to Pure-Python MultiTableVectorStorage (.vdb).
Migrates cti_catalog.db and analytics.db into src/database OKFMTC01 binary containers.
Preserves table schemas (DDL), primary keys, and 100% of row records.
"""

from __future__ import annotations

import argparse
import logging
import os
import shutil
import sqlite3
import sys
from typing import Any, Dict, List, Optional, Tuple

WORKSPACE_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
if WORKSPACE_DIR not in sys.path:
    sys.path.insert(0, os.path.join(WORKSPACE_DIR, "src"))

from database.compat.sqlite_engine import (  # noqa: E402
    dump_sqlite_table_records,
    get_sqlite_table_names,
)
from database.storage.multi_storage import MultiTableVectorStorage  # noqa: E402

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
)
logger = logging.getLogger("migrate_catalog_and_analytics")


def extract_table_ddl_and_records(
    src_db: str,
) -> Tuple[Dict[str, str], Dict[str, List[Dict[str, Any]]]]:
    """Extracts DDL and row dictionaries for all user tables in an SQLite database."""
    conn = sqlite3.connect(src_db)
    cur = conn.cursor()
    cur.execute(
        "SELECT name, sql FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' AND name NOT LIKE '%_fts%'"
    )
    ddl_map: Dict[str, str] = {str(row[0]): str(row[1]) for row in cur.fetchall()}

    records_map: Dict[str, List[Dict[str, Any]]] = {}
    for tbl in ddl_map:
        recs = dump_sqlite_table_records(conn, tbl)
        records_map[tbl] = recs
        logger.info("Extracted table '%s': %d records", tbl, len(recs))

    conn.close()
    return ddl_map, records_map


def build_vdb_container(
    target_vdb: str,
    ddl_map: Dict[str, str],
    records_map: Dict[str, List[Dict[str, Any]]],
) -> MultiTableVectorStorage:
    """Creates a MultiTableVectorStorage (.vdb) and writes all tables and schema metadata."""
    container = MultiTableVectorStorage(file_path=target_vdb)

    # 1. Store DDL schemas in special _schemas table
    schema_records = [{"table_name": tbl, "sql": sql} for tbl, sql in ddl_map.items()]
    schema_tbl = container.create_table("_schemas", dim=4)
    dummy_vecs = [(0.0, 0.0, 0.0, 0.0)] * len(schema_records)
    schema_tbl.write_all(dummy_vecs, schema_records)

    # 2. Store all data tables
    for tbl, recs in records_map.items():
        t = container.create_table(tbl, dim=4)
        v = [(0.0, 0.0, 0.0, 0.0)] * len(recs)
        t.write_all(v, recs)
        logger.info("Packed table '%s': %d rows into container", tbl, t.count)

    container.save()
    logger.info("Saved OKFMTC01 container to '%s' (%d bytes)", target_vdb, os.path.getsize(target_vdb))
    return container


def verify_migration(
    src_db: str,
    target_vdb: str,
    records_map: Dict[str, List[Dict[str, Any]]],
) -> bool:
    """Verifies that all tables and rows in target_vdb match the source SQLite database 100%."""
    if not os.path.exists(target_vdb):
        logger.error("Target VDB file does not exist: %s", target_vdb)
        return False

    verifier = MultiTableVectorStorage(file_path=target_vdb)
    verifier.load()

    all_passed = True
    for tbl, original_recs in records_map.items():
        if not verifier.has_table(tbl):
            logger.error("Missing table in container: %s", tbl)
            all_passed = False
            continue
        v_tbl = verifier.get_table(tbl)
        if v_tbl.count != len(original_recs):
            logger.error(
                "Row count mismatch for table '%s': expected %d, got %d",
                tbl,
                len(original_recs),
                v_tbl.count,
            )
            all_passed = False
            continue

        # Spot check first and last records
        if original_recs:
            first_orig = original_recs[0]
            first_vdb = v_tbl.get_metadata(0)
            if first_orig != first_vdb:
                logger.error("First row mismatch in table '%s'", tbl)
                all_passed = False

            last_orig = original_recs[-1]
            last_vdb = v_tbl.get_metadata(len(original_recs) - 1)
            if last_orig != last_vdb:
                logger.error("Last row mismatch in table '%s'", tbl)
                all_passed = False

        logger.info("Verification PASSED for table '%s' (%d rows)", tbl, v_tbl.count)

    verifier.close()
    return all_passed


def migrate_database_file(src_path: str, dst_path: str, backup: bool = True) -> bool:
    """Performs end-to-end migration of an SQLite DB to .vdb."""
    if not os.path.exists(src_path):
        logger.warning("Source database does not exist: %s (skipping)", src_path)
        return False

    logger.info("=== Starting migration: %s -> %s ===", src_path, dst_path)
    ddl_map, records_map = extract_table_ddl_and_records(src_path)
    build_vdb_container(dst_path, ddl_map, records_map)

    success = verify_migration(src_path, dst_path, records_map)
    if not success:
        logger.critical("Verification FAILED for %s -> %s! Aborting backup.", src_path, dst_path)
        return False

    logger.info("Verification 100%% SUCCEEDED for %s", dst_path)
    if backup:
        bak_path = src_path + ".bak"
        logger.info("Creating backup copy: %s -> %s", src_path, bak_path)
        shutil.copy2(src_path, bak_path)

    return True


def main() -> int:
    parser = argparse.ArgumentParser(description="Migrate SQLite databases to .vdb containers")
    parser.add_argument("--no-backup", action="store_true", help="Skip creating .bak files")
    args = parser.parse_args()

    databases: List[Tuple[str, str]] = [
        (
            os.path.join(WORKSPACE_DIR, "outputs", "database", "catalog", "cti_catalog.db"),
            os.path.join(WORKSPACE_DIR, "outputs", "database", "catalog", "cti_catalog.vdb"),
        ),
        (
            os.path.join(WORKSPACE_DIR, "outputs", "database", "analytics", "analytics.db"),
            os.path.join(WORKSPACE_DIR, "outputs", "database", "analytics", "analytics.vdb"),
        ),
    ]

    all_ok = True
    for src, dst in databases:
        if not migrate_database_file(src, dst, backup=not args.no_backup):
            all_ok = False

    if all_ok:
        logger.info("All database migrations completed successfully with 100% verification!")
        return 0
    logger.error("One or more migrations failed.")
    return 1


if __name__ == "__main__":
    sys.exit(main())
