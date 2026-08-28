#!/usr/bin/env python3
"""Backward-compatibility shim for database.storage.pager."""

from .storage.pager import PAGE_SIZE, Page, PageCache, Pager

__all__ = ["PAGE_SIZE", "Page", "PageCache", "Pager"]
