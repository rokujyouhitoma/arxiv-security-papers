#!/usr/bin/env python3
"""
MITRE ATT&CK CTI (Cyber Threat Intelligence) Integration Package.
Provides ingestion, STIX parsing, SQLite catalog storage, unified query registry,
pure-Python STIX 2.1 inference, ATT&CK Navigator export, and PropertyGraphEngine persistence.
Pure Python, Zero External Dependencies.
"""

from __future__ import annotations

from .graph_bridge import (
    batch_sync_papers_to_graph,
    find_papers_for_technique,
    find_techniques_for_paper,
    sync_cti_inferences_to_graph,
)
from .inference import InferenceEvidence, InferredTechnique, TechniqueInferenceEngine
from .navigator import (
    NavigatorLayerConfig,
    export_navigator_file,
    generate_navigator_layer,
)
from .parser import STIXCTIParser
from .registry import MITRECTIRegistry
from .stix_model import (
    AttackPattern,
    CourseOfAction,
    StixBundle,
    StixRelationship,
    generate_stix_id,
)
from .storage import CTICatalogStorage
from .sync import CTISyncManager

__all__ = [
    "AttackPattern",
    "CourseOfAction",
    "CTICatalogStorage",
    "CTISyncManager",
    "InferenceEvidence",
    "InferredTechnique",
    "MITRECTIRegistry",
    "NavigatorLayerConfig",
    "STIXCTIParser",
    "StixBundle",
    "StixRelationship",
    "TechniqueInferenceEngine",
    "batch_sync_papers_to_graph",
    "export_navigator_file",
    "find_papers_for_technique",
    "find_techniques_for_paper",
    "generate_navigator_layer",
    "generate_stix_id",
    "sync_cti_inferences_to_graph",
]
