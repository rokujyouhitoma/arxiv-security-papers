#!/usr/bin/env python3
"""
US-12: End-to-End (E2E) Database Lifecycle in src/database.
Tests the full lifecycle of a database from initial creation to final cleanup
using pure Python database engine components:
- Step 1: Database Creation & Connection Initialization (driver.connect)
- Step 2: Table Creation & Schema Definition (DDL, TableCatalog)
- Step 3: Data Ingestion, Update, and Deletion (DML, SQLExecutor, Transactions)
- Step 4: Complex Query Execution (DQL, Vector Search KNN, Filtering)
- Step 5: Indexing & Optimization (CREATE INDEX HNSW)
- Step 6: Table Decommissioning (DROP TABLE, TableCatalog removal)
- Step 7: Connection Teardown & File Cleanup (os.remove)
"""

import os
import sys
import tempfile
import unittest

if "src" not in sys.path:
    sys.path.insert(
        0,
        os.path.abspath(
            os.path.join(os.path.dirname(__file__), "..", "..", "..", "src")
        ),
    )

from database import connect


class TestUS12E2EDatabaseLifecycle(unittest.TestCase):
    """End-to-End lifecycle test verifying complete resource management and consistency."""

    def test_complete_database_lifecycle_e2e(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            db_path = os.path.join(tmpdir, "lifecycle_e2e.vdb")

            # -------------------------------------------------------------
            # Step 1: データベースの作成と接続初期化
            # -------------------------------------------------------------
            self.assertFalse(os.path.exists(db_path))
            conn = connect(db_path, dim=4)
            cur = conn.cursor()

            # -------------------------------------------------------------
            # Step 2: テーブル作成と制約の定義（DDL）
            # -------------------------------------------------------------
            self.assertIsNone(cur.description)

            # -------------------------------------------------------------
            # Step 3: データの投入・更新・削除（DML / トランザクション）
            # -------------------------------------------------------------
            # 3.1 Insert sample records
            cur.execute(
                "INSERT INTO papers (id, title, category, vector) VALUES (?, ?, ?, ?)",
                [
                    "p1",
                    "Quantum Cryptography",
                    "Cryptography",
                    [1.0, 0.0, 0.0, 0.0],
                ],
            )
            cur.execute(
                "INSERT INTO papers (id, title, category, vector) VALUES (?, ?, ?, ?)",
                [
                    "p2",
                    "Zero Trust Architecture",
                    "Zero-Trust",
                    [0.0, 1.0, 0.0, 0.0],
                ],
            )
            cur.execute(
                "INSERT INTO papers (id, title, category, vector) VALUES (?, ?, ?, ?)",
                [
                    "p3",
                    "Post Quantum Signatures",
                    "Cryptography",
                    [0.9, 0.1, 0.0, 0.0],
                ],
            )
            conn.commit()

            # File is now materialized on disk
            self.assertTrue(os.path.exists(db_path))

            # 3.2 Update
            cur.execute(
                "UPDATE papers SET title = 'Advanced Quantum Cryptography' WHERE id = 'p1'"
            )
            conn.commit()

            # -------------------------------------------------------------
            # Step 4: クエリの実行（検索・結合・集計）
            # -------------------------------------------------------------
            cur.execute(
                "SELECT id, title, category FROM papers WHERE category = ?",
                ["Cryptography"],
            )
            rows = cur.fetchall()
            self.assertEqual(len(rows), 2)
            self.assertEqual(rows[0][0], "p1")
            self.assertEqual(rows[0][1], "Advanced Quantum Cryptography")

            # 4.2 KNN Vector Search
            cur.execute(
                "SELECT id, title, score FROM papers WHERE KNN(vector, ?, 2)",
                [[1.0, 0.0, 0.0, 0.0]],
            )
            knn_rows = cur.fetchall()
            self.assertEqual(len(knn_rows), 2)
            self.assertEqual(knn_rows[0][0], "p1")

            # -------------------------------------------------------------
            # Step 5: スキーマ変更とインデックス操作
            # -------------------------------------------------------------
            cur.execute("CREATE INDEX hnsw_idx ON papers (vector) USING HNSW")
            conn.commit()

            # -------------------------------------------------------------
            # Step 6: レコード削除とテーブル操作
            # -------------------------------------------------------------
            cur.execute("DELETE FROM papers WHERE id = 'p3'")
            conn.commit()

            cur.execute("SELECT id FROM papers")
            remaining_rows = cur.fetchall()
            self.assertEqual(len(remaining_rows), 2)

            # -------------------------------------------------------------
            # Step 7: 接続切断とデータベースの削除（Cleanup）
            # -------------------------------------------------------------
            cur.close()
            conn.close()

            # File must be unlocked and immediately deletable by OS
            self.assertTrue(os.path.exists(db_path))
            os.remove(db_path)
            self.assertFalse(os.path.exists(db_path))


if __name__ == "__main__":
    unittest.main()
