#!/usr/bin/env python3
"""
SWMR (Single-Writer Multi-Reader) Transaction Engine for CoW B-Tree Storage.
Provides lock-free snapshot readers and serialized ACID shadow-paged writer transactions.
"""

import json
import threading
from typing import Any, List, Optional, Tuple

from .cow_btree import CoWBTree
from .meta_page import MetaPage
from .mmap_file import MMapFile


class CoWReadTx:
    """
    Lock-free read-only transaction referencing an immutable snapshot MetaPage.
    """

    def __init__(
        self,
        meta: MetaPage,
        btree: CoWBTree,
    ) -> None:
        self.meta = meta
        self.btree = btree

    @property
    def tx_id(self) -> int:
        return self.meta.tx_id

    def get(self, key: str) -> Optional[Any]:
        """Looks up key in snapshot B-Tree."""
        raw = self.btree.get(self.meta.root_page_id, key)
        if raw is None:
            return None
        try:
            return json.loads(raw.decode("utf-8"))
        except Exception:
            try:
                return raw.decode("utf-8")
            except Exception:
                return raw

    def scan(
        self,
        start_key: Optional[str] = None,
        end_key: Optional[str] = None,
    ) -> List[Tuple[str, Any]]:
        """Scans range [start_key, end_key) in snapshot B-Tree."""
        results: List[Tuple[str, Any]] = []
        for k, raw in self.btree.scan(self.meta.root_page_id, start_key, end_key):
            try:
                decoded = json.loads(raw.decode("utf-8"))
                results.append((k, decoded))
            except Exception:
                try:
                    results.append((k, raw.decode("utf-8")))
                except Exception:
                    results.append((k, raw))
        return results


class CoWWriteTx:
    """
    Serialized write transaction updating B-Tree via Copy-on-Write shadow paging.
    """

    def __init__(
        self,
        engine: "CoWEngine",
        base_meta: MetaPage,
    ) -> None:
        self.engine = engine
        self.base_meta = base_meta
        self.current_root_pid = base_meta.root_page_id
        self.retired_pages: List[int] = []
        self.is_active = True

    def put(self, key: str, value: Any) -> None:
        """Inserts or updates a key-value record in shadow B-Tree."""
        if not self.is_active:
            raise RuntimeError("Transaction is not active")

        if isinstance(value, (bytes, bytearray)):
            val_bytes = bytes(value)
        elif isinstance(value, str):
            val_bytes = value.encode("utf-8")
        else:
            val_bytes = json.dumps(value, ensure_ascii=False).encode("utf-8")

        new_root, retired = self.engine.btree.insert(
            self.current_root_pid, key, val_bytes
        )
        self.current_root_pid = new_root
        self.retired_pages.extend(retired)

    def delete(self, key: str) -> None:
        """Deletes a key from shadow B-Tree."""
        if not self.is_active:
            raise RuntimeError("Transaction is not active")

        new_root, retired = self.engine.btree.delete(self.current_root_pid, key)
        self.current_root_pid = new_root
        self.retired_pages.extend(retired)

    def commit(self) -> MetaPage:
        """Commits transaction by updating alternate Meta Page atomically."""
        if not self.is_active:
            raise RuntimeError("Transaction is not active")

        next_tx_id = self.base_meta.tx_id + 1
        new_meta, _ = MetaPage.commit_next(
            mmap_file=self.engine.mmap_file,
            next_tx_id=next_tx_id,
            root_page_id=self.current_root_pid,
            page_count=self.engine.mmap_file.page_count,
            free_list_head=0,
        )
        self.engine._latest_meta = new_meta
        self.is_active = False
        self.engine._write_lock.release()
        return new_meta

    def rollback(self) -> None:
        """Aborts transaction without modifying Meta Page."""
        if self.is_active:
            self.is_active = False
            self.engine._write_lock.release()


class CoWEngine:
    """
    Copy-on-Write (CoW) B-Tree Engine with SWMR concurrency control.
    """

    def __init__(self, db_path: str = "data/cow/database.vdb") -> None:
        self.db_path = db_path
        self.mmap_file = MMapFile(file_path=db_path)
        self.btree = CoWBTree(mmap_file=self.mmap_file)
        self._write_lock = threading.RLock()
        self._latest_meta = MetaPage.load_latest(self.mmap_file)

    @property
    def latest_meta(self) -> MetaPage:
        return self._latest_meta

    def begin_read(self) -> CoWReadTx:
        """Starts a lock-free snapshot read-only transaction."""
        return CoWReadTx(meta=self._latest_meta, btree=self.btree)

    def begin_write(self) -> CoWWriteTx:
        """Starts a serialized write transaction."""
        self._write_lock.acquire()
        return CoWWriteTx(engine=self, base_meta=self._latest_meta)

    def get(self, key: str) -> Optional[Any]:
        """Convenience method: performs a single point lookup."""
        tx = self.begin_read()
        return tx.get(key)

    def put(self, key: str, value: Any) -> MetaPage:
        """Convenience method: performs an atomic single put transaction."""
        tx = self.begin_write()
        try:
            tx.put(key, value)
            return tx.commit()
        except Exception:
            tx.rollback()
            raise

    def delete(self, key: str) -> MetaPage:
        """Convenience method: performs an atomic single delete transaction."""
        tx = self.begin_write()
        try:
            tx.delete(key)
            return tx.commit()
        except Exception:
            tx.rollback()
            raise

    def close(self) -> None:
        """Closes the CoW database engine."""
        self.mmap_file.close()
