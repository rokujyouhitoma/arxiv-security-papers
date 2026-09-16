"""Unit and boundary tests for Pure Packrat PEG BibTeX and citation extraction."""

from pdf_engine.bibtex_extractor import (
    extract_arxiv_references,
    extract_bibtex_entries,
    extract_latex_citations,
)


def test_extract_bibtex_entries_standard() -> None:
    text = """
@article{diffie1976new,
  author = {Whitfield Diffie and Martin E. Hellman},
  title = {New Directions in Cryptography},
  journal = {IEEE Transactions on Information Theory},
  year = {1976},
  volume = {22},
  pages = {644--654}
}

@inproceedings{shamir1979share,
  author = "Adi Shamir",
  title = "How to Share a Secret",
  booktitle = "Communications of the ACM",
  year = "1979"
}
"""
    entries = extract_bibtex_entries(text)
    assert len(entries) == 2
    e1, e2 = entries[0], entries[1]
    assert (e1.entry_type, e1.cite_key, e1.fields["year"], e1.fields["pages"]) == (
        "article",
        "diffie1976new",
        "1976",
        "644–654",
    )
    assert (e2.entry_type, e2.cite_key, e2.fields["author"], e2.fields["title"]) == (
        "inproceedings",
        "shamir1979share",
        "Adi Shamir",
        "How to Share a Secret",
    )


def test_extract_bibtex_nested_braces_and_latex_escapes() -> None:
    text = """
@book{knuth1984texbook,
  author = {Donald E. Knuth},
  title = {The {\\TeX}book and {ACM} Guidelines},
  publisher = {Addison---Wesley},
  year = {1984}
}
"""
    entries = extract_bibtex_entries(text)
    assert len(entries) == 1
    e = entries[0]
    assert ("Addison—Wesley" in e.fields["publisher"]) and ("The" in e.fields["title"])


def test_extract_latex_citations() -> None:
    text = r"""
According to \cite{diffie1976new}, public-key systems were established.
Later studies \citep{shamir1979share, rivest1978rsa} extended this concept.
Further analyzed in \citet{ford2004packrat}.
"""
    citations = extract_latex_citations(text)
    assert citations == [
        "diffie1976new",
        "shamir1979share",
        "rivest1978rsa",
        "ford2004packrat",
    ]


def test_extract_arxiv_references() -> None:
    text = """
See prior art at arXiv:2401.12345 and https://arxiv.org/abs/2312.09876v2.
Also referenced arxiv.org/pdf/2105.00001.
"""
    refs = extract_arxiv_references(text)
    assert refs == ["2401.12345", "2312.09876", "2105.00001"]


def test_extract_bibtex_resilience_on_non_bibtex() -> None:
    assert extract_bibtex_entries("Just some text without any at signs.") == []
    assert extract_bibtex_entries("@invalid syntax without closing brace") == []
