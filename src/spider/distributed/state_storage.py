"""Pause and Resume State Storage for Crawl Frontier and Bloom Filter."""

from __future__ import annotations

import heapq
import json
import os
import re
from typing import Any, Dict, List, Optional, Sequence, Tuple

from ..core.bloom import ScalableBloomFilter
from ..core.downloader import Request
from ..core.scheduler import Scheduler


def _serialize_request(req: Request) -> Dict[str, Any]:
    """Serializes a single Request object into a dictionary."""
    return {
        "url": req.url,
        "callback": req.callback,
        "method": req.method,
        "headers": req.headers,
        "priority": req.priority,
        "dont_filter": req.dont_filter,
        "meta": req.meta,
    }


def _deserialize_request(item: Dict[str, Any]) -> Request:
    """Deserializes a dictionary into a Request object."""
    return Request(
        url=item["url"],
        callback=item.get("callback", "parse"),
        method=item.get("method", "GET"),
        headers=item.get("headers", {}),
        priority=item.get("priority", 0),
        dont_filter=item.get("dont_filter", False),
        meta=item.get("meta", {}),
    )


def _is_explicit_checkpoint_path(target: str) -> bool:
    if "/" in target:
        return True
    return target.endswith((".state", ".json"))


def _resolve_checkpoint_file(target: str, base_dir: str) -> str:
    """Resolves whether target is an explicit filepath or spider name."""
    if _is_explicit_checkpoint_path(target):
        return target
    clean_name = re.sub(r"[^a-zA-Z0-9_-]", "", os.path.basename(target))
    return os.path.join(base_dir, f"{clean_name}.state")


def _is_valid_heap_entry(item: Any) -> bool:
    if not isinstance(item, tuple) or len(item) < 3:
        return False
    return hasattr(item[2], "url")


def _collect_valid_requests(heap: Sequence[Any]) -> List[Dict[str, Any]]:
    res: List[Dict[str, Any]] = []
    for item in heap:
        if _is_valid_heap_entry(item):
            res.append(_serialize_request(item[2]))
    return res


def _extract_pending_requests(scheduler: Scheduler) -> List[Dict[str, Any]]:
    """Extracts serializable pending requests from scheduler heap."""
    heap = getattr(scheduler, "_heap", None)
    if not isinstance(heap, list):
        return []
    return _collect_valid_requests(heap)


def _safe_call_to_dict(bloom: Any) -> Any:
    try:
        return bloom.to_dict()
    except Exception:
        return None


def _get_bloom_dict(bloom: Any) -> Optional[Dict[str, Any]]:
    if not hasattr(bloom, "to_dict"):
        return None
    data = _safe_call_to_dict(bloom)
    return data if isinstance(data, dict) else None


def _extract_bloom_state(
    scheduler: Scheduler,
) -> Tuple[Optional[Dict[str, Any]], int]:
    """Safely extracts dictionary representation and element count of Bloom filter."""
    bloom = getattr(scheduler, "bloom", None)
    if bloom is None:
        return None, 0
    count = len(bloom) if hasattr(bloom, "__len__") else 0
    return _get_bloom_dict(bloom), count


def _write_atomic_json(filepath: str, state: Dict[str, Any]) -> None:
    """Writes JSON payload atomically using a temporary file."""
    dir_name = os.path.dirname(filepath)
    if dir_name:
        os.makedirs(dir_name, exist_ok=True)
    temp_path = f"{filepath}.tmp"
    with open(temp_path, "w", encoding="utf-8") as f:
        json.dump(state, f, ensure_ascii=False, indent=2)
    os.replace(temp_path, filepath)


def _restore_bloom(scheduler: Scheduler, state: Dict[str, Any]) -> None:
    """Restores ScalableBloomFilter if serialized bloom state exists."""
    bloom_state = state.get("bloom_state")
    if isinstance(bloom_state, dict):
        scheduler.bloom = ScalableBloomFilter.from_dict(bloom_state)


def _restore_queue(scheduler: Scheduler, state: Dict[str, Any]) -> int:
    """Restores pending requests into scheduler priority heap."""
    restored = 0
    for item in state.get("pending_requests", []):
        req = _deserialize_request(item)
        scheduler._counter += 1
        heapq.heappush(scheduler._heap, (-req.priority, scheduler._counter, req))
        restored += 1
    return restored


class StateStorage:
    """Persists and restores Scheduler state (Frontier & Bloom filter) to atomic JSON."""

    @staticmethod
    def save_state(scheduler: Scheduler, filepath: str) -> None:
        """Atomically dumps scheduler frontier and visited Bloom filter to JSON."""
        pending_requests = _extract_pending_requests(scheduler)
        bloom_state, bloom_count = _extract_bloom_state(scheduler)
        state = {
            "version": "1.0",
            "pending_count": len(pending_requests),
            "pending_requests": pending_requests,
            "bloom_count": bloom_count,
            "bloom_state": bloom_state,
        }
        _write_atomic_json(filepath, state)

    @staticmethod
    def restore_state(scheduler: Scheduler, filepath: str) -> int:
        """Restores pending requests and Bloom filter state into the scheduler."""
        if not os.path.exists(filepath):
            return 0
        with open(filepath, "r", encoding="utf-8") as f:
            state = json.load(f)
        _restore_bloom(scheduler, state)
        return _restore_queue(scheduler, state)

    @staticmethod
    def get_default_checkpoint_path(
        spider_name: str, base_dir: str = "outputs/spider/checkpoints"
    ) -> str:
        """Returns standard checkpoint path for given spider name."""
        return _resolve_checkpoint_file(spider_name, base_dir)

    @staticmethod
    def has_checkpoint(
        spider_name_or_path: str,
        base_dir: str = "outputs/spider/checkpoints",
    ) -> bool:
        """Checks if a valid non-empty checkpoint file exists."""
        path = _resolve_checkpoint_file(spider_name_or_path, base_dir)
        return os.path.isfile(path) and os.path.getsize(path) > 0

    @staticmethod
    def clear_checkpoint(
        spider_name_or_path: str,
        base_dir: str = "outputs/spider/checkpoints",
    ) -> bool:
        """Safely deletes checkpoint file if it exists."""
        path = _resolve_checkpoint_file(spider_name_or_path, base_dir)
        try:
            if os.path.exists(path):
                os.remove(path)
                return True
        except OSError:
            pass
        return False
