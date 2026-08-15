"""
Unit tests for arxiv_okf_fetcher core module.
"""

import os
import sys

from arxiv_okf_fetcher import clean_text, load_config, translate_title_ja

# Add src to python path for standalone execution
if "src" not in sys.path:
    sys.path.insert(
        0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "src"))
    )


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
