"""Event Sourcing Write-Ahead Log (WAL) & Crash Recovery Engine.

Provides durable append-only event logging, checkpoint snapshots,
and state replay mechanisms to guarantee 100% crash recovery and resume.
"""

import json
import os
import uuid
from dataclasses import asdict, dataclass, field
from datetime import datetime, timezone
from enum import Enum
from typing import Any, Dict, List, Optional

from orchestrator.contracts import (
    FeedbackTelemetry,
    Hypothesis,
    HypothesisStatus,
    IntelligenceDirective,
    IntelligencePhase,
    IntelligenceProduct,
    PhaseContext,
    PhaseStatus,
)


class EventType(str, Enum):
    """Lifecycle event types recorded into the WAL."""

    CYCLE_STARTED = "cycle_started"
    CYCLE_COMPLETED = "cycle_completed"
    CYCLE_FAILED = "cycle_failed"
    PHASE_STARTED = "phase_started"
    PHASE_COMPLETED = "phase_completed"
    RECORD_HARVESTED = "record_harvested"
    RECORD_PROCESSED = "record_processed"
    PRODUCT_PUBLISHED = "product_published"
    HYPOTHESIS_EVALUATED = "hypothesis_evaluated"
    CHECKPOINT_CREATED = "checkpoint_created"


@dataclass
class OrchestratorEvent:
    """Atomic event record persisted into the WAL."""

    event_id: str
    cycle_id: str
    timestamp: str
    event_type: EventType
    payload: Dict[str, Any] = field(default_factory=dict)

    def to_dict(self) -> Dict[str, Any]:
        return {
            "event_id": self.event_id,
            "cycle_id": self.cycle_id,
            "timestamp": self.timestamp,
            "event_type": self.event_type.value,
            "payload": self.payload,
        }

    @classmethod
    def from_dict(cls, data: Dict[str, Any]) -> "OrchestratorEvent":
        return cls(
            event_id=str(data["event_id"]),
            cycle_id=str(data["cycle_id"]),
            timestamp=str(data["timestamp"]),
            event_type=EventType(data["event_type"]),
            payload=dict(data.get("payload", {})),
        )


