"""PIR (Priority Intelligence Requirements) data models."""

from dataclasses import dataclass, field
from datetime import datetime, timezone
from enum import Enum
from typing import Any, Dict, List, Optional


class PIRHorizon(str, Enum):
    """Temporal horizon classification for Priority Intelligence Requirements."""

    TACTICAL = "tactical"  # Immediate, high-velocity (0-day, PoC, CVE)
    OPERATIONAL = "operational"  # Medium-term, quarterly (protocol, supply-chain)
    STRATEGIC = "strategic"  # Long-term, macro (post-quantum, AI safety standards)


@dataclass
class PIRRequirement:
    """Represents a Priority Intelligence Requirement formulated by decision-makers."""

    req_id: str
    title: str
    description: str
    target_topics: List[str]
    specific_requirements: List[str] = field(default_factory=list)  # SIRs
    priority_score: float = 1.0  # Normalized 0.0 to 1.0
    horizon: PIRHorizon = PIRHorizon.OPERATIONAL
    escalation_level: int = 0
    escalated_at: Optional[str] = None
    is_active: bool = True
    created_at: str = field(
        default_factory=lambda: datetime.now(timezone.utc).isoformat()
    )
    metadata: Dict[str, Any] = field(default_factory=dict)


@dataclass
class TopicWeightVector:
    """Multi-topic weight distribution guiding harvesting and analysis."""

    weights: Dict[str, float] = field(default_factory=dict)
    updated_at: str = field(
        default_factory=lambda: datetime.now(timezone.utc).isoformat()
    )

    def _normalize_weighted(self, total: float) -> None:
        for k in list(self.weights.keys()):
            self.weights[k] = max(0.0, self.weights[k]) / total

    def _normalize_equal(self) -> None:
        equal_val = 1.0 / len(self.weights)
        for k in list(self.weights.keys()):
            self.weights[k] = equal_val

    def normalize(self) -> None:
        """Normalizes all positive weights to sum to 1.0."""
        total = sum(max(0.0, w) for w in self.weights.values())
        if total > 0.0:
            self._normalize_weighted(total)
        elif self.weights:
            self._normalize_equal()
