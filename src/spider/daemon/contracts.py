#!/usr/bin/env python3
"""
Contracts and data transfer models for the resident Spider Daemon subsystem.
Defines CrawlJob, CrawlResult, SpiderSessionState, and session HSM trees.
"""

from __future__ import annotations

import enum
import time
import uuid
from dataclasses import dataclass, field
from typing import Any, Dict, List, Optional

from core.hsm import StateNode, TransitionRule


class SpiderSessionState(enum.Enum):
    """Session operational state of a resident spider worker process."""

    INITIALIZING = "INITIALIZING"
    IDLE = "IDLE"
    FETCHING = "FETCHING"
    BACKOFF = "BACKOFF"
    DRAINING = "DRAINING"
    STOPPED = "STOPPED"
    FAILED = "FAILED"

    @property
    def super_state(self) -> str:
        """Returns the high-level composite super-state name."""
        if self in (
            SpiderSessionState.IDLE,
            SpiderSessionState.FETCHING,
            SpiderSessionState.BACKOFF,
        ):
            return "OPERATIONAL"
        if self in (
            SpiderSessionState.INITIALIZING,
            SpiderSessionState.DRAINING,
        ):
            return "TRANSITIONING"
        return "TERMINATED"

    @property
    def hierarchical_path(self) -> str:
        """Returns the dotted hierarchical state path."""
        mapping = {
            "IDLE": "OPERATIONAL.ACTIVE.IDLE",
            "FETCHING": "OPERATIONAL.ACTIVE.FETCHING",
            "BACKOFF": "OPERATIONAL.ACTIVE.BACKOFF",
            "INITIALIZING": "TRANSITIONING.INITIALIZING",
            "DRAINING": "TRANSITIONING.DRAINING",
            "STOPPED": "TERMINATED.STOPPED",
            "FAILED": "TERMINATED.FAILED",
        }
        return mapping.get(self.value, self.value)


@dataclass
class CrawlJob:
    """Encapsulates an asynchronous crawl dispatch request."""

    spider_name: str
    job_id: str = field(default_factory=lambda: str(uuid.uuid4()))
    params: Dict[str, Any] = field(default_factory=dict)
    priority: int = 0
    created_at: float = field(default_factory=time.time)

    def to_dict(self) -> Dict[str, Any]:
        """Serializes CrawlJob to a standard primitive dictionary."""
        return {
            "job_id": self.job_id,
            "spider_name": self.spider_name,
            "params": dict(self.params),
            "priority": self.priority,
            "created_at": self.created_at,
        }

    @classmethod
    def from_dict(cls, data: Dict[str, Any]) -> CrawlJob:
        """Deserializes primitive dictionary into a CrawlJob instance."""
        return cls(
            job_id=str(data.get("job_id", uuid.uuid4())),
            spider_name=str(data.get("spider_name", "")),
            params=dict(data.get("params", {})),
            priority=int(data.get("priority", 0)),
            created_at=float(data.get("created_at", time.time())),
        )


@dataclass
class CrawlResult:
    """Encapsulates the execution outcome and telemetry of a CrawlJob."""

    job_id: str
    spider_name: str
    success: bool
    item_count: int = 0
    items: List[Dict[str, Any]] = field(default_factory=list)
    stats: Dict[str, Any] = field(default_factory=dict)
    error: Optional[str] = None
    duration_seconds: float = 0.0

    def to_dict(self) -> Dict[str, Any]:
        """Serializes CrawlResult to a standard primitive dictionary."""
        return {
            "job_id": self.job_id,
            "spider_name": self.spider_name,
            "success": self.success,
            "item_count": self.item_count,
            "items": list(self.items),
            "stats": dict(self.stats),
            "error": self.error,
            "duration_seconds": self.duration_seconds,
        }

    @classmethod
    def from_dict(cls, data: Dict[str, Any]) -> CrawlResult:
        """Deserializes primitive dictionary into a CrawlResult instance."""
        return cls(
            job_id=str(data.get("job_id", "")),
            spider_name=str(data.get("spider_name", "")),
            success=bool(data.get("success", False)),
            item_count=int(data.get("item_count", 0)),
            items=list(data.get("items", [])),
            stats=dict(data.get("stats", {})),
            error=data.get("error"),
            duration_seconds=float(data.get("duration_seconds", 0.0)),
        )


def _build_spider_operational_substates(active_node: StateNode) -> None:
    idle = active_node.add_child(StateNode("IDLE"))
    fetching = active_node.add_child(StateNode("FETCHING"))
    backoff = active_node.add_child(StateNode("BACKOFF"))
    idle.add_transition(
        TransitionRule("IDLE", "START_JOB", "OPERATIONAL.ACTIVE.FETCHING")
    )
    fetching.add_transition(
        TransitionRule("FETCHING", "JOB_DONE", "OPERATIONAL.ACTIVE.IDLE")
    )
    fetching.add_transition(
        TransitionRule("FETCHING", "RATE_LIMIT", "OPERATIONAL.ACTIVE.BACKOFF")
    )
    backoff.add_transition(
        TransitionRule("BACKOFF", "COOLDOWN_DONE", "OPERATIONAL.ACTIVE.IDLE")
    )


def _build_spider_root_nodes(root: StateNode) -> tuple[StateNode, StateNode, StateNode]:
    trans = root.add_child(StateNode("TRANSITIONING", initial_child="INITIALIZING"))
    trans.add_child(StateNode("INITIALIZING"))
    trans.add_child(StateNode("DRAINING"))

    term = root.add_child(StateNode("TERMINATED", initial_child="STOPPED"))
    term.add_child(StateNode("STOPPED"))
    term.add_child(StateNode("FAILED"))

    op = root.add_child(StateNode("OPERATIONAL", initial_child="ACTIVE"))
    active = op.add_child(StateNode("ACTIVE", initial_child="IDLE"))
    _build_spider_operational_substates(active)
    return trans, op, term


def _attach_spider_lifecycle_rules(
    trans: StateNode, op: StateNode, term: StateNode
) -> None:
    trans.add_transition(
        TransitionRule("INITIALIZING", "SETUP_SUCCESS", "OPERATIONAL.ACTIVE.IDLE")
    )
    trans.add_transition(
        TransitionRule("INITIALIZING", "SETUP_ERROR", "TERMINATED.FAILED")
    )
    op.add_transition(
        TransitionRule("OPERATIONAL", "SIGQUIT", "TRANSITIONING.DRAINING")
    )
    trans.add_transition(
        TransitionRule("DRAINING", "DRAIN_COMPLETE", "TERMINATED.STOPPED")
    )
    op.add_transition(TransitionRule("OPERATIONAL", "FORCE_KILL", "TERMINATED.FAILED"))
    op.add_transition(TransitionRule("OPERATIONAL", "SIGTERM", "TERMINATED.STOPPED"))


def build_spider_session_state_tree(worker_id: str = "spider") -> StateNode:
    """
    Constructs a 3-tier DSN-23 compliant Hierarchical State Machine tree
    for resident spider session lifecycle management.
    """
    root = StateNode(f"SPIDER_{worker_id}", initial_child="TRANSITIONING")
    trans, op, term = _build_spider_root_nodes(root)
    _attach_spider_lifecycle_rules(trans, op, term)
    return root
