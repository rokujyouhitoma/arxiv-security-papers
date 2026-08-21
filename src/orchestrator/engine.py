"""Universal Autonomous Intelligence Lifecycle Orchestrator Engine.

Integrates the 6 intelligence phases (Planning, Collection, Processing,
Analysis, Dissemination, Evaluation) into an autonomous self-adapting closed loop.
"""

from datetime import datetime, timezone
from typing import Dict, List, Optional

from orchestrator.analysis.synthesizer import AnalysisSynthesizer
from orchestrator.contracts import IntelligenceProduct, PhaseContext
from orchestrator.dissemination.distributor import DisseminationDistributor
from orchestrator.feedback.evaluator import FeedbackEvaluator
from orchestrator.harvest.coordinator import HarvestCoordinator
from orchestrator.pir.manager import PIRManager
from orchestrator.pir.models import PIRRequirement
from orchestrator.processing.processor import ProcessingCoordinator
from orchestrator.workflow.saga import SagaCoordinator


class UniversalIntelligenceOrchestrator:
    """Central domain-agnostic orchestrator executing the 6-phase intelligence lifecycle."""

    def __init__(self, workspace_dir: str = ".") -> None:
        self.workspace_dir = workspace_dir
        self.pir_manager = PIRManager()
        self.harvest_coordinator = HarvestCoordinator()
        self.processing_coordinator = ProcessingCoordinator()
        self.analysis_synthesizer = AnalysisSynthesizer()
        self.dissemination_distributor = DisseminationDistributor()
        self.feedback_evaluator = FeedbackEvaluator()
        self.cycle_history: List[PhaseContext] = []

    def register_pir(
        self,
        req_id: str,
        title: str,
        description: str,
        target_topics: List[str],
        priority_score: float = 1.0,
    ) -> PIRRequirement:
        """Convenience method to register a Priority Intelligence Requirement."""
        req = PIRRequirement(
            req_id=req_id,
            title=title,
            description=description,
            target_topics=target_topics,
            priority_score=priority_score,
        )
        self.pir_manager.register_requirement(req)
        return req

    def record_query_feedback(
        self, query: str, topic: str, ndcg_score: float, hits_count: int
    ) -> None:
        """Feeds client usage and search accuracy back into the feedback loop."""
        self.feedback_evaluator.record_query_event(
            query=query, topic=topic, ndcg_score=ndcg_score, hits_count=hits_count
        )

    def run_cycle(self, cycle_id: Optional[str] = None) -> PhaseContext:
        """Executes a single transactional intelligence cycle across all 6 phases."""
        if not cycle_id:
            cycle_id = f"cycle_{datetime.now(timezone.utc).strftime('%Y%m%d_%H%M%S')}"

        context = PhaseContext(cycle_id=cycle_id, workspace_dir=self.workspace_dir)
        saga = SagaCoordinator()

        # Step 1: Planning & Direction
        context = saga.execute_phase_safely(self.pir_manager, context)
        if context.errors:
            self.cycle_history.append(context)
            return context

        # Step 2: Collection
        context = saga.execute_phase_safely(self.harvest_coordinator, context)
        if context.errors:
            self.cycle_history.append(context)
            return context

        # Step 3: Processing & Exploitation
        context = saga.execute_phase_safely(self.processing_coordinator, context)
        if context.errors:
            self.cycle_history.append(context)
            return context

        # Step 4: Analysis & Production
        context = saga.execute_phase_safely(self.analysis_synthesizer, context)
        if context.errors:
            self.cycle_history.append(context)
            return context

        # Step 5: Dissemination & Integration
        context = saga.execute_phase_safely(self.dissemination_distributor, context)
        if context.errors:
            self.cycle_history.append(context)
            return context

        # Step 6: Feedback & Evaluation
        context = saga.execute_phase_safely(self.feedback_evaluator, context)
        if context.errors:
            self.cycle_history.append(context)
            return context

        # Closed-Loop Self-Adapting Feedback Step (Update PIR weights for next cycle)
        if context.telemetry:
            self.pir_manager.update_weights_from_feedback(
                usage_counts=context.telemetry.frequent_topics,
                knowledge_gaps=context.telemetry.knowledge_gaps,
                topic_drifts=context.telemetry.topic_drift_scores,
            )

        self.cycle_history.append(context)
        return context

    def get_published_products(self) -> List[IntelligenceProduct]:
        """Returns all published intelligence products across cycles."""
        return self.dissemination_distributor.get_published_products()

    def get_current_topic_weights(self) -> Dict[str, float]:
        """Returns current topic priority distribution."""
        return self.pir_manager.get_weights()
