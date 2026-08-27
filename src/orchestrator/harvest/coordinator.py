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
from orchestrator.harvest.adaptive_router import AdaptiveHarvestRouter


class HarvestCoordinator(IntelligencePhaseProtocol):
    """Phase 2: Multi-Source Collection Coordinator with Adaptive Route Mutation."""

    def __init__(
        self,
        custom_harvesters: Optional[
            Dict[str, Callable[[str, int], List[Dict[str, Any]]]]
        ] = None,
    ) -> None:
        self.router = AdaptiveHarvestRouter()
        self._setup_initial_routes(custom_harvesters)

    def _setup_initial_routes(
        self,
        custom_harvesters: Optional[
            Dict[str, Callable[[str, int], List[Dict[str, Any]]]]
        ],
    ) -> None:
        """Sets up default or custom harvest routes."""
        if custom_harvesters:
            for idx, (name, fn) in enumerate(custom_harvesters.items()):
                self.router.register_route(
                    route_id=name,
                    source_type=name,
                    priority=idx + 1,
                    handler_fn=fn,
                )
        else:
            # Default routes: Primary synthetic -> Secondary synthetic fallback
            self.router.register_route(
                route_id="primary_arxiv_harvester",
                source_type="arxiv_api",
                priority=1,
                handler_fn=self._default_harvest_fn,
            )
            self.router.register_route(
                route_id="secondary_rss_harvester",
                source_type="rss_feed",
                priority=2,
                handler_fn=self._default_harvest_fn,
            )

    def _default_harvest_fn(self, topic: str, quota: int) -> List[Dict[str, Any]]:
        """Default collection generator for standalone operations."""
        return [
            {
                "id": f"rec_{topic}_{i+1}",
                "title": f"Intelligence Observation on {topic} #{i+1}",
                "topic": topic,
                "raw_text": f"Detailed raw intelligence data concerning {topic}.",
                "source": "universal_harvester",
            }
            for i in range(max(1, quota))
        ]

    @property
    def phase_type(self) -> IntelligencePhase:
        return IntelligencePhase.COLLECTION

    def register_harvester(
        self,
        source_name: str,
        harvester_fn: Callable[[str, int], List[Dict[str, Any]]],
        priority: int = 1,
    ) -> None:
        """Registers an external harvester/crawler function into the router with top priority."""
        # If default synthetic routes are in place, replace primary with this custom route
        if "primary_arxiv_harvester" in self.router._routes:
            del self.router._routes["primary_arxiv_harvester"]
        self.router.register_route(
            route_id=source_name,
            source_type=source_name,
            priority=priority,
            handler_fn=harvester_fn,
        )

    def harvest(
        self, target_topics: List[str], crawl_quotas: Dict[str, int]
    ) -> List[Dict[str, Any]]:
        """Collects raw records across registered sources with dynamic route mutation."""
        collected: List[Dict[str, Any]] = []

        for topic in target_topics:
            quota = crawl_quotas.get(topic, 5)
            records, used_route, _ = self.router.harvest_topic(topic, quota)
            collected.extend(records)

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
