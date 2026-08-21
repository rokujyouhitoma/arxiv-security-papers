"""Universal Intelligence Orchestrator common contracts and protocols.

Defines the phase abstractions, context carriers, directives, and protocols
governing the 6-phase universal intelligence lifecycle.
"""

from dataclasses import dataclass, field
from datetime import datetime, timezone
from enum import Enum
from typing import Any, Dict, List, Optional, Protocol, runtime_checkable


class IntelligencePhase(str, Enum):
    """6 phases of the universal intelligence lifecycle."""

    PLANNING = "planning"
    COLLECTION = "collection"
    PROCESSING = "processing"
    ANALYSIS = "analysis"
    DISSEMINATION = "dissemination"
    EVALUATION = "evaluation"


class PhaseStatus(str, Enum):
    """Execution status of an individual phase or lifecycle task."""

    PENDING = "pending"
    RUNNING = "running"
    COMPLETED = "completed"
    FAILED = "failed"
    COMPENSATED = "compensated"


@dataclass
class IntelligenceDirective:
    """Operational directive issued during Phase 1 (Planning & Direction)."""

    directive_id: str
    target_topics: List[str]
    topic_weights: Dict[str, float]
    crawl_quotas: Dict[str, int]
    priority_level: int = 1
    created_at: str = field(
        default_factory=lambda: datetime.now(timezone.utc).isoformat()
    )
    metadata: Dict[str, Any] = field(default_factory=dict)


@dataclass
class IntelligenceProduct:
    """Actionable intelligence synthesized during Phase 4 (Analysis & Production)."""

    product_id: str
    title: str
    summary: str
    tier: (
        str  # e.g., '01_per_run', '02_daily', '03_monthly', '04_quarterly', '05_annual'
    )
    topic_tags: List[str]
    source_count: int
    confidence_score: float
    okf_references: List[str] = field(default_factory=list)
    created_at: str = field(
        default_factory=lambda: datetime.now(timezone.utc).isoformat()
    )
    metadata: Dict[str, Any] = field(default_factory=dict)


@dataclass
class FeedbackTelemetry:
    """Evaluation telemetry collected during Phase 6 (Feedback & Evaluation)."""

    telemetry_id: str
    ndcg_at_k: float
    mean_average_precision: float
    zero_hit_queries: List[str]
    frequent_topics: Dict[str, int]
    topic_drift_scores: Dict[str, float]
    knowledge_gaps: Dict[str, float]
    recorded_at: str = field(
        default_factory=lambda: datetime.now(timezone.utc).isoformat()
    )
    metadata: Dict[str, Any] = field(default_factory=dict)


@dataclass
class PhaseContext:
    """Carrier context flowing across the 6 intelligence phases."""

    cycle_id: str
    workspace_dir: str
    phase_statuses: Dict[IntelligencePhase, PhaseStatus] = field(default_factory=dict)
    directive: Optional[IntelligenceDirective] = None
    raw_records: List[Dict[str, Any]] = field(default_factory=list)
    processed_records: List[Dict[str, Any]] = field(default_factory=list)
    products: List[IntelligenceProduct] = field(default_factory=list)
    telemetry: Optional[FeedbackTelemetry] = None
    errors: List[Dict[str, Any]] = field(default_factory=list)
    state: Dict[str, Any] = field(default_factory=dict)
    started_at: str = field(
        default_factory=lambda: datetime.now(timezone.utc).isoformat()
    )


@runtime_checkable
class IntelligencePhaseProtocol(Protocol):
    """Protocol implemented by each phase executor in the Intelligence Cycle."""

    @property
    def phase_type(self) -> IntelligencePhase:
        """Returns the phase identifier."""
        ...

    def execute(self, context: PhaseContext) -> PhaseContext:
        """Executes the phase logic and updates the carrier context."""
        ...

    def compensate(self, context: PhaseContext) -> None:
        """Executes compensating transactions if a downstream error occurs (Saga)."""
        ...
