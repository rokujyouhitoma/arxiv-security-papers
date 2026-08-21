"""PIR (Priority Intelligence Requirements) data models."""

from dataclasses import dataclass, field
from datetime import datetime, timezone
from typing import Any, Dict, List


@dataclass
class PIRRequirement:
    """Represents a Priority Intelligence Requirement formulated by decision-makers."""

    req_id: str
    title: str
    description: str
    target_topics: List[str]
    specific_requirements: List[str] = field(default_factory=list)  # SIRs
    priority_score: float = 1.0  # Normalized 0.0 to 1.0
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

    def normalize(self) -> None:
        """Normalizes all positive weights to sum to 1.0."""
        total = sum(max(0.0, w) for w in self.weights.values())
        if total > 0.0:
            for k in list(self.weights.keys()):
                self.weights[k] = max(0.0, self.weights[k]) / total
        elif self.weights:
            equal_val = 1.0 / len(self.weights)
            for k in list(self.weights.keys()):
                self.weights[k] = equal_val
