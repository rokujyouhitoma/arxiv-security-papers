"""
Unit tests for Intelligent Dehyphenation in PDF text extraction.
Verifies preservation of compound security terms and proper syllabic merging.
"""

from pdf_engine.layout import dehyphenate_text


def test_intelligent_dehyphenation_security_compounds() -> None:
    # Compounds that MUST preserve hyphen
    assert dehyphenate_text("zero-\ntrust architecture") == "zero-trust architecture"
    assert dehyphenate_text("cross-\nsite scripting") == "cross-site scripting"
    assert dehyphenate_text("side-\nchannel attack") == "side-channel attack"
    assert dehyphenate_text("fault-\ntolerant system") == "fault-tolerant system"
    assert dehyphenate_text("real-\ntime analysis") == "real-time analysis"
    assert dehyphenate_text("peer-\nto-peer network") == "peer-to-peer network"
    assert dehyphenate_text("multi-\n  tenant cloud") == "multi-tenant cloud"


def test_syllabic_dehyphenation_merges_words() -> None:
    # Standard syllabic breaks that MUST be merged without hyphen
    assert dehyphenate_text("cyber-\nsecurity") == "cybersecurity"
    assert dehyphenate_text("cryp-\ntography") == "cryptography"
    assert dehyphenate_text("secu-\nrity") == "security"
    assert dehyphenate_text("clas-\nsification") == "classification"
    assert dehyphenate_text("authen-\ntication") == "authentication"
    assert dehyphenate_text("infor-\nmation") == "information"


def test_hyphen_preservation_with_proper_nouns_or_caps() -> None:
    assert dehyphenate_text("anti-\nAmerican") == "anti-American"
