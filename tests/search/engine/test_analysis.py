"""
Tests for Core Search Engine Analysis (src/search/engine/analysis/).
"""

from search.engine.analysis import (
    CJKAnalyzer,
    CJKBigramTokenizer,
    HTMLStripCharFilter,
    LowerCaseFilter,
    MappingCharFilter,
    PorterStemFilter,
    StandardAnalyzer,
    StandardTokenizer,
    StopFilter,
    SynonymFilter,
)


def test_char_filters():
    html_f = HTMLStripCharFilter()
    filtered = html_f.filter("<p>hello <b>world</b></p>")
    assert "hello" in filtered and "world" in filtered

    map_f = MappingCharFilter({"foo": "bar"})
    assert map_f.filter("foo test") == "bar test"


def test_tokenizers():
    tok = StandardTokenizer()
    tokens = tok.tokenize("arXiv:2608.12345 Ransomware Attack")
    assert any("2608.12345" in t for t in tokens)
    assert "Ransomware" in tokens

    cjk_tok = CJKBigramTokenizer()
    cjk_tokens = cjk_tok.tokenize("脆弱性診断")
    assert (
        "脆弱" in cjk_tokens
        and "弱性" in cjk_tokens
        and "性診" in cjk_tokens
        and "診断" in cjk_tokens
    )


def test_token_filters_and_analyzers():
    low_f = LowerCaseFilter()
    assert low_f.filter(["ABC", "Def"]) == ["abc", "def"]

    stop_f = StopFilter()
    assert "the" not in stop_f.filter(["the", "ransomware"])

    stem_f = PorterStemFilter()
    assert stem_f.filter(["vulnerabilities", "attacks", "protecting"]) == [
        "vulnerabiliti",
        "attack",
        "protect",
    ]

    syn_f = SynonymFilter()
    expanded = syn_f.filter(["ransomware"])
    assert "ランサムウェア" in expanded

    std_analyzer = StandardAnalyzer()
    assert "security" in std_analyzer.analyze("<p>Security</p>")

    cjk_analyzer = CJKAnalyzer()
    cjk_res = cjk_analyzer.analyze("<h1>ランサムウェア攻撃 (Ransomware)</h1>")
    assert "ransomware" in cjk_res
