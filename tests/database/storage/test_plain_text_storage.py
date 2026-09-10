#!/usr/bin/env python3
"""
Unit tests for FileBackedPlainTextStorage (Issue #229 / DSN-05 Section 21.6).
Tests YAML frontmatter extraction, lazy loading, LRU caching, and security boundaries.
Pure Python, zero external dependencies.
"""

import os
import tempfile

import pytest

from database.storage.plain_text_storage import (
    FileBackedPlainTextStorage,
    PlainTextSecurityError,
)


def test_plain_text_storage_indexing_and_lazy_loading() -> None:
    with tempfile.TemporaryDirectory() as tmpdir:
        # Create a sample OKF Markdown paper
        paper_file = os.path.join(tmpdir, "2403_001.md")
        content = (
            "---\n"
            "type: 'security-paper'\n"
            "clean_id: '2403_001'\n"
            "arxiv_id: '2403.00001v1'\n"
            "title: 'Zero-Trust Protocol'\n"
            "description: 'A study on zero-trust architectures.'\n"
            "tags:\n"
            "  - zero-trust\n"
            "  - cryptography\n"
            "---\n"
            "\n"
            "# 1. Introduction\n"
            "This paper explores zero-trust principles in cloud environments.\n"
        )
        with open(paper_file, "w", encoding="utf-8") as f:
            f.write(content)

        # Mount directory
        storage = FileBackedPlainTextStorage(root_dir=tmpdir, workspace_dir=tmpdir)
        assert storage.count == 1

        # Check metadata list
        metas = storage.metadata
        assert len(metas) == 1
        record = metas[0]

        # Verify indexed frontmatter fields
        assert record["clean_id"] == "2403_001"
        assert record["arxiv_id"] == "2403.00001v1"
        assert record["title"] == "Zero-Trust Protocol"
        assert record["description"] == "A study on zero-trust architectures."
        assert "zero-trust" in record["tags"]

        # Verify lazy loaded body column
        assert "# 1. Introduction" in record["body_markdown"]
        assert "zero-trust principles" in record["body_markdown"]
        # Ensure YAML delimiters are stripped from body_markdown
        assert "type: 'security-paper'" not in record["body_markdown"]


def test_plain_text_storage_get_by_pk() -> None:
    with tempfile.TemporaryDirectory() as tmpdir:
        p1 = os.path.join(tmpdir, "paper_alpha.md")
        with open(p1, "w", encoding="utf-8") as f:
            f.write("---\ntitle: 'Alpha'\n---\nAlpha Body")

        storage = FileBackedPlainTextStorage(root_dir=tmpdir, workspace_dir=tmpdir)
        rec = storage.get_by_pk("paper_alpha")
        assert rec is not None
        assert rec["title"] == "Alpha"
        assert rec["body_markdown"] == "Alpha Body"

        missing = storage.get_by_pk("non_existent")
        assert missing is None


def test_plain_text_storage_lru_caching() -> None:
    with tempfile.TemporaryDirectory() as tmpdir:
        p1 = os.path.join(tmpdir, "cached_paper.md")
        with open(p1, "w", encoding="utf-8") as f:
            f.write("Raw text content without frontmatter")

        storage = FileBackedPlainTextStorage(root_dir=tmpdir, workspace_dir=tmpdir)
        # First read populates LRU cache
        b1 = storage.read_heavy_column("cached_paper", "raw_text")
        assert b1 == "Raw text content without frontmatter"
        assert "cached_paper:raw_text" in storage._content_cache

        # Modify file on disk to prove second read is served from LRU cache
        with open(p1, "w", encoding="utf-8") as f:
            f.write("Modified disk content")

        b2 = storage.read_heavy_column("cached_paper", "raw_text")
        assert b2 == "Raw text content without frontmatter"


def test_plain_text_storage_boundary_security() -> None:
    with tempfile.TemporaryDirectory() as tmpdir:
        workspace = os.path.join(tmpdir, "ws")
        outside = os.path.join(tmpdir, "etc")
        os.makedirs(workspace, exist_ok=True)
        os.makedirs(outside, exist_ok=True)

        with pytest.raises(PlainTextSecurityError, match="violates workspace boundary"):
            FileBackedPlainTextStorage(root_dir=outside, workspace_dir=workspace)
