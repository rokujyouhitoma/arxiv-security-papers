"""Intelligence lifecycle domain contracts, models, and protocols."""

from dataclasses import dataclass, field
from datetime import datetime, timezone
from enum import Enum
from typing import Any, Dict, List, Optional, Protocol, runtime_checkable


class IntelligencePhase(str, Enum):
    """The 6 sequential phases of the closed-loop intelligence lifecycle."""

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
    confidence_score: float = 0.5
    okf_references: List[str] = field(default_factory=list)
    content_markdown: str = ""
    created_at: str = field(
        default_factory=lambda: datetime.now(timezone.utc).isoformat()
    )
    metadata: Dict[str, Any] = field(default_factory=dict)


@dataclass
class FeedbackTelemetry:
    """Evaluation telemetry collected during Phase 6 (Feedback & Evaluation)."""

    telemetry_id: str
    ndcg_at_k: float = 0.0
    mean_average_precision: float = 0.0
    zero_hit_queries: List[str] = field(default_factory=list)
    frequent_topics: Dict[str, int] = field(default_factory=dict)
    topic_drift_scores: Dict[str, float] = field(default_factory=dict)
    knowledge_gaps: Dict[str, float] = field(default_factory=dict)
    recorded_at: str = field(
        default_factory=lambda: datetime.now(timezone.utc).isoformat()
    )
    metadata: Dict[str, Any] = field(default_factory=dict)


class HypothesisStatus(str, Enum):
    """Lifecycle status of an intelligence hypothesis."""

    FORMULATED = "formulated"  # Newly generated proposition
    INVESTIGATING = "investigating"  # In-progress deep evidence collection
    SUPPORTED = "supported"  # Sufficient empirical/academic proof found (>= 0.70)
    REFUTED = "refuted"  # Proven false or mitigated by strong defenses (<= 0.30)
    INCONCLUSIVE = "inconclusive"  # Conflicting or insufficient evidence


@dataclass
class HypothesisEvidence:
    """Empirical or academic evidence item tied to a hypothesis."""

    evidence_id: str
    paper_id: str
    excerpt: str
    polarity: str  # 'support' or 'refute'
    relevance_score: float = 1.0
    recorded_at: str = field(
        default_factory=lambda: datetime.now(timezone.utc).isoformat()
    )
    metadata: Dict[str, Any] = field(default_factory=dict)


@dataclass
class Hypothesis:
    """Security proposition formulated and verified through evidence collection."""

    hypo_id: str
    statement: str
    target_topics: List[str]
    confidence_score: float = 0.5  # 0.0 (fully refuted) to 1.0 (fully supported)
    status: HypothesisStatus = HypothesisStatus.FORMULATED
    supporting_evidence: List[HypothesisEvidence] = field(default_factory=list)
    refuting_evidence: List[HypothesisEvidence] = field(default_factory=list)
    formulated_at: str = field(
        default_factory=lambda: datetime.now(timezone.utc).isoformat()
    )
    updated_at: str = field(
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
    hypotheses: List[Hypothesis] = field(default_factory=list)
    telemetry: Optional[FeedbackTelemetry] = None
    errors: List[Dict[str, Any]] = field(default_factory=list)
    state: Dict[str, Any] = field(default_factory=dict)
    started_at: str = field(
        default_factory=lambda: datetime.now(timezone.utc).isoformat()
    )


@runtime_checkable
class IntelligencePhaseProtocol(Protocol):
    """Protocol implemented by each lifecycle phase coordinator."""

    @property
    def phase_type(self) -> IntelligencePhase:
        """Returns the specific phase this coordinator executes."""
        ...

    def execute(self, context: PhaseContext) -> PhaseContext:
        """Executes the phase's core intelligence logic."""
        ...

    def compensate(self, context: PhaseContext) -> None:
        """Compensates/rolls back changes if downstream phases fail."""
        ...


@runtime_checkable
class PIRManagerProtocol(Protocol):
    """Protocol for 3-Horizon Priority Intelligence Requirements (PIR) managers."""

    def create_directive(self, directive_id: str) -> IntelligenceDirective:
        """Issues an operational intelligence directive for Phase 1."""
        ...

    def get_weights(self) -> Dict[str, float]:
        """Returns the current topic weight vector."""
        ...



@runtime_checkable
class CredibilityEngineProtocol(Protocol):
    """Protocol for NATO STANAG Admiralty credibility evaluation engines."""

    def evaluate_source(
        self, source_type: str, metadata: Optional[Dict[str, Any]] = None
    ) -> tuple[Any, str]:
        """Evaluates reliability grade of an intelligence source."""
        ...

    def evaluate_content(
        self, text: str, metadata: Optional[Dict[str, Any]] = None
    ) -> tuple[Any, str]:
        """Calculates information credibility rating."""
        ...


@runtime_checkable
class SynthesizerProtocol(Protocol):
    """Protocol for multi-tier intelligence product synthesizers."""

    def synthesize_products(
        self,
        processed_records: List[Dict[str, Any]],
        cycle_id: str,
        hypothesis_engine: Optional[Any] = None,
    ) -> List[IntelligenceProduct]:
        """Synthesizes structured intelligence products from processed records."""
        ...

