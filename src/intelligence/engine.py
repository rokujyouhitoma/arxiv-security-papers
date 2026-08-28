"""Closed-Loop Intelligence Lifecycle Engine."""

import os
from datetime import datetime, timezone
from typing import Any, Dict, List, Optional

from intelligence.analysis.hypothesis_engine import HypothesisEngine
from intelligence.analysis.synthesizer import AnalysisSynthesizer
from intelligence.contracts import (
    Hypothesis,
    HypothesisStatus,
    IntelligencePhase,
    PhaseContext,
    PhaseStatus,
)
from intelligence.dissemination.distributor import DisseminationDistributor
from intelligence.feedback.evaluator import FeedbackEvaluator
from intelligence.harvest.coordinator import HarvestCoordinator
from intelligence.pir.manager import PIRManager
from intelligence.pir.models import PIRHorizon, PIRRequirement
from intelligence.processing.processor import ProcessingCoordinator
from workflow.saga import SagaCoordinator
from workflow.streaming_dag import BufferPolicy, StreamChunk, StreamingDAG
from workflow.wal import EventType, OrchestratorWAL


class ClosedLoopIntelligenceEngine:
    """Central domain engine executing the 6-phase intelligence lifecycle."""

    def __init__(
        self,
        workspace_dir: str = ".",
        wal: Optional[OrchestratorWAL] = None,
        pir_manager: Optional[PIRManager] = None,
        harvest_coordinator: Optional[HarvestCoordinator] = None,
        processing_coordinator: Optional[ProcessingCoordinator] = None,
        hypothesis_engine: Optional[HypothesisEngine] = None,
        analysis_synthesizer: Optional[AnalysisSynthesizer] = None,
        dissemination_distributor: Optional[DisseminationDistributor] = None,
        feedback_evaluator: Optional[FeedbackEvaluator] = None,
    ) -> None:
        self.workspace_dir = os.path.abspath(workspace_dir)
        self.wal = wal or OrchestratorWAL(
            wal_dir=os.path.join(self.workspace_dir, "outputs", "wal")
        )
        pir_storage = os.path.join(
            self.workspace_dir, "outputs", "orchestrator", "pir_registry.json"
        )
        hypo_storage = os.path.join(
            self.workspace_dir, "outputs", "orchestrator", "hypotheses_registry.json"
        )
        self.pir_manager = pir_manager or PIRManager(
            storage_path=pir_storage, auto_seed=True
        )
        self.harvest_coordinator = harvest_coordinator or HarvestCoordinator()
        self.processing_coordinator = processing_coordinator or ProcessingCoordinator()
        self.hypothesis_engine = hypothesis_engine or HypothesisEngine(
            storage_path=hypo_storage
        )
        self.analysis_synthesizer = analysis_synthesizer or AnalysisSynthesizer(
            hypothesis_engine=self.hypothesis_engine
        )
        self.dissemination_distributor = (
            dissemination_distributor or DisseminationDistributor()
        )
        self.feedback_evaluator = feedback_evaluator or FeedbackEvaluator()
        self.cycle_history: List[PhaseContext] = []

    def register_hypothesis(
        self,
        hypo_id: str,
        statement: str,
        target_topics: List[str],
    ) -> Hypothesis:
        """Registers a manual or operator-defined security hypothesis."""
        hypo = Hypothesis(
            hypo_id=hypo_id,
            statement=statement,
            target_topics=target_topics,
            status=HypothesisStatus.FORMULATED,
        )
        return self.hypothesis_engine.register_hypothesis(hypo)

    def list_hypotheses(
        self, status: Optional[HypothesisStatus] = None
    ) -> List[Hypothesis]:
        """Lists active hypotheses tracked by the orchestrator."""
        return self.hypothesis_engine.list_hypotheses(status=status)

    def register_pir(
        self,
        req_id: str,
        title: str,
        description: str,
        target_topics: List[str],
        priority_score: float = 1.0,
        horizon: PIRHorizon = PIRHorizon.OPERATIONAL,
    ) -> PIRRequirement:
        """Convenience method to register a Priority Intelligence Requirement."""
        req = PIRRequirement(
            req_id=req_id,
            title=title,
            description=description,
            target_topics=target_topics,
            priority_score=priority_score,
            horizon=horizon,
        )
        self.pir_manager.register_requirement(req)
        return req

    def escalate_pir(
        self,
        req_id: str,
        reason: str,
        target_horizon: PIRHorizon = PIRHorizon.TACTICAL,
    ) -> bool:
        """Convenience method to escalate a Priority Intelligence Requirement."""
        return self.pir_manager.escalate_requirement(
            req_id=req_id, reason=reason, target_horizon=target_horizon
        )

    def get_current_topic_weights(self) -> Dict[str, float]:
        """Returns current topic priority distribution."""
        return self.pir_manager.get_weights()

    def get_published_products(self) -> List[Any]:
        """Returns all published intelligence products across cycles."""
        return self.dissemination_distributor.get_published_products()

    def record_query_feedback(
        self, query: str, topic: str, ndcg_score: float, hits_count: int
    ) -> None:
        """Feeds client usage and search accuracy back into the feedback loop."""
        self.feedback_evaluator.record_query_event(
            query=query, topic=topic, ndcg_score=ndcg_score, hits_count=hits_count
        )

    def _execute_phase_with_wal(
        self,
        saga: SagaCoordinator,
        phase_executor: Any,
        phase_type: IntelligencePhase,
        context: PhaseContext,
    ) -> PhaseContext:
        """Executes a single phase wrapped with WAL event logging and checkpoints."""
        self.wal.append_event(
            cycle_id=context.cycle_id,
            event_type=EventType.PHASE_STARTED,
            payload={"phase": phase_type.value},
        )
        context = saga.execute_phase_safely(phase_executor, context)
        if context.errors:
            self.wal.append_event(
                cycle_id=context.cycle_id,
                event_type=EventType.CYCLE_FAILED,
                payload={"failed_phase": phase_type.value, "errors": context.errors},
            )
            return context

        self.wal.append_event(
            cycle_id=context.cycle_id,
            event_type=EventType.PHASE_COMPLETED,
            payload={"phase": phase_type.value},
        )
        self.wal.create_checkpoint(context)
        return context

    def run_cycle(self, cycle_id: Optional[str] = None) -> PhaseContext:
        """Executes a single transactional intelligence cycle across all 6 phases with WAL."""
        if not cycle_id:
            cycle_id = f"cycle_{datetime.now(timezone.utc).strftime('%Y%m%d_%H%M%S')}"

        context = PhaseContext(cycle_id=cycle_id, workspace_dir=self.workspace_dir)
        self.wal.append_event(cycle_id=cycle_id, event_type=EventType.CYCLE_STARTED)
        saga = SagaCoordinator()

        phases = [
            (self.pir_manager, IntelligencePhase.PLANNING),
            (self.harvest_coordinator, IntelligencePhase.COLLECTION),
            (self.processing_coordinator, IntelligencePhase.PROCESSING),
            (self.analysis_synthesizer, IntelligencePhase.ANALYSIS),
            (self.dissemination_distributor, IntelligencePhase.DISSEMINATION),
            (self.feedback_evaluator, IntelligencePhase.EVALUATION),
        ]

        for executor, ptype in phases:
            context = self._execute_phase_with_wal(saga, executor, ptype, context)
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
            self.pir_manager.adapt_queries_from_telemetry(context.telemetry)

        self.wal.append_event(cycle_id=cycle_id, event_type=EventType.CYCLE_COMPLETED)
        self.cycle_history.append(context)
        return context

    def resume_cycle(self, cycle_id: str) -> PhaseContext:
        """Replays and resumes an uncompleted or crashed cycle from its WAL state."""
        replayed = self.wal.replay_cycle(cycle_id, self.workspace_dir)
        context = (
            replayed
            if isinstance(replayed, PhaseContext)
            else PhaseContext(cycle_id=cycle_id, workspace_dir=self.workspace_dir)
        )
        saga = SagaCoordinator()

        phases = [
            (self.pir_manager, IntelligencePhase.PLANNING),
            (self.harvest_coordinator, IntelligencePhase.COLLECTION),
            (self.processing_coordinator, IntelligencePhase.PROCESSING),
            (self.analysis_synthesizer, IntelligencePhase.ANALYSIS),
            (self.dissemination_distributor, IntelligencePhase.DISSEMINATION),
            (self.feedback_evaluator, IntelligencePhase.EVALUATION),
        ]

        for executor, ptype in phases:
            status = context.phase_statuses.get(ptype, PhaseStatus.PENDING)
            if status != PhaseStatus.COMPLETED:
                context = self._execute_phase_with_wal(saga, executor, ptype, context)
                if context.errors:
                    self.cycle_history.append(context)
                    return context

        if context.telemetry:
            self.pir_manager.update_weights_from_feedback(
                usage_counts=context.telemetry.frequent_topics,
                knowledge_gaps=context.telemetry.knowledge_gaps,
                topic_drifts=context.telemetry.topic_drift_scores,
            )
            self.pir_manager.adapt_queries_from_telemetry(context.telemetry)

        self.wal.append_event(cycle_id=cycle_id, event_type=EventType.CYCLE_COMPLETED)
        self.cycle_history.append(context)
        return context

    def stream_cycle(
        self,
        cycle_id: Optional[str] = None,
        chunk_size: int = 5,
        buffer_capacity: int = 10,
    ) -> PhaseContext:
        """Executes the intelligence cycle using a reactive streaming DAG with backpressure."""
        if not cycle_id:
            cycle_id = (
                f"stream_cycle_{datetime.now(timezone.utc).strftime('%Y%m%d_%H%M%S')}"
            )

        context = PhaseContext(cycle_id=cycle_id, workspace_dir=self.workspace_dir)

        # 1. Planning Phase
        context = self.pir_manager.execute(context)
        directive = context.directive
        if not directive:
            context.phase_statuses[IntelligencePhase.PLANNING] = PhaseStatus.FAILED
            return context

        # 2. Setup Streaming DAG
        dag: StreamingDAG[Dict[str, Any]] = StreamingDAG()

        def harvest_step(items: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
            records = self.harvest_coordinator.harvest(
                target_topics=directive.target_topics,
                crawl_quotas={t: chunk_size for t in directive.target_topics},
            )
            return records

        def process_step(items: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
            processed = []
            for item in items:
                processed.append(self.processing_coordinator.process_record(item))
            return processed

        dag.add_node(
            "harvest_node",
            harvest_step,
            max_queue_size=buffer_capacity,
            policy=BufferPolicy.BLOCK,
        )
        dag.add_node(
            "process_node",
            process_step,
            max_queue_size=buffer_capacity,
            policy=BufferPolicy.BLOCK,
        )
        dag.add_edge("harvest_node", "process_node")

        init_chunks = [
            StreamChunk(
                chunk_id=f"chunk_{i}",
                items=[{"seed": i}],
                sequence_num=i,
                is_final=(i == 1),
            )
            for i in range(2)
        ]

        final_chunks = dag.execute_pipeline(init_chunks)

        for chunk in final_chunks:
            context.processed_records.extend(chunk.items)

        context.phase_statuses[IntelligencePhase.COLLECTION] = PhaseStatus.COMPLETED
        context.phase_statuses[IntelligencePhase.PROCESSING] = PhaseStatus.COMPLETED

        # 3. Downstream Analysis, Dissemination, Evaluation
        context = self.analysis_synthesizer.execute(context)
        context = self.dissemination_distributor.execute(context)
        context = self.feedback_evaluator.execute(context)

        self.cycle_history.append(context)
        return context
