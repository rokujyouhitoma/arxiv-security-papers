"""Unit and boundary tests for Pure Packrat PEG YAML Frontmatter parsing."""

import pytest

from pipeline.transformer.yaml_parser import (
    clear_frontmatter_cache,
    parse_okf_frontmatter,
)


@pytest.fixture(autouse=True)
def _clear_cache() -> None:
    clear_frontmatter_cache()


def test_parse_okf_frontmatter_basic() -> None:
    content = """---
type: "security-paper"
title: "Zero-Trust Architecture"
title_ja: "ゼロトラストアーキテクチャ"
published_date: "2024-03-01"
score: 42
is_verified: true
tags:
  - "network-security"
  - "zero-trust"
---
# Content Header
Body text here.
"""
    meta = parse_okf_frontmatter(content)
    actual_scalars = (
        meta["type"],
        meta["title"],
        meta["title_ja"],
        meta["published_date"],
    )
    assert actual_scalars == (
        "security-paper",
        "Zero-Trust Architecture",
        "ゼロトラストアーキテクチャ",
        "2024-03-01",
    )
    assert (meta["score"], meta["is_verified"], meta["tags"]) == (
        42,
        True,
        ["network-security", "zero-trust"],
    )


def test_parse_okf_frontmatter_provenance() -> None:
    content = """---
title: "CTI Knowledge Graph Pipeline"
provenance:
  origin: "arxiv.org"
  metadata_path: "outputs/raw_data/2024-01-01/meta.json"
  authors:
    - "Alice Smith"
    - "Bob Jones"
trust:
  level: "attested"
  signer: "arxiv-pipeline-v2"
---
"""
    meta = parse_okf_frontmatter(content)
    prov = meta["provenance"]
    assert (prov["origin"], prov["metadata_path"], prov["authors"]) == (
        "arxiv.org",
        "outputs/raw_data/2024-01-01/meta.json",
        ["Alice Smith", "Bob Jones"],
    )
    assert (meta["trust"]["level"], meta["trust"]["signer"]) == (
        "attested",
        "arxiv-pipeline-v2",
    )


def test_parse_okf_frontmatter_cti_techniques() -> None:
    content = """---
cti_techniques:
  - id: "T1059"
    name: "Command and Scripting Interpreter"
  - id: "T1566"
    name: "Phishing"
---
"""
    meta = parse_okf_frontmatter(content)
    cti = meta["cti_techniques"]
    assert (len(cti), cti[0]["id"], cti[1]["id"]) == (2, "T1059", "T1566")


def test_parse_okf_frontmatter_inline_lists() -> None:
    content = """---
title: "Inline List Test"
tags: ["crypto", "side-channel", "hardware"]
scores: [10, 20, 30]
---
"""
    meta = parse_okf_frontmatter(content)
    assert (meta["tags"], meta["scores"]) == (
        ["crypto", "side-channel", "hardware"],
        [10, 20, 30],
    )


def test_parse_okf_frontmatter_resilience_and_fallbacks() -> None:
    assert (parse_okf_frontmatter("Just markdown"), parse_okf_frontmatter("")) == (
        {},
        {},
    )
    malformed = "---\nkey_without_value:\n  - incomplete\n---\n"
    assert isinstance(parse_okf_frontmatter(malformed), dict)


def test_parse_okf_frontmatter_redos_resilience() -> None:
    long_content = "---\ntitle: 'Benchmarking ReDoS'\n"
    long_content += "# Comment line\n" * 1000
    long_content += "tags:\n"
    for i in range(100):
        long_content += f"  - 'tag-{i}'\n"
    long_content += "---\nBody\n"

    meta = parse_okf_frontmatter(long_content)
    assert (meta["title"], len(meta["tags"])) == ("Benchmarking ReDoS", 100)
