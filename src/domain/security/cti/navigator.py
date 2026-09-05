#!/usr/bin/env python3
"""
MITRE ATT&CK Navigator Layer v4.5 JSON Generator & Exporter.
Serializes CTI paper inferences into visual heatmap layers.
Pure Python, Zero External Dependencies.
"""

from __future__ import annotations

import json
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Dict, List, Optional

from .inference import InferredTechnique

# Heatmap color thresholds based on paper citation frequency
COLOR_LOW = "#ffd966"  # Yellow (1 paper)
COLOR_MEDIUM = "#f6b26b"  # Orange (2-4 papers)
COLOR_HIGH = "#e06666"  # Red (5+ papers)


@dataclass
class NavigatorLayerConfig:
    """Configuration options for ATT&CK Navigator Layer v4.5."""

    name: str = "arXiv Security Papers - Coverage Layer"
    domain: str = "enterprise-attack"
    version: str = "4.5"
    attack_version: str = "14"
    description: str = "Auto-generated ATT&CK coverage layer from arXiv research papers"
    min_score: float = 0.0
    max_score: float = 10.0
    colors: List[str] = field(
        default_factory=lambda: ["#ffffff", "#ffd966", "#f6b26b", "#e06666"]
    )


def _resolve_color(paper_count: int) -> str:
    """Returns color based on frequency of techniques in papers."""
    if paper_count <= 1:
        return COLOR_LOW
    if paper_count < 5:
        return COLOR_MEDIUM
    return COLOR_HIGH


def _aggregate_technique_papers(
    inferences_by_paper: Dict[str, List[InferredTechnique]],
) -> Dict[str, Dict[str, Any]]:
    """
    Aggregates techniques across multiple papers.
    Returns: tech_id -> {'papers': set(), 'tactic': str, 'max_conf': float}
    """
    aggregated: Dict[str, Dict[str, Any]] = {}
    for paper_id, tech_list in inferences_by_paper.items():
        for tech in tech_list:
            entry = aggregated.setdefault(
                tech.technique_id,
                {"papers": set(), "tactic": tech.tactic, "max_conf": 0.0},
            )
            entry["papers"].add(paper_id)
            if tech.confidence > entry["max_conf"]:
                entry["max_conf"] = tech.confidence
    return aggregated


def _build_technique_entry(
    tech_id: str,
    data: Dict[str, Any],
) -> Dict[str, Any]:
    """Constructs a single technique entry for Navigator JSON."""
    papers = sorted(list(data["papers"]))
    count = len(papers)
    color = _resolve_color(count)
    comment = f"Papers ({count}): " + ", ".join(papers[:10])
    if count > 10:
        comment += f" ... (+{count - 10} more)"

    entry: Dict[str, Any] = {
        "techniqueID": tech_id,
        "score": count,
        "color": color,
        "comment": comment,
        "enabled": True,
        "metadata": [
            {"name": "paper_count", "value": str(count)},
            {"name": "max_confidence", "value": str(round(data["max_conf"], 2))},
        ],
    }
    tactic = data.get("tactic")
    if tactic and tactic != "unknown":
        entry["tactic"] = tactic
    return entry


def generate_navigator_layer(
    inferences_by_paper: Dict[str, List[InferredTechnique]],
    config: Optional[NavigatorLayerConfig] = None,
) -> Dict[str, Any]:
    """
    Generates an ATT&CK Navigator Layer v4.5 compliant dictionary.
    """
    cfg = config or NavigatorLayerConfig()
    aggregated = _aggregate_technique_papers(inferences_by_paper)

    technique_entries: List[Dict[str, Any]] = []
    for tech_id, data in sorted(aggregated.items()):
        entry = _build_technique_entry(tech_id, data)
        technique_entries.append(entry)

    layer: Dict[str, Any] = {
        "name": cfg.name,
        "versions": {
            "attack": cfg.attack_version,
            "navigator": cfg.version,
            "layer": cfg.version,
        },
        "domain": cfg.domain,
        "description": cfg.description,
        "gradient": {
            "colors": cfg.colors,
            "minValue": cfg.min_score,
            "maxValue": cfg.max_score,
        },
        "techniques": technique_entries,
    }
    return layer


def export_navigator_file(layer_dict: Dict[str, Any], output_path: str) -> str:
    """
    Exports the Navigator layer dictionary to a JSON file.
    Creates parent directories if necessary.
    """
    out_file = Path(output_path).resolve()
    out_file.parent.mkdir(parents=True, exist_ok=True)

    with open(out_file, "w", encoding="utf-8") as f:
        json.dump(layer_dict, f, indent=2, ensure_ascii=False)

    return str(out_file)
