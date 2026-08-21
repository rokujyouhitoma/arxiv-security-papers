"""
Tests for Dynamic and Fast Vector Highlighters (src/search/platform/highlight/).
"""

from search.platform.highlight import DynamicHighlighter, FastVectorHighlighter


def test_dynamic_highlighter_escaping_and_tags():
    hl = DynamicHighlighter(pre_tag="<mark>", post_tag="</mark>", fragment_size=100)
    text = (
        "We discover a critical Zero-Day vulnerability in modern TLS implementations."
    )
    res = hl.highlight(text, ["Zero-Day", "vulnerability"])
    assert "<mark>Zero-Day</mark>" in res or "<mark>vulnerability</mark>" in res

    # Test XSS protection: script tag inside text should be escaped
    xss_text = "<script>alert(1)</script> Vulnerability report on Zero-Day attacks."
    xss_res = hl.highlight(xss_text, ["Zero-Day"])
    assert "<script>" not in xss_res
    assert "&lt;script&gt;" in xss_res


def test_fast_vector_highlighter():
    fvh = FastVectorHighlighter(pre_tag='<span class="hl">', post_tag="</span>")
    text = "Advanced Ransomware Defense mechanisms."
    res = fvh.highlight_field(text, ["Ransomware"])
    assert '<span class="hl">Ransomware</span>' in res