class OrchestratorWAL:
    """Manages append-only write-ahead log files and state replay."""

    def __init__(self, wal_dir: str) -> None:
        self.wal_dir = os.path.abspath(wal_dir)
        os.makedirs(self.wal_dir, exist_ok=True)

    def _get_wal_path(self, cycle_id: str) -> str:
        return os.path.join(self.wal_dir, f"{cycle_id}.wal.jsonl")

    def _get_checkpoint_path(self, cycle_id: str) -> str:
        return os.path.join(self.wal_dir, f"{cycle_id}.checkpoint.json")

    def append_event(
        self,
        cycle_id: str,
        event_type: EventType,
        payload: Optional[Dict[str, Any]] = None,
    ) -> OrchestratorEvent:
        """Appends a new immutable event to the cycle WAL file."""
        now_iso = datetime.now(timezone.utc).isoformat()
        ev = OrchestratorEvent(
            event_id=f"ev_{uuid.uuid4().hex[:12]}",
            cycle_id=cycle_id,
            timestamp=now_iso,
            event_type=event_type,
            payload=payload or {},
        )

        wal_path = self._get_wal_path(cycle_id)
        line = json.dumps(ev.to_dict(), ensure_ascii=False) + "\n"
        with open(wal_path, "a", encoding="utf-8") as f:
            f.write(line)
            f.flush()
            os.fsync(f.fileno())

        return ev

    def read_events(self, cycle_id: str) -> List[OrchestratorEvent]:
        """Reads all historical events for the given cycle ID."""
        wal_path = self._get_wal_path(cycle_id)
        if not os.path.isfile(wal_path):
            return []

        events: List[OrchestratorEvent] = []
        with open(wal_path, "r", encoding="utf-8") as f:
            for line in f:
                line_str = line.strip()
                if line_str:
                    try:
                        data = json.loads(line_str)
                        events.append(OrchestratorEvent.from_dict(data))
                    except Exception:
                        continue
        return events

    def create_checkpoint(self, context: PhaseContext) -> str:
        """Saves a compacted snapshot of current context state."""
        cp_path = self._get_checkpoint_path(context.cycle_id)
        snapshot = {
            "cycle_id": context.cycle_id,
            "timestamp": datetime.now(timezone.utc).isoformat(),
            "phase_statuses": {
                p.value: s.value for p, s in context.phase_statuses.items()
            },
            "raw_records_count": len(context.raw_records),
            "raw_records": context.raw_records,
            "processed_records": context.processed_records,
            "products": [asdict(p) for p in context.products],
            "hypotheses": [asdict(h) for h in context.hypotheses],
            "errors": context.errors,
            "state": context.state,
        }
        if context.directive:
            snapshot["directive"] = asdict(context.directive)
        if context.telemetry:
            snapshot["telemetry"] = asdict(context.telemetry)

        temp_path = f"{cp_path}.tmp"
        with open(temp_path, "w", encoding="utf-8") as f:
            json.dump(snapshot, f, ensure_ascii=False, indent=2)
            f.flush()
            os.fsync(f.fileno())
        os.replace(temp_path, cp_path)

        self.append_event(
            cycle_id=context.cycle_id,
            event_type=EventType.CHECKPOINT_CREATED,
            payload={"checkpoint_path": cp_path},
        )
        return cp_path

    def _restore_from_checkpoint_dict(
        self, data: Dict[str, Any], workspace_dir: str
    ) -> PhaseContext:
        """Constructs PhaseContext from serialized checkpoint snapshot."""
        ctx = PhaseContext(
            cycle_id=str(data["cycle_id"]),
            workspace_dir=workspace_dir,
            raw_records=list(data.get("raw_records", [])),
            processed_records=list(data.get("processed_records", [])),
            errors=list(data.get("errors", [])),
            state=dict(data.get("state", {})),
        )
        # Restore phase statuses
        raw_statuses = data.get("phase_statuses", {})
        for p_str, s_str in raw_statuses.items():
            try:
                ctx.phase_statuses[IntelligencePhase(p_str)] = PhaseStatus(s_str)
            except ValueError:
                continue

        # Restore products
        for p_dict in data.get("products", []):
            try:
                ctx.products.append(IntelligenceProduct(**p_dict))
            except Exception:
                continue

        # Restore hypotheses
        for h_dict in data.get("hypotheses", []):
            try:
                status_val = HypothesisStatus(h_dict.get("status", "formulated"))
                hypo = Hypothesis(
                    hypo_id=h_dict["hypo_id"],
                    statement=h_dict["statement"],
                    target_topics=h_dict.get(
                        "target_topics", h_dict.get("domain_topics", [])
                    ),
                    status=status_val,
                    confidence_score=h_dict.get("confidence_score", 0.5),
                    formulated_at=h_dict.get("formulated_at", ""),
                )
                ctx.hypotheses.append(hypo)
            except Exception:
                continue

        if "directive" in data:
            ctx.directive = IntelligenceDirective(**data["directive"])
        if "telemetry" in data:
            ctx.telemetry = FeedbackTelemetry(**data["telemetry"])

        return ctx

    def _apply_event_to_context(self, ctx: PhaseContext, ev: OrchestratorEvent) -> None:
        """Applies a single historical event to mutate PhaseContext state."""
        t = ev.event_type
        p = ev.payload

        if t == EventType.PHASE_STARTED:
            phase_val = p.get("phase")
            if phase_val:
                ctx.phase_statuses[IntelligencePhase(phase_val)] = PhaseStatus.RUNNING
        elif t == EventType.PHASE_COMPLETED:
            phase_val = p.get("phase")
            if phase_val:
                ctx.phase_statuses[IntelligencePhase(phase_val)] = PhaseStatus.COMPLETED
        elif t == EventType.RECORD_HARVESTED:
            recs = p.get("records", [])
            ctx.raw_records.extend(recs)
        elif t == EventType.RECORD_PROCESSED:
            recs = p.get("records", [])
            ctx.processed_records.extend(recs)
        elif t == EventType.PRODUCT_PUBLISHED:
            prod_data = p.get("product")
            if prod_data:
                ctx.products.append(IntelligenceProduct(**prod_data))

    def replay_cycle(self, cycle_id: str, workspace_dir: str) -> Optional[PhaseContext]:
        """Replays all events (starting from snapshot if available) to rebuild PhaseContext."""
        cp_path = self._get_checkpoint_path(cycle_id)
        events = self.read_events(cycle_id)

        if not os.path.isfile(cp_path) and not events:
            return None

        ctx: PhaseContext
        if os.path.isfile(cp_path):
            with open(cp_path, "r", encoding="utf-8") as f:
                cp_data = json.load(f)
            ctx = self._restore_from_checkpoint_dict(cp_data, workspace_dir)
        else:
            ctx = PhaseContext(cycle_id=cycle_id, workspace_dir=workspace_dir)

        # Apply events
        for ev in events:
            self._apply_event_to_context(ctx, ev)

        return ctx

    def list_active_cycles(self) -> List[Dict[str, Any]]:
        """Lists cycles recorded in WAL and their latest state summary."""
        if not os.path.isdir(self.wal_dir):
            return []

        cycles: List[Dict[str, Any]] = []
        for filename in os.listdir(self.wal_dir):
            if filename.endswith(".wal.jsonl"):
                cid = filename[:-10]
                events = self.read_events(cid)
                if not events:
                    continue
                first_ev = events[0]
                last_ev = events[-1]
                is_completed = any(
                    e.event_type == EventType.CYCLE_COMPLETED for e in events
                )
                is_failed = any(e.event_type == EventType.CYCLE_FAILED for e in events)
                status = (
                    "completed"
                    if is_completed
                    else ("failed" if is_failed else "in_progress")
                )

                cycles.append(
                    {
                        "cycle_id": cid,
                        "status": status,
                        "started_at": first_ev.timestamp,
                        "last_event_at": last_ev.timestamp,
                        "total_events": len(events),
                    }
                )
        return sorted(cycles, key=lambda c: str(c["started_at"]), reverse=True)

    def purge_cycle_wal(self, cycle_id: str) -> None:
        """Removes WAL and checkpoint files for a completed cycle."""
        wal_path = self._get_wal_path(cycle_id)
        cp_path = self._get_checkpoint_path(cycle_id)
        if os.path.isfile(wal_path):
            os.remove(wal_path)
        if os.path.isfile(cp_path):
            os.remove(cp_path)
