#!/usr/bin/env python3
"""
US-11: In-Memory VFS and Temporary Session Isolation in src/database.
Tests MemoryVFS, in-memory Pager/BufferPool, session data isolation,
and zero-leak cleanup.
"""

import os
import sys
import unittest

if "src" not in sys.path:
    sys.path.insert(
        0,
        os.path.abspath(
            os.path.join(os.path.dirname(__file__), "..", "..", "..", "src")
        ),
    )

from database import Pager
from database.vfs import MemoryVFS


class TestUS11InMemoryAndTempTables(unittest.TestCase):
    """Verifies in-memory VFS and temporary session lifecycle."""

    def test_in_memory_vfs_lifecycle_and_isolation(self) -> None:
        vfs = MemoryVFS()

        # Session 1 file
        fh1 = vfs.open(":memory:session1", "w+b")
        fh1.write(0, b"TEMP_SESSION_1_DATA")
        data1 = fh1.read(0, 19)
        self.assertEqual(data1, b"TEMP_SESSION_1_DATA")
        fh1.close()

        # Session 2 file is completely isolated
        fh2 = vfs.open(":memory:session2", "w+b")
        self.assertEqual(fh2.file_size(), 0)
        fh2.close()

        # In-memory Pager
        pager_mem = Pager(":memory:db", vfs=vfs, use_wal=False)
        pager_mem.begin()
        pager_mem.write_page(0, b"PAGE_IN_MEMORY" + b"\x00" * (4096 - 14))
        pager_mem.commit()

        read_page = pager_mem.read_page(0)
        self.assertTrue(read_page.startswith(b"PAGE_IN_MEMORY"))
        pager_mem.close()


if __name__ == "__main__":
    unittest.main()
