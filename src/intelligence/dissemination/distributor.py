"""Dissemination Distributor for Phase 5 (Dissemination & Integration).

Distributes finalized intelligence products across AI Agent MCP interfaces,
RESTful Web Gateways, and static Markdown executive reporting hubs.
"""

from typing import Callable, Dict, List

from intelligence.contracts import (
    IntelligencePhase,
    IntelligencePhaseProtocol,
    IntelligenceProduct,
    PhaseContext,
    PhaseStatus,
)


class DisseminationDistributor(IntelligencePhaseProtocol):
    """Phase 5: Multi-Channel Dissemination Gateway."""

    def __init__(self) -> None:
        self._channels: Dict[str, Callable[[List[IntelligenceProduct]], None]] = {}
        self._published_history: List[IntelligenceProduct] = []

    @property
    def phase_type(self) -> IntelligencePhase:
        return IntelligencePhase.DISSEMINATION

    def register_channel(
        self,
        channel_name: str,
        handler: Callable[[List[IntelligenceProduct]], None],
    ) -> None:
        """Registers a publication channel callback (e.g., MCP sync, Web API cache)."""
        self._channels[channel_name] = handler

    def get_published_products(self) -> List[IntelligenceProduct]:
        return list(self._published_history)

    def disseminate(self, products: List[IntelligenceProduct]) -> None:
        """Disseminates products to all registered channels."""
        self._published_history.extend(products)
        for name, handler in self._channels.items():
            try:
                handler(products)
            except Exception:
                # Log channel error and proceed
                pass

    def execute(self, context: PhaseContext) -> PhaseContext:
        """Executes Phase 5: Disseminates all synthesized products."""
        try:
            self.disseminate(context.products)
            context.phase_statuses[IntelligencePhase.DISSEMINATION] = (
                PhaseStatus.COMPLETED
            )
        except Exception as ex:
            context.phase_statuses[IntelligencePhase.DISSEMINATION] = PhaseStatus.FAILED
            context.errors.append({"error": str(ex)})

        return context

    def compensate(self, context: PhaseContext) -> None:
        """Compensates Phase 5: revokes published batch."""
        # Remove current batch products from published history
        cur_ids = {p.product_id for p in context.products}
        self._published_history = [
            p for p in self._published_history if p.product_id not in cur_ids
        ]
        context.phase_statuses[IntelligencePhase.DISSEMINATION] = (
            PhaseStatus.COMPENSATED
        )
