#!/usr/bin/env python3
"""
PRIMUS CTI Precision Mapping Package.
Provides CTI-RCM (Root Cause Mapping to CWE), CTI-VSP (Vulnerability Severity Prediction to CVSS v3.1),
CTI-ATE (Attack Technique Extraction to ATT&CK/ATLAS), and Provenance Tiering (Gold/Silver).
"""

from .ate import AttackTechniqueExtractor
from .provenance import ProvenanceRecord, ProvenanceTier, assign_provenance
from .rcm import RootCauseMapper
from .vsp import CVSSPrediction, VulnerabilitySeverityPredictor, roundup

__all__ = [
    "AttackTechniqueExtractor",
    "CVSSPrediction",
    "ProvenanceRecord",
    "ProvenanceTier",
    "RootCauseMapper",
    "VulnerabilitySeverityPredictor",
    "assign_provenance",
    "roundup",
]
