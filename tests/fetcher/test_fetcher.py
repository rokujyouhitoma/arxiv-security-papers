"""
Unit tests for arxiv_okf_fetcher core module.
"""

import os
import sys

from fetcher import clean_text, load_config, translate_title_ja


def test_clean_text():
    raw_text = "  Hello \n\n  World \t  "
    assert clean_text(raw_text) == "Hello World"
    assert clean_text("") == ""


def test_load_config():
    config = load_config()
    assert isinstance(config, dict)
    assert "arxiv" in config
    assert config["arxiv"]["query"] == "cat:cs.CR"


def test_translate_title_ja():
    title = (
        "TeleGapper: On the (un)reliability of Privacy Policies in Telegram Mini apps"
    )
    translated = translate_title_ja(title)
    assert "Telegram" in translated
