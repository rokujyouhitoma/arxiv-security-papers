"""Write-Ahead Log (WAL) & Event Sourcing State Replay Engine."""

import json
import os
import uuid
from dataclasses import asdict, dataclass, is_dataclass
from datetime import datetime, timezone
from enum import Enum
from typing import Any, Dict, List, Optional


class EventType(str, Enum):
    """Lifecycle event types recorded into the WAL stream."""

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
    """An immutable event record written to the WAL."""

    event_id: str
    cycle_id: str
    timestamp: str
    event_type: EventType
    payload: Dict[str, Any]

    def to_json_line(self) -> str:
        """Serializes event to a single JSON line string."""
        data = {
            "event_id": self.event_id,
            "cycle_id": self.cycle_id,
            "timestamp": self.timestamp,
            "event_type": self.event_type.value,
            "payload": self.payload,
        }
        return json.dumps(data, ensure_ascii=False)

    @classmethod
    def from_json_line(cls, line: str) -> "OrchestratorEvent":
        """Deserializes event from a JSON line string."""
        raw = json.loads(line)
        return cls(
            event_id=raw["event_id"],
            cycle_id=raw["cycle_id"],
            timestamp=raw["timestamp"],
            event_type=EventType(raw["event_type"]),
            payload=raw.get("payload", {}),
        )


