"""Closed-Loop Intelligence System Package.

Orchestrates the 6-phase intelligence lifecycle:
Planning, Collection, Processing, Analysis, Dissemination, and Evaluation.
"""

from intelligence.analysis.synthesizer import AnalysisSynthesizer
from intelligence.cli import build_parser, main, run_cycle_command
from intelligence.contracts import (
    FeedbackTelemetry,
    Hypothesis,
    HypothesisEvidence,
    HypothesisStatus,
    IntelligenceDirective,
    IntelligencePhase,
    IntelligencePhaseProtocol,
    IntelligenceProduct,
    PhaseContext,
    PhaseStatus,
)
from intelligence.dissemination.distributor import DisseminationDistributor
from intelligence.engine import (
    ClosedLoopIntelligenceEngine,
    UniversalIntelligenceOrchestrator,
)
from intelligence.feedback.evaluator import FeedbackEvaluator
from intelligence.harvest.coordinator import HarvestCoordinator
from intelligence.pir.manager import PIRManager
from intelligence.pir.models import PIRHorizon, PIRRequirement, TopicWeightVector
from intelligence.processing.processor import ProcessingCoordinator

__all__ = [
    "ClosedLoopIntelligenceEngine",
    "UniversalIntelligenceOrchestrator",
    "IntelligencePhase",
    "PhaseStatus",
    "PhaseContext",
    "IntelligenceDirective",
    "IntelligenceProduct",
    "Hypothesis",
    "HypothesisEvidence",
    "HypothesisStatus",
    "FeedbackTelemetry",
    "IntelligencePhaseProtocol",
    "PIRManager",
    "PIRRequirement",
    "PIRHorizon",
    "TopicWeightVector",
    "HarvestCoordinator",
    "ProcessingCoordinator",
    "AnalysisSynthesizer",
    "DisseminationDistributor",
    "FeedbackEvaluator",
    "main",
    "build_parser",
    "run_cycle_command",
]
