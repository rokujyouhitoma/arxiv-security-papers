#!/usr/bin/env python3
"""
PAX Table Storage Abstraction.
Buffers rows, packages them into compressed PAX 4KB pages, and exposes the OLAP PAXScanner.
"""

from typing import Any, List, Optional, Tuple

from .pax_page import PAXPage
from .scanner import PAXScanner

DEFAULT_MAX_ROWS_PER_PAGE: int = 64


class PAXTable:
    """
    In-memory and persistent PAX Columnar Table representation.
    """

    def __init__(
        self,
        table_name: str,
        schema: List[Tuple[str, str]],
        max_rows_per_page: int = DEFAULT_MAX_ROWS_PER_PAGE,
    ) -> None:
        self.table_name = table_name
        self.schema = schema
        self.max_rows_per_page = max_rows_per_page
        self._buffered_rows: List[List[Any]] = []
        self._pages: List[bytes] = []

    def __len__(self) -> int:
        scanner = self.get_scanner()
        return scanner.count()

    def insert(self, row: List[Any]) -> None:
        """Appends a row to the table."""
        self._buffered_rows.append(row)
        if len(self._buffered_rows) >= self.max_rows_per_page:
            self.flush()

    def insert_bulk(self, rows: List[List[Any]]) -> None:
        """Inserts multiple rows."""
        for r in rows:
            self.insert(r)

    def flush(self) -> Optional[bytes]:
        """Flushes buffered rows into a new PAX 4KB page."""
        if not self._buffered_rows:
            return None

        page_bytes = PAXPage.create_page(self.schema, self._buffered_rows)
        self._pages.append(page_bytes)
        self._buffered_rows.clear()
        return page_bytes

    def get_pages(self) -> List[bytes]:
        """Returns all completed PAX pages plus current active buffer flushed."""
        if self._buffered_rows:
            self.flush()
        return list(self._pages)

    def get_scanner(self) -> PAXScanner:
        """Returns an OLAP aggregation scanner over all pages."""
        if self._buffered_rows:
            self.flush()
        return PAXScanner(pages=self._pages, schema=self.schema)

    def scan_all_rows(self) -> List[List[Any]]:
        """Reconstructs all rows across all PAX pages."""
        if self._buffered_rows:
            self.flush()

        results: List[List[Any]] = []
        for page in self._pages:
            view = memoryview(page)
            rows = PAXPage.read_rows(view, self.schema)
            results.extend(rows)
        return results
