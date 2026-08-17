"""
Integration and regression tests for arxiv_okf_fetcher core pipeline.
"""

import os
import sys

from fetcher import (
    build_okf_from_raw,
    build_summary_table_md,
    classify_domain,
    clean_text,
    determine_security_tags,
    extract_mitre_and_stride,
    generate_annual_summary,
    generate_japanese_executive_summary,
    generate_mermaid_mindmap,
    generate_monthly_summary,
    generate_per_run_summary,
    generate_quarterly_summary,
    get_paper_pub_date_str,
    load_config,
    parse_arxiv_entry,
    run_pipeline,
    save_raw_paper_data,
    translate_title_ja,
    update_index_and_log,
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
