"""Unit tests for distributed coordination, Spider CLI runner, and fetcher adapter."""

import os
import shutil
import tempfile

from src.fetcher.ingestion.adapters.registry import get_source_registry
from src.fetcher.ingestion.adapters.spider_adapter import SpiderSourceAdapter
from src.spider.core.downloader import Request
from src.spider.core.engine import ScrapedItem
from src.spider.core.scheduler import Scheduler
from src.spider.distributed.consistent_hash import ConsistentHashRouter
from src.spider.distributed.contracts import SpiderContractVerifier
from src.spider.distributed.state_storage import StateStorage
from src.spider.runner import parse_cli_args


def test_consistent_hash_router() -> None:
    router = ConsistentHashRouter(nodes=["node1", "node2", "node3"], virtual_nodes=50)
    target1 = router.get_node("arxiv.org")
    target2 = router.get_node("arxiv.org")
    assert target1 == target2  # Consistent locality

    target_iacr = router.get_node("eprint.iacr.org")
    assert target_iacr in {"node1", "node2", "node3"}


def test_state_storage_pause_resume() -> None:
    temp_dir = tempfile.mkdtemp()
    try:
        state_file = os.path.join(temp_dir, "spider_state.json")
        scheduler = Scheduler()
        req1 = Request(url="https://arxiv.org/abs/1", priority=10)
        req2 = Request(url="https://arxiv.org/abs/2", priority=20)
        scheduler.enqueue(req1)
        scheduler.enqueue(req2)

        # Save state
        StateStorage.save_state(scheduler, state_file)
        assert os.path.exists(state_file)

        # Restore into new scheduler
        new_scheduler = Scheduler()
        restored = StateStorage.restore_state(new_scheduler, state_file)
        assert restored == 2
        assert len(new_scheduler) == 2
        first = new_scheduler.next_request()
        assert first is not None
        assert first.url == "https://arxiv.org/abs/2"  # Higher priority first
    finally:
        shutil.rmtree(temp_dir)


def test_spider_contract_verifier() -> None:
    doc = """
    Spider for testing.
    @url https://arxiv.org/list/cs.CR/recent
    @returns items 1 10
    @scrapes title, abstract, published_date
    """
    contracts = SpiderContractVerifier.extract_contracts(doc)
    assert contracts["url"] == "https://arxiv.org/list/cs.CR/recent"
    assert contracts["returns_type"] == "items"
    assert contracts["returns_min"] == 1
    assert "title" in contracts["scrapes_fields"]

    item = ScrapedItem(
        item_id="1",
        source_url="https://arxiv.org/abs/1",
        title="Valid Title",
        payload={"abstract": "Valid", "published_date": "2026-08-21"},
    )
    assert (
        SpiderContractVerifier.verify_items(
            [item], ["title", "abstract", "published_date"]
        )
        is True
    )
    assert (
        SpiderContractVerifier.verify_items([item], ["title", "missing_field"]) is False
    )


def test_spider_cli_args_parsing() -> None:
    args = parse_cli_args(
        ["--spider", "iacr", "--max-requests", "10", "--delay", "1.0", "--persist-db"]
    )
    assert args.spider == "iacr"
    assert args.max_requests == 10
    assert args.delay == 1.0
    assert args.persist_db is True


def test_spider_adapter_registration() -> None:
    registry = get_source_registry()
    sources = registry.list_sources()
    assert "spider_arxiv" in sources
    assert "spider_iacr" in sources
    assert "spider_advisory" in sources

    adapter = registry.get("spider_arxiv")
    assert isinstance(adapter, SpiderSourceAdapter)
    assert adapter.spider_name == "arxiv"
