"""Universal Autonomous Intelligence Lifecycle Orchestrator Engine.

Integrates the 6 intelligence phases (Planning, Collection, Processing,
Analysis, Dissemination, Evaluation) into an autonomous self-adapting closed loop.
"""

import os
from datetime import datetime, timezone
from typing import Any, Dict, Iterator, List, Optional

from orchestrator.analysis.hypothesis_engine import HypothesisEngine
from orchestrator.analysis.synthesizer import AnalysisSynthesizer
from orchestrator.contracts import (
    Hypothesis,
    HypothesisStatus,
    IntelligencePhase,
    IntelligenceProduct,
    PhaseContext,
    PhaseStatus,
)
from orchestrator.dissemination.distributor import DisseminationDistributor
from orchestrator.feedback.evaluator import FeedbackEvaluator
from orchestrator.harvest.coordinator import HarvestCoordinator
from orchestrator.pir.manager import PIRManager
from orchestrator.pir.models import PIRHorizon, PIRRequirement
from orchestrator.processing.processor import ProcessingCoordinator
from orchestrator.workflow.saga import SagaCoordinator


class UniversalIntelligenceOrchestrator:
    """Central domain-agnostic orchestrator executing the 6-phase intelligence lifecycle."""

    def __init__(self, workspace_dir: str = ".") -> None:
        self.workspace_dir = workspace_dir
        pir_storage = os.path.join(
            workspace_dir, "outputs", "orchestrator", "pir_registry.json"
        )
        hypo_storage = os.path.join(
            workspace_dir, "outputs", "orchestrator", "hypotheses_registry.json"
        )
        self.pir_manager = PIRManager(storage_path=pir_storage, auto_seed=True)
        self.hypothesis_engine = HypothesisEngine(storage_path=hypo_storage)
        self.harvest_coordinator = HarvestCoordinator()
        self.processing_coordinator = ProcessingCoordinator()
        self.analysis_synthesizer = AnalysisSynthesizer(
            hypothesis_engine=self.hypothesis_engine
        )
        self.dissemination_distributor = DisseminationDistributor()
        self.feedback_evaluator = FeedbackEvaluator()
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
            self.pir_manager.adapt_queries_from_telemetry(context.telemetry)

        self.cycle_history.append(context)
        return context

    def stream_cycle(
        self,
        cycle_id: Optional[str] = None,
        chunk_size: int = 20,
        max_buffer_size: int = 10,
    ) -> PhaseContext:
        """Executes an intelligence cycle via streaming DAG with reactive backpressure."""
        from orchestrator.workflow.streaming_dag import (
            BufferPolicy,
            StreamChunk,
            StreamingDAG,
            StreamingTaskNode,
        )

        if not cycle_id:
            cycle_id = (
                f"stream_cycle_{datetime.now(timezone.utc).strftime('%Y%m%d_%H%M%S')}"
            )

        context = PhaseContext(cycle_id=cycle_id, workspace_dir=self.workspace_dir)

        # 1. Phase 1: Planning
        context = self.pir_manager.execute(context)
        if context.errors:
            self.cycle_history.append(context)
            return context

        # 2. Phase 2: Harvest Raw Records
        context = self.harvest_coordinator.execute(context)
        if context.errors:
            self.cycle_history.append(context)
            return context

        # 3. Build Streaming DAG Pipeline
        def make_chunks(
            records: List[Dict[str, Any]],
        ) -> Iterator[StreamChunk[Dict[str, Any]]]:
            seq = 0
            for i in range(0, max(1, len(records)), chunk_size):
                sub = records[i : i + chunk_size]
                if sub:
                    seq += 1
                    yield StreamChunk(
                        chunk_id=f"chunk_{seq}",
                        sequence_no=seq,
                        items=sub,
                    )

        def transform_process(
            chunk: StreamChunk[Dict[str, Any]],
        ) -> StreamChunk[Dict[str, Any]]:
            processed_items = [
                self.processing_coordinator.process_record(r) for r in chunk.items
            ]
            return StreamChunk(
                chunk_id=f"proc_{chunk.chunk_id}",
                sequence_no=chunk.sequence_no,
                items=processed_items,
            )

        dag = StreamingDAG(high_watermark=0.80, low_watermark=0.30)
        node_entry: StreamingTaskNode[Dict[str, Any], Dict[str, Any]] = (
            StreamingTaskNode(
                node_id="ingest_entry",
                transform_fn=lambda c: c,
                max_buffer_size=max_buffer_size,
                policy=BufferPolicy.BLOCK,
            )
        )
        node_proc: StreamingTaskNode[Dict[str, Any], Dict[str, Any]] = (
            StreamingTaskNode(
                node_id="process_okf_admiralty",
                transform_fn=transform_process,
                max_buffer_size=max_buffer_size,
                policy=BufferPolicy.BLOCK,
            )
        )

        dag.add_node(node_entry)
        dag.add_node(node_proc)
        dag.connect("ingest_entry", "process_okf_admiralty")

        # Execute Stream
        stream_results = dag.run_stream(
            entry_node_id="ingest_entry",
            chunk_iterator=make_chunks(context.raw_records),
        )

        # Aggregate stream output into context
        all_processed: List[Dict[str, Any]] = []
        for out_chunk in stream_results.get("output_chunks", []):
            all_processed.extend(out_chunk.items)

        context.processed_records = all_processed
        context.phase_statuses[IntelligencePhase.PROCESSING] = PhaseStatus.COMPLETED
        context.state["streaming_stats"] = stream_results

        # 4. Phase 4: Analysis & Synthesis
        context = self.analysis_synthesizer.execute(context)

        # 5. Phase 5: Dissemination
        context = self.dissemination_distributor.execute(context)

        # 6. Phase 6: Feedback & Adaptation
        context = self.feedback_evaluator.execute(context)
        if context.telemetry:
            self.pir_manager.update_weights_from_feedback(
                usage_counts=context.telemetry.frequent_topics,
                knowledge_gaps=context.telemetry.knowledge_gaps,
                topic_drifts=context.telemetry.topic_drift_scores,
            )
            self.pir_manager.adapt_queries_from_telemetry(context.telemetry)

        self.cycle_history.append(context)
        return context

    def get_published_products(self) -> List[IntelligenceProduct]:
        """Returns all published intelligence products across cycles."""
        return self.dissemination_distributor.get_published_products()

    def get_current_topic_weights(self) -> Dict[str, float]:
        """Returns current topic priority distribution."""
        return self.pir_manager.get_weights()
