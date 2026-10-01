"""Pause and Resume State Storage for Crawl Frontier and Bloom Filter."""

from __future__ import annotations

import datetime
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


def _find_candidate_checkpoint(clean_name: str, base_dir: str) -> str:
    for ext in (".state", ".json"):
        cand = os.path.join(base_dir, f"{clean_name}{ext}")
        if os.path.exists(cand):
            return cand
    return os.path.join(base_dir, f"{clean_name}.state")


def _resolve_checkpoint_file(target: str, base_dir: str) -> str:
    """Resolves whether target is an explicit filepath or spider name."""
    if _is_explicit_checkpoint_path(target):
        return target
    clean_name = re.sub(r"[^a-zA-Z0-9_-]", "", os.path.basename(target))
    return _find_candidate_checkpoint(clean_name, base_dir)


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


def _format_mtime(mtime: float) -> str:
    dt = datetime.datetime.fromtimestamp(mtime, tz=datetime.timezone.utc)
    return dt.strftime("%Y-%m-%d %H:%M:%S UTC")


def _read_checkpoint_metadata(path: str) -> Dict[str, Any]:
    try:
        stat = os.stat(path)
        with open(path, "r", encoding="utf-8") as f:
            data = json.load(f)
        pending = int(data.get("pending_count", len(data.get("pending_requests", []))))
        bloom_cnt = int(data.get("bloom_count", 0))
        return {
            "has_checkpoint": True,
            "path": path,
            "size_bytes": stat.st_size,
            "mtime": _format_mtime(stat.st_mtime),
            "pending_count": pending,
            "bloom_count": bloom_cnt,
            "version": str(data.get("version", "1.0")),
        }
    except Exception:
        return {"has_checkpoint": False, "corrupted": True}


def _resolve_progress_file(target: str, base_dir: str) -> str:
    """Resolves standard path for spider progress telemetry."""
    if "/" in target or target.endswith(".json"):
        return target
    clean_name = re.sub(r"[^a-zA-Z0-9_-]", "", os.path.basename(target))
    return os.path.join(base_dir, f"{clean_name}.progress.json")


def _calc_progress_metrics(
    processed: int, pending: int, elapsed_seconds: float
) -> Dict[str, Any]:
    """Calculates ratio, rate, and ETA from processed and pending queue counts."""
    total = processed + pending
    ratio_pct = round((processed / total * 100.0) if total > 0 else 0.0, 1)
    rate = round(processed / elapsed_seconds, 2) if elapsed_seconds > 0 else 0.0
    eta_sec = round(pending / rate, 1) if rate > 0 else 0.0
    return {
        "processed": processed,
        "pending": pending,
        "total": total,
        "ratio_pct": ratio_pct,
        "pages_per_second": rate,
        "eta_seconds": eta_sec,
        "elapsed_seconds": round(max(0.0, elapsed_seconds), 1),
    }


def _build_progress_dict(
    spider_name: str, metrics: Dict[str, Any], start_time: float, status: str
) -> Dict[str, Any]:
    """Constructs progress telemetry document with UTC timestamp."""
    now = datetime.datetime.now(datetime.timezone.utc).timestamp()
    res: Dict[str, Any] = {
        "spider_name": spider_name,
        "status": status,
        "is_active": status == "RUNNING",
        "start_time": start_time,
        "updated_at": now,
    }
    res.update(metrics)
    return res


def _read_progress_metadata(path: str) -> Dict[str, Any]:
    """Safely reads and deserializes progress file."""
    try:
        with open(path, "r", encoding="utf-8") as f:
            data = json.load(f)
        if isinstance(data, dict):
            return data
    except Exception:
        pass
    return {
        "is_active": False,
        "status": "IDLE",
        "processed": 0,
        "pending": 0,
        "total": 0,
        "ratio_pct": 0.0,
        "pages_per_second": 0.0,
        "eta_seconds": 0.0,
        "elapsed_seconds": 0.0,
    }


