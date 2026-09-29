"""Unit tests for PrefixTrie container."""

from nlp.morphology.trie import PrefixTrie


def test_trie_insert_and_exact_search():
    """Verify exact match lookup and size counting."""
    trie = PrefixTrie()
    assert len(trie) == 0
    assert "attack" not in trie

    trie.insert("attack", 10)
    trie.insert("attacker", 20)
    trie.insert("attacker", 25)  # Update existing

    assert len(trie) == 2
    assert "attack" in trie
    assert "attacker" in trie
    assert "att" not in trie
    assert trie.search("attack") == 10
    assert trie.search("attacker") == 25
    assert trie.search("nonexistent") is None


def test_trie_common_prefix_search():
    """Verify multiple prefix matching in ascending order."""
    trie = PrefixTrie()
    trie.insert("side", 1)
    trie.insert("side-channel", 2)
    trie.insert("side-channel attack", 3)

    text = "side-channel attack against RSA"
    matches = trie.common_prefix_search(text, 0)
    assert len(matches) == 3
    assert matches[0] == ("side", 1)
    assert matches[1] == ("side-channel", 2)
    assert matches[2] == ("side-channel attack", 3)

    longest = trie.longest_prefix(text, 0)
    assert longest == ("side-channel attack", 3)


def test_trie_empty_and_out_of_bounds():
    """Verify edge cases for trie lookups."""
    trie = PrefixTrie()
    trie.insert("", 0)
    assert len(trie) == 0
    assert trie.search("") is None
    assert trie.common_prefix_search("test", -1) == []
    assert trie.common_prefix_search("test", 10) == []
    assert trie.longest_prefix("test", 10) is None
