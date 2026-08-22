"""
Unit tests for the Ingestion layer (arXiv client, XML parsing, PDF extractor).
"""

import os
import tempfile
import xml.etree.ElementTree as ET

from pipeline.ingestion import (
    clean_text,
    get_paper_pub_date_str,
    load_config,
    parse_arxiv_entry,
    save_raw_paper_data,
)


def test_clean_text():
    assert clean_text("  Hello \n\t World  ") == "Hello World"
    assert clean_text("") == ""
    assert clean_text(None) == ""


def test_load_config():
    config = load_config()
    assert isinstance(config, dict)
    assert "arxiv" in config
    assert config["arxiv"]["query"] == "cat:cs.CR"


def test_parse_arxiv_entry():
    sample_xml = """<entry xmlns="http://www.w3.org/2005/Atom" xmlns:arxiv="http://arxiv.org/schemas/atom">
        <id>http://arxiv.org/abs/2608.12345v1</id>
        <title> Deep Learning in Network Intrusion Detection </title>
        <summary> This is an abstract on intrusion detection systems. </summary>
        <published>2026-08-15T12:00:00Z</published>
        <updated>2026-08-16T12:00:00Z</updated>
        <author><name>Alice Smith</name></author>
        <author><name>Bob Jones</name></author>
        <category term="cs.CR"/>
        <arxiv:primary_category term="cs.CR"/>
    </entry>"""
    entry = ET.fromstring(sample_xml)
    parsed = parse_arxiv_entry(entry)

    assert parsed["arxiv_id"] == "2608.12345v1"
    assert parsed["clean_id"] == "2608.12345"
    assert parsed["title"] == "Deep Learning in Network Intrusion Detection"
    assert parsed["authors"] == ["Alice Smith", "Bob Jones"]
    assert parsed["primary_category"] == "cs.CR"
    assert parsed["pdf_url"] == "https://arxiv.org/pdf/2608.12345v1.pdf"


def test_get_paper_pub_date_str():
    paper = {"published": "2026-08-15T10:00:00Z"}
    assert get_paper_pub_date_str(paper) == "2026-08-15"

    paper_invalid = {"published": "invalid-date"}
    assert len(get_paper_pub_date_str(paper_invalid)) == 10


def test_save_raw_paper_data():
    with tempfile.TemporaryDirectory() as tmpdir:
        config = {
            "paths": {
                "raw_data_dir": "outputs/raw_data",
            }
        }
        paper = {
            "arxiv_id": "2608.99999v1",
            "clean_id": "2608.99999",
            "title": "Zero-Trust Architecture in Cloud",
            "title_ja": "クラウドにおけるゼロトラストアーキテクチャ",
            "published": "2026-08-17T00:00:00Z",
            "authors": ["Carol White"],
            "summary": "Evaluation of zero-trust microsegmentation.",
        }
        meta_path = save_raw_paper_data(paper, tmpdir, config)
        assert os.path.exists(meta_path)
        assert meta_path.endswith("2608.99999_meta.json")

        abs_path = os.path.join(
            os.path.dirname(meta_path), "2608.99999_raw_abstract.txt"
        )
        assert os.path.exists(abs_path)


def test_safe_urlopen_fallback():
    import ssl
    import urllib.error
    from unittest.mock import MagicMock, patch

    from pipeline.ingestion.arxiv_client import safe_urlopen

    # Test standard success
    mock_resp = MagicMock()
    mock_resp.status = 200
    with patch("urllib.request.urlopen", return_value=mock_resp) as mock_open:
        resp = safe_urlopen("https://example.com")
        assert resp.status == 200
        assert mock_open.call_count == 1

    # Test SSL failure retry with unverified context
    call_count = 0

    def fail_first_then_succeed(req, **kwargs):
        nonlocal call_count
        call_count += 1
        if call_count == 1:
            err_msg = (
                "[SSL: CERTIFICATE_VERIFY_FAILED] certificate verify failed: "
                "self-signed certificate in certificate chain (_ssl.c:1082)"
            )
            raise urllib.error.URLError(ssl.SSLCertVerificationError(1, err_msg))
        ret = MagicMock()
        ret.status = 200
        return ret

    with patch("urllib.request.urlopen", side_effect=fail_first_then_succeed):
        resp = safe_urlopen("https://example.com")
        assert resp.status == 200
        assert call_count == 2
