#!/usr/bin/env python3
"""Backward-compatibility shim for database.storage.slotted_page."""

from .storage.slotted_page import (
    DataType,
    OverflowManager,
    PageCorruptionError,
    PageFullError,
    PageType,
    SlottedPage,
    SlottedPageError,
    TupleSerializer,
)

__all__ = [
    "DataType",
    "OverflowManager",
    "PageCorruptionError",
    "PageFullError",
    "PageType",
    "SlottedPage",
    "SlottedPageError",
    "TupleSerializer",
]