def _has_valid_queue_data(data: Any) -> bool:
    if not isinstance(data, dict):
        return False
    return "pending_requests" in data or "pending_count" in data


def _validate_checkpoint_file(path: str) -> Tuple[bool, Optional[str]]:
    """Validates structural integrity of checkpoint JSON file."""
    if not (os.path.isfile(path) and os.path.getsize(path) > 0):
        return False, "Checkpoint file does not exist or is empty"
    try:
        with open(path, "r", encoding="utf-8") as f:
            data = json.load(f)
        if not _has_valid_queue_data(data):
            return False, "Checkpoint payload must contain pending requests"
        return True, None
    except Exception as exc:
        return False, f"JSON parse error or corrupted file: {exc}"


def _quarantine_checkpoint_file(
    src_path: str,
    quarantine_dir: str,
    reason: str = "corrupt",
) -> Optional[str]:
    """Safely isolates corrupted or exhausted checkpoint file into quarantine directory."""
    if not os.path.exists(src_path):
        return None
    try:
        os.makedirs(quarantine_dir, exist_ok=True)
        ts = int(datetime.datetime.now(datetime.timezone.utc).timestamp())
        basename = os.path.basename(src_path)
        dst_name = f"{basename}.{reason}.{ts}"
        dst_path = os.path.join(quarantine_dir, dst_name)
        os.replace(src_path, dst_path)
        return dst_path
    except OSError:
        return None


def _resolve_recovery_file(target: str, base_dir: str) -> str:
    """Resolves standard path for spider recovery metadata."""
    if "/" in target or target.endswith(".json"):
        return target
    clean_name = re.sub(r"[^a-zA-Z0-9_-]", "", os.path.basename(target))
    return os.path.join(base_dir, f"{clean_name}.recovery.json")


