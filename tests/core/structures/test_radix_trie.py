"""Unit tests for RadixTrie (Patricia Tree) and CTI taxonomy prefix search."""

import pytest

from core.structures.radix_trie import MAX_RADIX_KEY_LENGTH, RadixTrie
from domain.security.taxonomy.cwe import search_cwe_by_prefix
from domain.security.taxonomy.mitre import search_techniques_by_prefix


def test_radix_trie_basic_crud() -> None:
    """Test basic insertion, retrieval, and presence checking."""
    trie: RadixTrie[str] = RadixTrie()
    assert len(trie) == 0
    assert not trie.contains("apple")

    trie.insert("apple", "fruit_apple")
    assert len(trie) == 1
    assert trie.contains("apple")
    assert "apple" in trie
    assert trie.get("apple") == "fruit_apple"
    assert trie.get("app") is None
    assert "app" not in trie

    # Update existing
    trie.insert("apple", "fresh_apple")
    assert len(trie) == 1
    assert trie.get("apple") == "fresh_apple"

    # Clear
    trie.clear()
    assert len(trie) == 0
    assert "apple" not in trie


def test_radix_trie_edge_splitting() -> None:
    """Test compressed edge splitting when shared prefixes diverge."""
    trie: RadixTrie[int] = RadixTrie()
    words = [
        ("romane", 1),
        ("romanus", 2),
        ("romulus", 3),
        ("rubens", 4),
        ("ruber", 5),
        ("rubicon", 6),
        ("rubicundus", 7),
    ]
    for w, val in words:
        trie.insert(w, val)

    assert len(trie) == 7
    for w, val in words:
        assert trie.get(w) == val

    # Verify prefix searches
    rom_results = trie.find_by_prefix("rom")
    assert len(rom_results) == 3
    rom_keys = [k for k, _ in rom_results]
    assert "romane" in rom_keys
    assert "romanus" in rom_keys
    assert "romulus" in rom_keys

    rub_results = trie.find_by_prefix("rubi")
    assert len(rub_results) == 2
    rub_keys = [k for k, _ in rub_results]
    assert "rubicon" in rub_keys
    assert "rubicundus" in rub_keys


def test_radix_trie_longest_prefix() -> None:
    """Test longest matching prefix for token extraction."""
    trie: RadixTrie[str] = RadixTrie()
    trie.insert("T1059", "Command Interpreter")
    trie.insert("T1059.001", "PowerShell")
    trie.insert("T1059.003", "Windows Command Shell")

    match1 = trie.longest_prefix("T1059.001 (Adversary execution)")
    assert match1 is not None
    assert match1[0] == "T1059.001"
    assert match1[1] == "PowerShell"

    match2 = trie.longest_prefix("T1059.999 (Unknown subtechnique)")
    assert match2 is not None
    assert match2[0] == "T1059"
    assert match2[1] == "Command Interpreter"

    match3 = trie.longest_prefix("NO_MATCH_HERE")
    assert match3 is None


def test_radix_trie_suggest_limit() -> None:
    """Test limit clamping on find_by_prefix."""
    trie: RadixTrie[int] = RadixTrie()
    for i in range(50):
        trie.insert(f"CWE-{i:03d}", i)

    results = trie.find_by_prefix("CWE-", limit=5)
    assert len(results) == 5

    none_match = trie.find_by_prefix("NONEXISTENT")
    assert none_match == []


def test_radix_trie_security_max_length() -> None:
    """Test maximum key length boundary to defend against DoS."""
    trie: RadixTrie[str] = RadixTrie()
    oversized = "a" * (MAX_RADIX_KEY_LENGTH + 1)
    with pytest.raises(ValueError, match="exceeds safe limit"):
        trie.insert(oversized, "overflow")


def test_mitre_taxonomy_prefix_search_integration() -> None:
    """Verify MITRE ATT&CK taxonomy prefix search using RadixTrie."""
    results = search_techniques_by_prefix("T1059")
    assert len(results) >= 1
    assert any(item["id"] == "T1059" for item in results)

    # Partial prefix
    t1_results = search_techniques_by_prefix("T1", limit=10)
    assert len(t1_results) >= 2
    for r in t1_results:
        assert r["id"].startswith("T1")


def test_cwe_taxonomy_prefix_search_integration() -> None:
    """Verify CWE taxonomy prefix search using RadixTrie."""
    results = search_cwe_by_prefix("CWE-7")
    # Should match CWE-79, CWE-787 etc if present
    cwe_ids = [r["id"] for r in results]
    for cid in cwe_ids:
        assert cid.startswith("CWE-7")

    # Number-only prefix shorthand
    results_num = search_cwe_by_prefix("89")
    assert any(r["id"] == "CWE-89" for r in results_num)
