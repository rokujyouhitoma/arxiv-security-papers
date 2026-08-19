#!/usr/bin/env python3
"""
ARIES Crash Recovery Manager Subsystem.
Implements the 3-phase ARIES (Algorithm for Recovery and Isolation Exploiting Semantics)
recovery protocol: Analysis, Redo (Repeating History), and Undo with CLR logging.
"""

import struct
import threading
from typing import TYPE_CHECKING, Dict, List, Optional, Set, Tuple, Union

from .vfs import VFS, VFSFile, get_vfs
from .wal import DEFAULT_PAGE_SIZE, LogRecord, LogRecordType, WALReader, WALWriter

if TYPE_CHECKING:
    from .pager import Pager


class ARIESRecoveryManager:
    """
    Coordinates crash recovery using the ARIES 3-phase protocol:
    1. Analysis Phase: Reconstructs Active Transaction Table (ATT) and Dirty Page Table (DPT).
    2. Redo Phase: Replays all logged changes from min(RecLSN) forward (Repeating History).
    3. Undo Phase: Rolls back all uncommitted (loser) transactions backward, writing CLRs.
    """

    def __init__(
        self,
        db_file_path: str,
        wal_file_path: str,
        vfs_name: Optional[str] = None,
        vfs: Optional[VFS] = None,
        page_size: int = DEFAULT_PAGE_SIZE,
    ) -> None:
        self.db_file_path = db_file_path
        self.wal_file_path = wal_file_path
        self.vfs_name = vfs_name
        self.vfs = vfs if vfs is not None else get_vfs(vfs_name)
        self.page_size = page_size
        self._lock = threading.RLock()

    def run_recovery(self, pager: Optional["Pager"] = None) -> Tuple[int, int]:
        """
        Executes complete ARIES 3-phase crash recovery on the database and WAL files.
        Returns (redo_count, undo_count).
        """
        with self._lock:
            if not self.vfs.exists(self.wal_file_path):
                return 0, 0

            wal_reader = WALReader(self.wal_file_path, vfs=self.vfs)
            all_records = wal_reader.read_all_records()
            if not all_records:
                return 0, 0

            att, dpt, chk_lsn = self._run_analysis_phase(all_records)
            redo_count = self._run_redo_phase(all_records, dpt, pager=pager)
            undo_count = self._run_undo_phase(all_records, att, pager=pager)
            return redo_count, undo_count

    def _find_checkpoint_info(
        self, all_records: List[LogRecord]
    ) -> Tuple[Dict[int, int], Dict[int, int], int]:
        """Extracts initial ATT and DPT from the last checkpoint record."""
        for record in reversed(all_records):
            if record.record_type == LogRecordType.CHECKPOINT_END:
                att = {int(k): v for k, v in record.extra_info.get("att", {}).items()}
                dpt = {int(k): v for k, v in record.extra_info.get("dpt", {}).items()}
                return att, dpt, record.lsn
        return {}, {}, 0

    def _run_analysis_phase(
        self, all_records: List[LogRecord]
    ) -> Tuple[Dict[int, int], Dict[int, int], int]:
        """
        Phase 1: Analysis Phase.
        Scans forward to reconstruct ATT, DPT, and checkpoint state.
        """
        att, dpt, chk_lsn = self._find_checkpoint_info(all_records)
        start_idx = 0
        if chk_lsn > 0:
            for idx, rec in enumerate(all_records):
                if rec.lsn == chk_lsn:
                    start_idx = idx + 1
                    break

        for record in all_records[start_idx:]:
            self._update_tables_for_record(record, att, dpt)

        return att, dpt, chk_lsn

    @staticmethod
    def _update_tables_for_record(
        record: LogRecord, att: Dict[int, int], dpt: Dict[int, int]
    ) -> None:
        """Updates Active Transaction Table and Dirty Page Table for a single record."""
        rec_type = record.record_type
        tx_id = record.tx_id

        if rec_type in (LogRecordType.BEGIN, LogRecordType.UPDATE, LogRecordType.CLR):
            att[tx_id] = record.lsn
            if (
                rec_type in (LogRecordType.UPDATE, LogRecordType.CLR)
                and record.page_id != 0xFFFFFFFF
                and record.page_id not in dpt
            ):
                dpt[record.page_id] = record.lsn
        elif rec_type in (LogRecordType.COMMIT, LogRecordType.ABORT):
            att.pop(tx_id, None)

    def _run_redo_phase(
        self,
        all_records: List[LogRecord],
        dpt: Dict[int, int],
        pager: Optional["Pager"] = None,
    ) -> int:
        """
        Phase 2: Redo Phase (Repeating History).
        Replays updates from min(RecLSN) forward to restore state before crash.
        """
        if not dpt:
            return 0

        min_rec_lsn = min(dpt.values())
        redo_count = 0

        db_file: Optional[VFSFile] = None
        if pager is None and self.vfs.exists(self.db_file_path):
            db_file = self.vfs.open(self.db_file_path, mode="r+b")

        try:
            for record in all_records:
                if self._can_redo_record(record, min_rec_lsn, dpt):
                    if self._apply_redo(record, pager, db_file):
                        redo_count += 1
            if db_file:
                db_file.sync()
        finally:
            if db_file:
                db_file.close()

        return redo_count

    @staticmethod
    def _can_redo_record(
        record: LogRecord, min_rec_lsn: int, dpt: Dict[int, int]
    ) -> bool:
        """Checks whether a record is a valid candidate for Redo."""
        if record.lsn < min_rec_lsn:
            return False
        if record.record_type not in (
            LogRecordType.UPDATE,
            LogRecordType.CLR,
        ):
            return False
        page_id = record.page_id
        if page_id == 0xFFFFFFFF or page_id not in dpt:
            return False
        return record.lsn >= dpt[page_id]

    def _apply_redo(
        self,
        record: LogRecord,
        pager: Optional["Pager"],
        db_file: Optional[VFSFile],
    ) -> bool:
        """Reads page and applies redo payload if page_lsn < log.lsn."""
        page_id = record.page_id
        page_data = self._read_page_raw(page_id, pager, db_file)
        page_lsn = self._extract_page_lsn(page_data)

        if page_lsn >= record.lsn:
            return False

        new_page_data = bytearray(page_data)
        offset = record.offset
        redo = record.redo_data
        new_page_data[offset : offset + len(redo)] = redo
        self._set_page_lsn(new_page_data, record.lsn)
        self._write_page_raw(page_id, new_page_data, pager, db_file)
        return True

    def _run_undo_phase(
        self,
        all_records: List[LogRecord],
        att: Dict[int, int],
        pager: Optional["Pager"] = None,
    ) -> int:
        """
        Phase 3: Undo Phase.
        Rolls back all uncommitted active transactions (losers) backward.
        """
        if not att:
            return 0

        wal_writer = WALWriter(
            self.wal_file_path,
            vfs=self.vfs,
            page_size=self.page_size,
        )
        record_map: Dict[int, LogRecord] = {r.lsn: r for r in all_records}
        to_undo: Set[int] = set(att.values())
        undo_count = 0

        db_file: Optional[VFSFile] = None
        if pager is None and self.vfs.exists(self.db_file_path):
            db_file = self.vfs.open(self.db_file_path, mode="r+b")

        try:
            while to_undo:
                max_lsn = max(to_undo)
                to_undo.remove(max_lsn)
                if max_lsn not in record_map:
                    continue

                rec = record_map[max_lsn]
                undone = self._process_undo_step(
                    rec, wal_writer, pager, db_file, record_map, to_undo
                )
                if undone:
                    undo_count += 1

            wal_writer.flush()
            if db_file:
                db_file.sync()
        finally:
            wal_writer.close()
            if db_file:
                db_file.close()

        return undo_count

    def _process_undo_step(
        self,
        record: LogRecord,
        wal_writer: WALWriter,
        pager: Optional["Pager"],
        db_file: Optional[VFSFile],
        record_map: Dict[int, LogRecord],
        to_undo: Set[int],
    ) -> bool:
        """Processes a single undo step based on log record type."""
        if record.record_type == LogRecordType.UPDATE:
            return self._undo_update(
                record, wal_writer, pager, db_file, record_map, to_undo
            )
        elif record.record_type == LogRecordType.CLR:
            if record.undo_next_lsn > 0:
                to_undo.add(record.undo_next_lsn)
            else:
                self._record_abort(record.tx_id, record.lsn, wal_writer, record_map)
            return False
        elif record.record_type == LogRecordType.BEGIN:
            self._record_abort(record.tx_id, record.lsn, wal_writer, record_map)
            return False
        return False

    def _undo_update(
        self,
        record: LogRecord,
        wal_writer: WALWriter,
        pager: Optional["Pager"],
        db_file: Optional[VFSFile],
        record_map: Dict[int, LogRecord],
        to_undo: Set[int],
    ) -> bool:
        """Undoes an UPDATE record, applies undo_data, and writes CLR."""
        page_id = record.page_id
        if page_id != 0xFFFFFFFF and record.undo_data:
            page_data = self._read_page_raw(page_id, pager, db_file)
            new_page_data = bytearray(page_data)
            offset = record.offset
            undo = record.undo_data
            new_page_data[offset : offset + len(undo)] = undo

            clr_rec = wal_writer.append_record(
                tx_id=record.tx_id,
                record_type=LogRecordType.CLR,
                prev_lsn=wal_writer.next_lsn - 1,
                page_id=page_id,
                offset=offset,
                redo_data=undo,
                undo_next_lsn=record.prev_lsn,
            )
            self._set_page_lsn(new_page_data, clr_rec.lsn)
            self._write_page_raw(page_id, new_page_data, pager, db_file)
            record_map[clr_rec.lsn] = clr_rec

        if record.prev_lsn > 0:
            to_undo.add(record.prev_lsn)
        else:
            self._record_abort(record.tx_id, record.lsn, wal_writer, record_map)
        return True

    @staticmethod
    def _record_abort(
        tx_id: int,
        prev_lsn: int,
        wal_writer: WALWriter,
        record_map: Dict[int, LogRecord],
    ) -> None:
        """Appends ABORT record to mark transaction rollback completion."""
        abort_rec = wal_writer.append_record(
            tx_id=tx_id,
            record_type=LogRecordType.ABORT,
            prev_lsn=prev_lsn,
        )
        record_map[abort_rec.lsn] = abort_rec

    def _read_page_raw(
        self,
        page_id: int,
        pager: Optional["Pager"],
        db_file: Optional[VFSFile],
    ) -> bytearray:
        if pager is not None:
            return pager.read_page(page_id)
        if db_file is not None:
            offset = page_id * self.page_size
            data = bytearray(db_file.read(offset, self.page_size))
            if len(data) < self.page_size:
                data.extend(b"\x00" * (self.page_size - len(data)))
            return data
        return bytearray(self.page_size)

    def _write_page_raw(
        self,
        page_id: int,
        data: Union[bytes, bytearray],
        pager: Optional["Pager"],
        db_file: Optional[VFSFile],
    ) -> None:
        if pager is not None:
            pager.write_page(page_id, bytes(data))
        elif db_file is not None:
            offset = page_id * self.page_size
            db_file.write(offset, bytes(data))

    @staticmethod
    def _extract_page_lsn(page_data: Union[bytes, bytearray]) -> int:
        """Extracts 8-byte LSN from SlottedPage header if valid."""
        if len(page_data) >= 28:
            try:
                _, lsn, _, _, _, _, _ = struct.unpack_from("<IQHHHHI", page_data, 0)
                return int(lsn)
            except Exception:
                return 0
        return 0

    @staticmethod
    def _set_page_lsn(page_data: bytearray, lsn: int) -> None:
        """Writes 8-byte LSN into SlottedPage header if formatted as SlottedPage."""
        if len(page_data) >= 28:
            try:
                _, _, slot_count, _, free_upper, _, _ = struct.unpack_from(
                    "<IQHHHHI", page_data, 0
                )
                if free_upper > 0 or slot_count > 0:
                    struct.pack_into("<Q", page_data, 4, lsn)
            except Exception:
                pass
