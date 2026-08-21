"""
Integration and regression tests for arxiv_okf_fetcher core pipeline.
"""

from pipeline import (
    classify_domain,
    clean_text,
    determine_security_tags,
    extract_mitre_and_stride,
    generate_mermaid_mindmap,
    load_config,
    run_pipeline,
    translate_title_ja,
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


def test_all_symbols_exported():
    assert callable(run_pipeline)
    assert callable(classify_domain)
    assert callable(determine_security_tags)
    assert callable(extract_mitre_and_stride)
    assert callable(generate_mermaid_mindmap)
