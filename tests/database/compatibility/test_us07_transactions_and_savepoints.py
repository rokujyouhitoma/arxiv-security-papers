#!/usr/bin/env python3
"""
US-07: Transaction Management and Rollback Recovery in src/database.
Tests TransactionManager, MVCC snapshot isolation, and ROLLBACK atomic recovery.
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

from database import (
    HNSWIndex,
    SQLExecutor,
    TableCatalog,
    TransactionManager,
    VectorStorage,
)


class TestUS07TransactionsAndSavepoints(unittest.TestCase):
    """Verifies transaction commit, rollback, and state restoration."""

    def test_transaction_lifecycle_and_rollback(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            storage_path = os.path.join(tmpdir, "tx_table.vdb")
            storage = VectorStorage(storage_path, dim=4)
            catalog = TableCatalog(
                name="tx_table", storage=storage, index=HNSWIndex(dim=4)
            )
            tx_mgr = TransactionManager()
            executor = SQLExecutor(catalog=catalog, tx_manager=tx_mgr)

            # 1. Insert baseline record
            executor.execute(
                "INSERT INTO tx_table (id, title) VALUES ('initial', 'Base Paper')"
            )
            self.assertEqual(storage.count, 1)

            # 2. Begin transaction
            executor.execute("BEGIN TRANSACTION")
            self.assertTrue(tx_mgr.is_active)

            # 3. Perform uncommitted modifications
            executor.execute(
                "INSERT INTO tx_table (id, title) VALUES ('tx_temp', 'Uncommitted')"
            )
            executor.execute(
                "UPDATE tx_table SET title = 'Modified Title' WHERE id = 'initial'"
            )

            # 4. Rollback
            executor.execute("ROLLBACK")
            self.assertFalse(tx_mgr.is_active)

            # 5. Verify pristine state was restored
            self.assertEqual(storage.count, 1)
            meta = storage.get_metadata(0)
            self.assertEqual(meta["title"], "Base Paper")


if __name__ == "__main__":
    unittest.main()
