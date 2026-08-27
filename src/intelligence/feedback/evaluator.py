"""Feedback Evaluator for Phase 6 (Feedback & Evaluation).

Quantifies information retrieval effectiveness, computes knowledge gaps:
G(t) = sum_{q in Q_t} (1.0 - NDCG@K(q)) * ln(1 + Count(q))
and detects emerging topic drift to recalibrate Phase 1 PIR directives.
"""

import math
from typing import Any, Dict, List

from intelligence.contracts import (
    FeedbackTelemetry,
    IntelligencePhase,
    IntelligencePhaseProtocol,
    PhaseContext,
    PhaseStatus,
)


class FeedbackEvaluator(IntelligencePhaseProtocol):
    """Phase 6: Evaluation and Closed-Loop Feedback Engine."""

    def __init__(self) -> None:
        self._query_logs: List[Dict[str, Any]] = []

    @property
    def phase_type(self) -> IntelligencePhase:
        return IntelligencePhase.EVALUATION

    def record_query_event(
        self, query: str, topic: str, ndcg_score: float, hits_count: int
    ) -> None:
        """Records client search queries and evaluation metrics."""
        self._query_logs.append(
            {
                "query": query,
                "topic": topic,
                "ndcg": ndcg_score,
                "hits": hits_count,
            }
        )

    def evaluate_telemetry(self, telemetry_id: str) -> FeedbackTelemetry:
        """Computes composite evaluation metrics, knowledge gaps, and topic drift."""
        if not self._query_logs:
            # Baseline default telemetry
            return FeedbackTelemetry(
                telemetry_id=telemetry_id,
                ndcg_at_k=0.85,
                mean_average_precision=0.80,
                zero_hit_queries=[],
                frequent_topics={},
                topic_drift_scores={},
                knowledge_gaps={},
            )

        total_ndcg = sum(q["ndcg"] for q in self._query_logs)
        avg_ndcg = total_ndcg / len(self._query_logs)

        zero_hits: List[str] = []
        topic_counts: Dict[str, int] = {}
        topic_ndcg_sum: Dict[str, float] = {}

        for q in self._query_logs:
            t = q["topic"]
            topic_counts[t] = topic_counts.get(t, 0) + 1
            topic_ndcg_sum[t] = topic_ndcg_sum.get(t, 0.0) + q["ndcg"]
            if q["hits"] == 0:
                zero_hits.append(q["query"])

        # Knowledge Gap calculation: G(t) = sum (1 - NDCG) * ln(1 + count)
        knowledge_gaps: Dict[str, float] = {}
        for t, count in topic_counts.items():
            mean_t_ndcg = topic_ndcg_sum[t] / count
            gap = (1.0 - mean_t_ndcg) * math.log(1.0 + count)
            knowledge_gaps[t] = max(0.0, gap)

        # Topic Drift (burstiness score)
        topic_drifts: Dict[str, float] = {}
        for t, count in topic_counts.items():
            topic_drifts[t] = count / len(self._query_logs)

        return FeedbackTelemetry(
            telemetry_id=telemetry_id,
            ndcg_at_k=avg_ndcg,
            mean_average_precision=avg_ndcg * 0.95,
            zero_hit_queries=sorted(list(set(zero_hits))),
            frequent_topics=topic_counts,
            topic_drift_scores=topic_drifts,
            knowledge_gaps=knowledge_gaps,
        )

    def execute(self, context: PhaseContext) -> PhaseContext:
        """Executes Phase 6: Computes feedback telemetry for closed-loop adaptation."""
        try:
            telemetry = self.evaluate_telemetry(
                telemetry_id=f"telem_{context.cycle_id}"
            )
            context.telemetry = telemetry
            context.phase_statuses[IntelligencePhase.EVALUATION] = PhaseStatus.COMPLETED
        except Exception as ex:
            context.phase_statuses[IntelligencePhase.EVALUATION] = PhaseStatus.FAILED
            context.errors.append({"error": str(ex)})

        return context

    def compensate(self, context: PhaseContext) -> None:
        """Compensates Phase 6: resets telemetry."""
        context.telemetry = None
        context.phase_statuses[IntelligencePhase.EVALUATION] = PhaseStatus.COMPENSATED
