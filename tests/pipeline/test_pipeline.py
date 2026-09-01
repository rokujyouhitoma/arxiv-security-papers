"""
Integration and regression tests for arxiv_okf_fetcher core pipeline.
"""

from pipeline import (
    classify_domain,
    clean_text,
    detect_workspace_dir,
    determine_security_tags,
    extract_mitre_and_stride,
    generate_mermaid_mindmap,
    load_config,
    run_pipeline,
    translate_title_ja,
)


def test_clean_text() -> None:
    raw_text = "  Hello \n\n  World \t  "
    assert clean_text(raw_text) == "Hello World"
    assert clean_text("") == ""


def test_load_config() -> None:
    config = load_config()
    assert isinstance(config, dict)
    assert "arxiv" in config
    assert config["arxiv"]["query"] == "cat:cs.CR"


def test_translate_title_ja() -> None:
    title = (
        "TeleGapper: On the (un)reliability of Privacy Policies in Telegram Mini apps"
    )
    translated = translate_title_ja(title)
    assert "Telegram" in translated


def test_all_symbols_exported() -> None:
    assert callable(run_pipeline)
    assert callable(classify_domain)
    assert callable(determine_security_tags)
    assert callable(extract_mitre_and_stride)
    assert callable(generate_mermaid_mindmap)
    assert callable(detect_workspace_dir)


def test_detect_workspace_dir_resolution() -> None:
    ws = detect_workspace_dir()
    import os

    assert os.path.isabs(ws)
    assert os.path.exists(os.path.join(ws, "config.json")) or os.path.exists(
        os.path.join(ws, "pyproject.toml")
    )
    assert not ws.endswith("src/pipeline")
    assert not ws.endswith("src")
