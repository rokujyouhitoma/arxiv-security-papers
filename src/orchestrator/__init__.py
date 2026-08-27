"""Universal Autonomous Intelligence Lifecycle Orchestration Package.

Provides a domain-agnostic closed-loop intelligence engine orchestrating
Planning, Collection, Processing, Analysis, Dissemination, and Evaluation.
"""

from orchestrator.analysis.synthesizer import AnalysisSynthesizer
from orchestrator.cli import build_parser, main, run_cycle_command
from orchestrator.contracts import (
    FeedbackTelemetry,
    IntelligenceDirective,
    IntelligencePhase,
    IntelligencePhaseProtocol,
    IntelligenceProduct,
    PhaseContext,
    PhaseStatus,
)
from orchestrator.dissemination.distributor import DisseminationDistributor
from orchestrator.engine import UniversalIntelligenceOrchestrator
from orchestrator.feedback.evaluator import FeedbackEvaluator
from orchestrator.harvest.coordinator import HarvestCoordinator
from orchestrator.pir.manager import PIRManager
from orchestrator.pir.models import PIRRequirement, TopicWeightVector
from orchestrator.processing.processor import ProcessingCoordinator
from orchestrator.wal import EventType, OrchestratorEvent, OrchestratorWAL
from orchestrator.workflow.dag import DAGWorkflowEngine
from orchestrator.workflow.saga import SagaCoordinator

__all__ = [
    "UniversalIntelligenceOrchestrator",
    "IntelligencePhase",
    "PhaseStatus",
    "PhaseContext",
    "IntelligenceDirective",
    "IntelligenceProduct",
    "FeedbackTelemetry",
    "IntelligencePhaseProtocol",
    "PIRManager",
    "PIRRequirement",
    "TopicWeightVector",
    "HarvestCoordinator",
    "ProcessingCoordinator",
    "AnalysisSynthesizer",
    "DisseminationDistributor",
    "FeedbackEvaluator",
    "DAGWorkflowEngine",
    "SagaCoordinator",
    "OrchestratorWAL",
    "OrchestratorEvent",
    "EventType",
    "main",
    "build_parser",
    "run_cycle_command",
]
