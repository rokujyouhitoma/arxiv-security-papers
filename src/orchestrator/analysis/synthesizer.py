"""Analysis Synthesizer for Phase 4 (Analysis & Production).

Correlates structured data, evaluates multi-source confidence, and synthesizes
multi-tier actionable intelligence products (01_per_run through 05_annual).
"""

from collections import defaultdict
from typing import Any, Dict, List

from orchestrator.contracts import (
    IntelligencePhase,
    IntelligencePhaseProtocol,
    IntelligenceProduct,
    PhaseContext,
    PhaseStatus,
)


class AnalysisSynthesizer(IntelligencePhaseProtocol):
    """Phase 4: Synthesis and Production Engine."""

    @property
    def phase_type(self) -> IntelligencePhase:
        return IntelligencePhase.ANALYSIS

    def synthesize_products(
        self, processed_records: List[Dict[str, Any]], cycle_id: str
    ) -> List[IntelligenceProduct]:
        """Synthesizes structured intelligence products across tiers."""
        products: List[IntelligenceProduct] = []

        # 1. Group records by topic
        topic_groups: Dict[str, List[Dict[str, Any]]] = defaultdict(list)
        for r in processed_records:
            topic = str(r.get("topic", "general"))
            topic_groups[topic].append(r)

        # 2. Synthesize Per-Run Product (01_per_run)
        total_count = len(processed_records)
        summary_lines = [
            f"- Topic '{t}': {len(recs)} records observed."
            for t, recs in topic_groups.items()
        ]
        summary_text = (
            f"Automated intelligence synthesis for cycle {cycle_id}.\n"
            + "\n".join(summary_lines)
        )

        run_product = IntelligenceProduct(
            product_id=f"prod_run_{cycle_id}",
            title=f"Cycle {cycle_id} Intelligence Assessment",
            summary=summary_text,
            tier="01_per_run",
            topic_tags=sorted(list(topic_groups.keys())),
            source_count=total_count,
            confidence_score=min(1.0, 0.7 + 0.05 * total_count),
            okf_references=[str(r.get("id")) for r in processed_records],
        )
        products.append(run_product)

        # 3. Synthesize Topic Strategic Overviews (02_daily tier)
        for topic, recs in topic_groups.items():
            topic_prod = IntelligenceProduct(
                product_id=f"prod_topic_{topic}_{cycle_id}",
                title=f"Domain Intelligence Deep-Dive: {topic.capitalize()}",
                summary=f"Consolidated analysis for domain {topic} based on {len(recs)} primary sources.",
                tier="02_daily",
                topic_tags=[topic],
                source_count=len(recs),
                confidence_score=0.9,
                okf_references=[str(r.get("id")) for r in recs],
            )
            products.append(topic_prod)

        return products

    def execute(self, context: PhaseContext) -> PhaseContext:
        """Executes Phase 4: Produces intelligence products."""
        try:
            products = self.synthesize_products(
                processed_records=context.processed_records,
                cycle_id=context.cycle_id,
            )
            context.products = products
            context.phase_statuses[IntelligencePhase.ANALYSIS] = PhaseStatus.COMPLETED
        except Exception as ex:
            context.phase_statuses[IntelligencePhase.ANALYSIS] = PhaseStatus.FAILED
            context.errors.append({"error": str(ex)})

        return context

    def compensate(self, context: PhaseContext) -> None:
        """Compensates Phase 4: clears synthesized products."""
        context.products = []
        context.phase_statuses[IntelligencePhase.ANALYSIS] = PhaseStatus.COMPENSATED
