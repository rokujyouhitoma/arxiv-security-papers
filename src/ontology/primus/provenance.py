#!/usr/bin/env python3
"""
Provenance Tiering and Confidence Scoring for PRIMUS CTI Engine.
Distinguishes Gold Tier (ground-truth/explicit mentions, >=0.85) from
Silver Tier (semantic inference, 0.60..0.85), discarding low-confidence (<0.60) mappings.
"""

from __future__ import annotations

from dataclasses import asdict, dataclass
from enum import Enum
from typing import Any, Dict, Optional


class ProvenanceTier(str, Enum):
    """Classification tiers for extracted CTI security identifiers."""

    GOLD = "gold"
    SILVER = "silver"
    REJECT = "reject"


@dataclass
class ProvenanceRecord:
    """Detailed provenance tracking metadata for an extracted security mapping."""

    mapped_id: str
    category: str
    confidence: float
    evidence_snippet: str
    tier: ProvenanceTier
    source_rule: str = "PRIMUS-v1.0"

    def to_dict(self) -> Dict[str, Any]:
        """Serializes record to clean dictionary representation."""
        data = asdict(self)
        data["tier"] = self.tier.value
        return data


def assign_provenance(
    mapped_id: str,
    category: str,
    confidence: float,
    evidence_snippet: str,
    is_explicit: bool = False,
    source_rule: str = "PRIMUS-v1.0",
) -> Optional[ProvenanceRecord]:
    """
    Evaluates confidence and explicit mention flag to assign Gold, Silver, or Reject tier.
    Rejects items with confidence < 0.60.
    """
    conf = max(0.0, min(1.0, float(confidence)))
    if is_explicit or conf >= 0.85:
        tier = ProvenanceTier.GOLD
    elif conf >= 0.60:
        tier = ProvenanceTier.SILVER
    else:
        tier = ProvenanceTier.REJECT

    if tier == ProvenanceTier.REJECT:
        return None

    return ProvenanceRecord(
        mapped_id=mapped_id,
        category=category,
        confidence=round(conf, 4),
        evidence_snippet=evidence_snippet.strip()[:200],
        tier=tier,
        source_rule=source_rule,
    )