def _read_recovery_metadata(path: str, spider_name: str) -> Dict[str, Any]:
    """Safely reads and deserializes recovery state metadata."""
    try:
        with open(path, "r", encoding="utf-8") as f:
            data = json.load(f)
        if isinstance(data, dict):
            return data
    except Exception:
        pass
    return {
        "spider_name": spider_name,
        "attempts": 0,
        "max_attempts": 3,
        "status": "INITIAL",
        "last_attempt_at": None,
        "reason": None,
    }


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

    @staticmethod
    def get_checkpoint_info(
        spider_name_or_path: str,
        base_dir: str = "outputs/spider/checkpoints",
    ) -> Dict[str, Any]:
        """Returns structured metadata of a spider checkpoint if it exists."""
        path = _resolve_checkpoint_file(spider_name_or_path, base_dir)
        if not (os.path.isfile(path) and os.path.getsize(path) > 0):
            return {"has_checkpoint": False}
        return _read_checkpoint_metadata(path)

    @staticmethod
    def calculate_progress(
        processed: int, pending: int, elapsed_seconds: float
    ) -> Dict[str, Any]:
        """Calculates percentage, crawl rate, and ETA from processed and pending counts."""
        return _calc_progress_metrics(processed, pending, elapsed_seconds)

    @staticmethod
    def save_progress(
        spider_name: str,
        processed: int,
        pending: int,
        start_time: float,
        status: str = "RUNNING",
        base_dir: str = "outputs/spider/progress",
    ) -> Dict[str, Any]:
        """Atomically persists live crawl telemetry progress to disk."""
        elapsed = datetime.datetime.now(datetime.timezone.utc).timestamp() - start_time
        metrics = _calc_progress_metrics(processed, pending, elapsed)
        progress = _build_progress_dict(spider_name, metrics, start_time, status)
        path = _resolve_progress_file(spider_name, base_dir)
        _write_atomic_json(path, progress)
        return progress

    @staticmethod
    def get_progress_info(
        spider_name: str,
        base_dir: str = "outputs/spider/progress",
    ) -> Dict[str, Any]:
        """Reads live crawl telemetry progress from disk."""
        path = _resolve_progress_file(spider_name, base_dir)
        if not (os.path.isfile(path) and os.path.getsize(path) > 0):
            return {
                "spider_name": spider_name,
                "is_active": False,
                "status": "IDLE",
                "processed": 0,
                "pending": 0,
                "total": 0,
                "ratio_pct": 0.0,
                "pages_per_second": 0.0,
                "eta_seconds": 0.0,
                "elapsed_seconds": 0.0,
            }
        return _read_progress_metadata(path)

    @staticmethod
    def clear_progress(
        spider_name: str,
        base_dir: str = "outputs/spider/progress",
    ) -> bool:
        """Removes progress telemetry file."""
        path = _resolve_progress_file(spider_name, base_dir)
        try:
            if os.path.exists(path):
                os.remove(path)
                return True
        except OSError:
            pass
        return False

    @staticmethod
    def validate_checkpoint(
        spider_name_or_path: str,
        base_dir: str = "outputs/spider/checkpoints",
    ) -> Tuple[bool, Optional[str]]:
        """Checks if checkpoint exists, is uncorrupted JSON, and contains valid queues."""
        path = _resolve_checkpoint_file(spider_name_or_path, base_dir)
        return _validate_checkpoint_file(path)

    @staticmethod
    def quarantine_checkpoint(
        spider_name_or_path: str,
        base_dir: str = "outputs/spider/checkpoints",
        quarantine_dir: Optional[str] = None,
        reason: str = "corrupt",
    ) -> Optional[str]:
        """Safely isolates an unreadable or exhausted checkpoint."""
        path = _resolve_checkpoint_file(spider_name_or_path, base_dir)
        qdir = quarantine_dir or os.path.join(base_dir, "quarantine")
        return _quarantine_checkpoint_file(path, qdir, reason=reason)

    @staticmethod
    def record_recovery_attempt(
        spider_name: str,
        base_dir: str = "outputs/spider/recovery",
        max_attempts: int = 3,
        reason: str = "",
    ) -> Dict[str, Any]:
        """Increments recovery attempts and transitions status atomically."""
        path = _resolve_recovery_file(spider_name, base_dir)
        cur = _read_recovery_metadata(path, spider_name)
        new_attempts = int(cur.get("attempts", 0)) + 1
        is_exhausted = new_attempts > max_attempts
        status = "EXHAUSTED" if is_exhausted else "RECOVERABLE"
        now_iso = datetime.datetime.now(datetime.timezone.utc).isoformat()
        res: Dict[str, Any] = {
            "spider_name": spider_name,
            "attempts": new_attempts,
            "max_attempts": max_attempts,
            "status": status,
            "last_attempt_at": now_iso,
            "reason": reason or cur.get("reason"),
            "is_exhausted": is_exhausted,
        }
        _write_atomic_json(path, res)
        return res

    @staticmethod
    def get_recovery_info(
        spider_name: str,
        base_dir: str = "outputs/spider/recovery",
    ) -> Dict[str, Any]:
        """Returns recovery status and attempt counters."""
        path = _resolve_recovery_file(spider_name, base_dir)
        if not (os.path.isfile(path) and os.path.getsize(path) > 0):
            return {
                "spider_name": spider_name,
                "has_recovery": False,
                "attempts": 0,
                "max_attempts": 3,
                "status": "INITIAL",
                "is_exhausted": False,
                "can_resume": False,
            }
        data = _read_recovery_metadata(path, spider_name)
        data["has_recovery"] = True
        is_ex = data.get("attempts", 0) > data.get("max_attempts", 3)
        data["is_exhausted"] = is_ex
        data["can_resume"] = not is_ex
        return data

    @staticmethod
    def clear_recovery_state(
        spider_name: str,
        base_dir: str = "outputs/spider/recovery",
    ) -> bool:
        """Clears recovery attempts record upon successful run or operator reset."""
        path = _resolve_recovery_file(spider_name, base_dir)
        try:
            if os.path.exists(path):
                os.remove(path)
                return True
        except OSError:
            pass
        return False
