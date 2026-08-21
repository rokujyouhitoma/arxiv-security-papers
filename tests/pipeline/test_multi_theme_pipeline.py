#!/usr/bin/env python3
"""
Unit and Integration tests for ThemeManager and Multi-Theme Pipeline Orchestration.
"""

import json
import os
import tempfile
from typing import Any, List, Optional
from unittest.mock import MagicMock, patch

from pipeline.arxiv_okf_fetcher import run_theme_pipeline
from pipeline.transformer.theme import ThemeManager


def test_theme_manager_builtins_and_registration() -> None:
    mgr = ThemeManager()
    themes = mgr.list_theme_ids()

    assert "security" in themes
    assert "ai_safety" in themes
    assert "software_engineering" in themes

    sec_theme = mgr.get("security")
    assert sec_theme is not None
    assert sec_theme.theme_id == "security"
    assert sec_theme.get_output_root() == "outputs"

    ai_theme = mgr.get("ai_safety")
    assert ai_theme is not None
    assert "jailbreak" in ai_theme.keywords
    assert "themes/ai_safety" in ai_theme.get_output_root()


def test_theme_manager_custom_json_loading() -> None:
    custom_json = {
        "theme_id": "quantum_security",
        "name": "Post-Quantum Cryptography & Quantum Computing",
        "description": "Lattice cryptography, QKD, quantum algorithms.",
        "sources": [
            {
                "adapter": "arxiv",
                "query": "cat:quant-ph AND (cat:cs.CR OR cryptography)",
                "category": "quant-ph",
                "max_results": 25,
            }
        ],
        "keywords": ["lattice", "QKD", "Shor", "post-quantum"],
        "taxonomies": ["nist_pqc", "stride"],
    }

    with tempfile.NamedTemporaryFile("w", suffix=".json", delete=False) as f:
        json.dump(custom_json, f)
        temp_path = f.name

    try:
        mgr = ThemeManager()
        loaded = mgr.load_from_json_file(temp_path)
        assert loaded is not None
        assert loaded.theme_id == "quantum_security"
        assert loaded.name == "Post-Quantum Cryptography & Quantum Computing"
        assert mgr.get("quantum_security") is not None
    finally:
        if os.path.exists(temp_path):
            os.unlink(temp_path)


@patch("pipeline.arxiv_okf_fetcher._transform_and_save_okf")
@patch("pipeline.arxiv_okf_fetcher._generate_summaries_and_index")
def test_run_theme_pipeline_mock_execution(
    mock_gen_sum: MagicMock, mock_transform: MagicMock
) -> None:
    mock_transform.return_value = [{"clean_id": "2608.11111", "title": "Test Paper"}]

    with tempfile.TemporaryDirectory() as tmp_workspace:
        from pipeline.ingestion.adapters.base import BaseSourceAdapter, RawItem
        from pipeline.ingestion.adapters.registry import get_source_registry

        class MockArxivAdapter(BaseSourceAdapter):
            @property
            def source_name(self) -> str:
                return "arxiv"

            def fetch_items(self, *args: Any, **kwargs: Any) -> List[RawItem]:
                return [
                    RawItem(
                        item_id="2608.11111",
                        clean_id="2608.11111",
                        title="Test AI Security Paper",
                        abstract="Adversarial evaluation.",
                        authors=["Researcher A"],
                        published="2026-08-21T00:00:00Z",
                        updated="2026-08-21T00:00:00Z",
                        url="https://arxiv.org/abs/2608.11111",
                        source_type="arxiv",
                    )
                ]

            def fetch_content_and_text(
                self, item: RawItem, raw_dir: str
            ) -> tuple[Optional[str], Optional[str]]:
                return None, None

        reg = get_source_registry()
        reg.register(MockArxivAdapter())

        items = run_theme_pipeline(
            theme_id="ai_safety",
            workspace_dir=tmp_workspace,
            config={},
            max_results=5,
            force=True,
        )

        assert len(items) == 1
        assert mock_transform.called
        assert mock_gen_sum.called
