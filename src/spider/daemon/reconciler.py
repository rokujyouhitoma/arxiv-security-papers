"""
Autonomous Spider Job Reconciler & Self-Healing Crash Recovery Policy.
Detects stale running jobs, verifies checkpoint integrity, and manages autonomous recovery cycles.
"""

from __future__ import annotations

import logging
from typing import Any, Dict, List, Optional, Tuple

from ..distributed.state_storage import StateStorage
from .storage import SpiderExecutionStorage

logger = logging.getLogger(__name__)


def _inspect_checkpoint_integrity(
    spider_name: str, checkpoints_dir: str
) -> Tuple[bool, Optional[str]]:
    """Checks whether checkpoint exists and is free from JSON corruption."""
    return StateStorage.validate_checkpoint(spider_name, base_dir=checkpoints_dir)


def _handle_corrupted_checkpoint(
    spider_name: str, checkpoints_dir: str, reason: str
) -> Dict[str, Any]:
    """Quarantines corrupted checkpoint to prevent infinite crash loops."""
    dest = StateStorage.quarantine_checkpoint(
        spider_name, base_dir=checkpoints_dir, reason="corrupt"
    )
    logger.warning(
        "[SpiderReconciler] Corrupted checkpoint for %s quarantined to %s: %s",
        spider_name,
        dest,
        reason,
    )
    return {
        "spider_name": spider_name,
        "action": "QUARANTINED",
        "reason": reason,
        "quarantine_path": dest,
    }


def _handle_valid_recovery_candidate(
    spider_name: str,
    recovery_dir: str,
    checkpoints_dir: str,
    max_attempts: int,
) -> Dict[str, Any]:
    """Applies recovery retry threshold and determines whether to resume or quarantine."""
    rec = StateStorage.record_recovery_attempt(
        spider_name,
        base_dir=recovery_dir,
        max_attempts=max_attempts,
        reason="Stale job recovered from checkpoint",
    )
    if rec.get("is_exhausted"):
        dest = StateStorage.quarantine_checkpoint(
            spider_name, base_dir=checkpoints_dir, reason="exhausted"
        )
        logger.error(
            "[SpiderReconciler] Max recovery attempts (%d) exceeded for %s. Quarantined to %s",
            max_attempts,
            spider_name,
            dest,
        )
        return {
            "spider_name": spider_name,
            "action": "EXHAUSTED",
            "attempts": rec.get("attempts", 0),
            "quarantine_path": dest,
        }
    logger.info(
        "[SpiderReconciler] Checkpoint for %s is valid. Recovery candidate attempt %d/%d",
        spider_name,
        rec.get("attempts", 0),
        max_attempts,
    )
    return {
        "spider_name": spider_name,
        "action": "RECOVERABLE",
        "attempts": rec.get("attempts", 0),
        "recovery_info": rec,
    }


def _process_spider_recovery(
    spider_name: str,
    checkpoints_dir: str,
    recovery_dir: str,
    max_attempts: int,
) -> Optional[Dict[str, Any]]:
    """Evaluates checkpoint existence and dispatches to appropriate recovery handler."""
    if not StateStorage.has_checkpoint(spider_name, base_dir=checkpoints_dir):
        return None
    is_valid, err = _inspect_checkpoint_integrity(spider_name, checkpoints_dir)
    if not is_valid:
        return _handle_corrupted_checkpoint(spider_name, checkpoints_dir, str(err))
    return _handle_valid_recovery_candidate(
        spider_name, recovery_dir, checkpoints_dir, max_attempts
    )


def _collect_recovery_actions(
    spiders: Tuple[str, ...],
    checkpoints_dir: str,
    recovery_dir: str,
    max_attempts: int,
) -> List[Dict[str, Any]]:
    actions: List[Dict[str, Any]] = []
    for name in spiders:
        act = _process_spider_recovery(
            name, checkpoints_dir, recovery_dir, max_attempts
        )
        if act is not None:
            actions.append(act)
    return actions


def _count_actions_by_type(actions: List[Dict[str, Any]]) -> Tuple[int, int]:
    rec_cnt = sum(1 for a in actions if a.get("action") == "RECOVERABLE")
    quar_cnt = sum(
        1 for a in actions if a.get("action") in ("QUARANTINED", "EXHAUSTED")
    )
    return rec_cnt, quar_cnt


class SpiderReconciler:
    """Orchestrates detection of aborted crawlers and governs self-healing resume policies."""

    ALL_SPIDERS = ("arxiv", "cwe", "cve_nvd", "cisa_kev")

    def __init__(
        self,
        storage: Optional[SpiderExecutionStorage] = None,
        checkpoints_dir: str = "outputs/spider/checkpoints",
        recovery_dir: str = "outputs/spider/recovery",
        max_attempts: int = 3,
    ) -> None:
        self.storage = storage or SpiderExecutionStorage()
        self.checkpoints_dir = checkpoints_dir
        self.recovery_dir = recovery_dir
        self.max_attempts = max_attempts

    def reconcile_and_recover(self, timeout_seconds: float = 7200.0) -> Dict[str, Any]:
        """Detects stale jobs, marks them INTERRUPTED, and evaluates recovery candidates."""
        stale_count = self.storage.reconcile_stale_jobs(timeout_seconds=timeout_seconds)
        actions = _collect_recovery_actions(
            self.ALL_SPIDERS, self.checkpoints_dir, self.recovery_dir, self.max_attempts
        )
        rec_cnt, quar_cnt = _count_actions_by_type(actions)
        return {
            "stale_jobs_count": stale_count,
            "actions": actions,
            "recoverable_count": rec_cnt,
            "quarantined_count": quar_cnt,
        }
