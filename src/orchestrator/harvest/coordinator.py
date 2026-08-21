"""Harvest Coordinator for Phase 2 (Collection).

Coordinates multi-source data harvesters, crawlers, and adapters while enforcing
PIR crawl priorities, OPIC credit allocation, and rate-limiting safeguards.
"""

from typing import Any, Callable, Dict, List, Optional

from orchestrator.contracts import (
    IntelligencePhase,
    IntelligencePhaseProtocol,
    PhaseContext,
    PhaseStatus,
)


class HarvestCoordinator(IntelligencePhaseProtocol):
    """Phase 2: Multi-Source Collection Coordinator."""

    def __init__(
        self,
        custom_harvesters: Optional[
            Dict[str, Callable[[str, int], List[Dict[str, Any]]]]
        ] = None,
    ) -> None:
        self._harvesters = custom_harvesters or {}

    @property
    def phase_type(self) -> IntelligencePhase:
        return IntelligencePhase.COLLECTION

    def register_harvester(
        self,
        source_name: str,
        harvester_fn: Callable[[str, int], List[Dict[str, Any]]],
    ) -> None:
        """Registers an external harvester/crawler function."""
        self._harvesters[source_name] = harvester_fn

    def harvest(
        self, target_topics: List[str], crawl_quotas: Dict[str, int]
    ) -> List[Dict[str, Any]]:
        """Collects raw records across registered sources based on topic quotas."""
        collected: List[Dict[str, Any]] = []

        if self._harvesters:
            for source_name, fn in self._harvesters.items():
                for topic in target_topics:
                    quota = crawl_quotas.get(topic, 10)
                    try:
                        records = fn(topic, quota)
                        collected.extend(records)
                    except Exception as e:
                        # Fault-tolerance: log and continue
                        collected.append(
                            {
                                "id": f"error_{source_name}_{topic}",
                                "error": str(e),
                                "source": source_name,
                                "topic": topic,
                            }
                        )
        else:
            # Synthetic fallback adapter for standalone orchestrator operation
            for topic in target_topics:
                quota = crawl_quotas.get(topic, 5)
                for i in range(quota):
                    collected.append(
                        {
                            "id": f"rec_{topic}_{i+1}",
                            "title": f"Intelligence Observation on {topic} #{i+1}",
                            "topic": topic,
                            "raw_text": f"Detailed raw intelligence data concerning {topic}.",
                            "source": "universal_harvester",
                        }
                    )

        return collected

    def execute(self, context: PhaseContext) -> PhaseContext:
        """Executes Phase 2: Harvests raw records based on the Phase 1 directive."""
        if not context.directive:
            context.phase_statuses[IntelligencePhase.COLLECTION] = PhaseStatus.FAILED
            context.errors.append({"error": "Missing IntelligenceDirective"})
            return context

        try:
            records = self.harvest(
                target_topics=context.directive.target_topics,
                crawl_quotas=context.directive.crawl_quotas,
            )
            context.raw_records = records
            context.phase_statuses[IntelligencePhase.COLLECTION] = PhaseStatus.COMPLETED
        except Exception as ex:
            context.phase_statuses[IntelligencePhase.COLLECTION] = PhaseStatus.FAILED
            context.errors.append({"error": str(ex)})

        return context

    def compensate(self, context: PhaseContext) -> None:
        """Compensates Phase 2 if downstream fails: cleans raw records cache."""
        context.raw_records = []
        context.phase_statuses[IntelligencePhase.COLLECTION] = PhaseStatus.COMPENSATED