class OrchestratorWAL:
    """Manages append-only event logging, snapshot checkpoints, and state replay."""

    def __init__(self, wal_dir: str = "outputs/wal") -> None:
        self.wal_dir = os.path.abspath(wal_dir)
        os.makedirs(self.wal_dir, exist_ok=True)

    def _get_wal_path(self, cycle_id: str) -> str:
        safe_id = cycle_id.replace("/", "_")
        return os.path.join(self.wal_dir, f"{safe_id}.wal.jsonl")

    def _get_checkpoint_path(self, cycle_id: str) -> str:
        safe_id = cycle_id.replace("/", "_")
        return os.path.join(self.wal_dir, f"{safe_id}.checkpoint.json")

    def append_event(
        self,
        cycle_id: str,
        event_type: EventType,
        payload: Optional[Dict[str, Any]] = None,
    ) -> OrchestratorEvent:
        """Appends a new immutable event to the cycle's WAL file with fsync."""
        event = OrchestratorEvent(
            event_id=f"ev_{uuid.uuid4().hex[:12]}",
            cycle_id=cycle_id,
            timestamp=datetime.now(timezone.utc).isoformat(),
            event_type=event_type,
            payload=payload or {},
        )

        wal_path = self._get_wal_path(cycle_id)
        with open(wal_path, "a", encoding="utf-8") as f:
            f.write(event.to_json_line() + "\n")
            f.flush()
            os.fsync(f.fileno())

        return event

    def read_events(self, cycle_id: str) -> List[OrchestratorEvent]:
        """Reads all events for a given cycle from its WAL file."""
        wal_path = self._get_wal_path(cycle_id)
        if not os.path.isfile(wal_path):
            return []

        events: List[OrchestratorEvent] = []
        with open(wal_path, "r", encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if line:
                    try:
                        events.append(OrchestratorEvent.from_json_line(line))
                    except Exception:
                        continue
        return events

    def create_checkpoint(self, context: Any) -> str:
        """Atomically saves a serialized snapshot of context state."""
        cycle_id = getattr(context, "cycle_id", "unknown_cycle")
        cp_path = self._get_checkpoint_path(cycle_id)
        temp_path = f"{cp_path}.tmp"

        payload = self._serialize_context(context)

        with open(temp_path, "w", encoding="utf-8") as f:
            json.dump(payload, f, ensure_ascii=False, indent=2)
            f.flush()
            os.fsync(f.fileno())

        os.replace(temp_path, cp_path)

        self.append_event(
            cycle_id=cycle_id,
            event_type=EventType.CHECKPOINT_CREATED,
            payload={"checkpoint_file": cp_path},
        )
        return cp_path

    def _serialize_dict(self, d: Dict[Any, Any]) -> Dict[str, Any]:
        """Serializes dictionary keys and values."""
        res: Dict[str, Any] = {}
        for k, v in d.items():
            key_str = k.value if hasattr(k, "value") else str(k)
            val_str = v.value if hasattr(v, "value") else v
            res[key_str] = val_str
        return res

    def _serialize_list(self, lst: List[Any]) -> List[Any]:
        """Serializes list items."""
        return [
            (
                asdict(item)
                if (is_dataclass(item) and not isinstance(item, type))
                else item
            )
            for item in lst
        ]

    def _serialize_value(self, val: Any) -> Any:
        """Serializes a single object, list, or dataclass."""
        if isinstance(val, dict):
            return self._serialize_dict(val)
        if isinstance(val, list):
            return self._serialize_list(val)
        if is_dataclass(val) and not isinstance(val, type):
            return asdict(val)
        return val

    def _serialize_context(self, context: Any) -> Dict[str, Any]:
        """Converts context object to a JSON-serializable dictionary."""
        if hasattr(context, "__dict__"):
            return {k: self._serialize_value(v) for k, v in context.__dict__.items()}
        return {"cycle_id": getattr(context, "cycle_id", "unknown")}

    def _load_initial_data(self, cycle_id: str) -> Optional[Dict[str, Any]]:
        cp_path = self._get_checkpoint_path(cycle_id)
        if not os.path.isfile(cp_path):
            return None
        try:
            with open(cp_path, "r", encoding="utf-8") as f:
                return json.load(f)
        except Exception:
            return None

    def replay_cycle(self, cycle_id: str, workspace_dir: str = ".") -> Optional[Any]:
        """Reconstructs context by loading latest snapshot and replaying remaining events."""
        events = self.read_events(cycle_id)
        if not events:
            return None

        from intelligence.contracts import (
            Hypothesis,
            IntelligencePhase,
            IntelligenceProduct,
            PhaseContext,
            PhaseStatus,
        )

        ctx = PhaseContext(cycle_id=cycle_id, workspace_dir=workspace_dir)
        initial_data = self._load_initial_data(cycle_id)
        if initial_data:
            self._apply_dict_to_context(ctx, initial_data)

        for ev in events:
            self._apply_event_to_context(
                ctx, ev, IntelligencePhase, PhaseStatus, IntelligenceProduct, Hypothesis
            )

        return ctx

    def _restore_statuses(self, ctx: Any, statuses_dict: Dict[str, Any]) -> None:
        """Restores phase statuses from dict."""
        from intelligence.contracts import IntelligencePhase, PhaseStatus

        for p_str, s_str in statuses_dict.items():
            try:
                ctx.phase_statuses[IntelligencePhase(p_str)] = PhaseStatus(s_str)
            except ValueError:
                continue

    def _restore_hypotheses_list(
        self, ctx: Any, raw_list: List[Dict[str, Any]]
    ) -> None:
        """Restores hypotheses list from dicts."""
        from intelligence.contracts import Hypothesis, HypothesisStatus

        for h_dict in raw_list:
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

    def _restore_directive_and_telemetry(self, ctx: Any, data: Dict[str, Any]) -> None:
        from intelligence.contracts import FeedbackTelemetry, IntelligenceDirective

        if data.get("directive"):
            try:
                ctx.directive = IntelligenceDirective(**data["directive"])
            except Exception:
                pass
        if data.get("telemetry"):
            try:
                ctx.telemetry = FeedbackTelemetry(**data["telemetry"])
            except Exception:
                pass

    def _apply_dict_to_context(self, ctx: Any, data: Dict[str, Any]) -> None:
        """Restores context attributes from serialized dictionary."""
        from intelligence.contracts import IntelligenceProduct

        ctx.raw_records = data.get("raw_records", [])
        ctx.processed_records = data.get("processed_records", [])
        ctx.errors = data.get("errors", [])
        ctx.state = data.get("state", {})

        self._restore_statuses(ctx, data.get("phase_statuses", {}))

        for p_dict in data.get("products", []):
            try:
                ctx.products.append(IntelligenceProduct(**p_dict))
            except Exception:
                continue

        self._restore_hypotheses_list(ctx, data.get("hypotheses", []))
        self._restore_directive_and_telemetry(ctx, data)

    def _apply_phase_event(
        self,
        ctx: Any,
        t: EventType,
        p: Dict[str, Any],
        IntelligencePhase: Any,
        PhaseStatus: Any,
    ) -> None:
        phase_val = p.get("phase") or p.get("failed_phase")
        if not phase_val:
            return
        status_map = {
            EventType.PHASE_STARTED: PhaseStatus.RUNNING,
            EventType.PHASE_COMPLETED: PhaseStatus.COMPLETED,
            EventType.CYCLE_FAILED: PhaseStatus.FAILED,
        }
        status = status_map.get(t)
        if status:
            ctx.phase_statuses[IntelligencePhase(phase_val)] = status

    def _apply_event_to_context(
        self,
        ctx: Any,
        ev: OrchestratorEvent,
        IntelligencePhase: Any,
        PhaseStatus: Any,
        IntelligenceProduct: Any,
        Hypothesis: Any,
    ) -> None:
        """Applies a single historical event to mutate PhaseContext state."""
        t = ev.event_type
        p = ev.payload

        if t in (
            EventType.PHASE_STARTED,
            EventType.PHASE_COMPLETED,
            EventType.CYCLE_FAILED,
        ):
            self._apply_phase_event(ctx, t, p, IntelligencePhase, PhaseStatus)
        elif t == EventType.RECORD_HARVESTED:
            ctx.raw_records.extend(p.get("records", []))
        elif t == EventType.RECORD_PROCESSED:
            ctx.processed_records.extend(p.get("records", []))

    def _calculate_cycle_status(self, events: List[OrchestratorEvent]) -> str:
        if any(e.event_type == EventType.CYCLE_COMPLETED for e in events):
            return "completed"
        if any(e.event_type == EventType.CYCLE_FAILED for e in events):
            return "failed"
        return "in_progress"

    def _build_cycle_meta(self, cid: str) -> Optional[Dict[str, Any]]:
        events = self.read_events(cid)
        if not events:
            return None
        return {
            "cycle_id": cid,
            "status": self._calculate_cycle_status(events),
            "total_events": len(events),
            "started_at": events[0].timestamp,
            "last_updated": events[-1].timestamp,
        }

    def list_active_cycles(self) -> List[Dict[str, Any]]:
        """Lists metadata of all tracked WAL cycles in the wal directory."""
        if not os.path.exists(self.wal_dir):
            return []

        cycles: List[Dict[str, Any]] = []
        for f in os.listdir(self.wal_dir):
            if f.endswith(".wal.jsonl"):
                meta = self._build_cycle_meta(f[:-10])
                if meta:
                    cycles.append(meta)

        return sorted(cycles, key=lambda x: str(x["started_at"]), reverse=True)

    def purge_cycle_wal(self, cycle_id: str) -> None:
        """Purges WAL log and checkpoint file for a given cycle."""
        wal_p = self._get_wal_path(cycle_id)
        cp_p = self._get_checkpoint_path(cycle_id)
        if os.path.isfile(wal_p):
            os.remove(wal_p)
        if os.path.isfile(cp_p):
            os.remove(cp_p)
