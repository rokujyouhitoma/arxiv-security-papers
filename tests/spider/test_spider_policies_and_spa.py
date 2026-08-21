from src.spider.core.downloader import Request, Response
from src.spider.downloader.spa_handler import SpaContentExtractor
from src.spider.policies.autothrottle import AutoThrottlePolicy
from src.spider.policies.normalizer import TrapDetector, UrlNormalizer
from src.spider.policies.opic import OpicCalculator, TopicRelevanceScorer


def test_spa_hydration_state_extraction() -> None:
    html = """
    <html>
        <head>
            <script id="__NEXT_DATA__" type="application/json">
                {"props": {"pageProps": {"paper": {"title": "Zero Trust Protocol", "id": "2608.9999"}}}}
            </script>
            <script type="application/ld+json">
                {"@context": "https://schema.org", "@type": "ScholarlyArticle", "headline": "Zero Knowledge Proofs"}
            </script>
        </head>
        <body>
            <div id="root"></div>
            <script>
                fetch('/api/v1/papers/recent');
                axios.get('/api/v1/advisories/active');
            </script>
        </body>
    </html>
    """
    extracted = SpaContentExtractor.extract_hydration_state(html)
    assert "next_data" in extracted
    assert (
        extracted["next_data"]["props"]["pageProps"]["paper"]["title"]
        == "Zero Trust Protocol"
    )
    assert "json_ld" in extracted
    assert extracted["json_ld"][0]["headline"] == "Zero Knowledge Proofs"

    endpoints = SpaContentExtractor.sniff_api_endpoints(
        html, base_url="https://example.com"
    )
    assert "https://example.com/api/v1/papers/recent" in endpoints
    assert "https://example.com/api/v1/advisories/active" in endpoints


def test_url_normalizer() -> None:
    raw_url = "HTTP://Research.EXAMPLE.COM:80/papers/../papers/./index.html?utm_source=rss&b=2&a=1#section"
    normalized = UrlNormalizer.normalize(raw_url)
    assert normalized == "http://research.example.com/papers/index.html?a=1&b=2"


def test_trap_detector() -> None:
    detector = TrapDetector(max_depth=5, max_params=3)
    normal_url = "https://example.com/research/security/paper1"
    assert detector.is_trap(normal_url) is False

    # Excessive depth
    deep_url = "https://example.com/a/b/c/d/e/f/g/h"
    assert detector.is_trap(deep_url) is True

    # Repeating directory loop
    cycle_url = "https://example.com/calendar/2026/calendar/2026/calendar/2026/view"
    assert detector.is_trap(cycle_url) is True

    # Sensitive path
    login_url = "https://example.com/admin/dashboard/login"
    assert detector.is_trap(login_url) is True


def test_autothrottle_policy() -> None:
    async def _run() -> None:
        policy = AutoThrottlePolicy(min_delay=0.2, max_delay=10.0, alpha=5.0)
        req = Request(url="https://arxiv.org/abs/1")
        resp = Response(
            url="https://arxiv.org/abs/1",
            status_code=200,
            headers={},
            body=b"OK",
            request=req,
            download_latency=0.1,
        )
        await policy.process_response(req, resp, spider=None)
        delay = policy.get_delay("arxiv.org")
        assert 0.2 <= delay <= 10.0

    import asyncio

    asyncio.run(_run())


def test_opic_and_topic_relevance() -> None:
    opic = OpicCalculator(initial_cash=1.0)
    opic.visit(
        "https://arxiv.org/hub", ["https://arxiv.org/p1", "https://arxiv.org/p2"]
    )
    assert opic.get_cash("https://arxiv.org/hub") == 0.0
    assert opic.get_cash("https://arxiv.org/p1") == 1.5  # 1.0 initial + 0.5 share
    assert opic.get_cash("https://arxiv.org/p2") == 1.5

    sec_text = (
        "This paper analyzes side-channel vulnerability in "
        "post-quantum cryptography and proposes exploit mitigation."
    )
    non_sec_text = "Cooking recipes for delicious Italian pasta and tomato sauces."

    assert TopicRelevanceScorer.is_relevant(sec_text) is True
    assert TopicRelevanceScorer.is_relevant(non_sec_text) is False
