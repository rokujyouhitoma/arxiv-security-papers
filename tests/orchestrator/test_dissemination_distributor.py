"""Tests for Phase 5 DisseminationDistributor."""

from orchestrator.contracts import (
    IntelligencePhase,
    IntelligenceProduct,
    PhaseContext,
    PhaseStatus,
)
from orchestrator.dissemination.distributor import DisseminationDistributor


def test_dissemination_distributor_channels() -> None:
    dist = DisseminationDistributor()
    received_mcp: list = []
    received_web: list = []

    dist.register_channel("mcp", lambda prods: received_mcp.extend(prods))
    dist.register_channel("web", lambda prods: received_web.extend(prods))

    prod = IntelligenceProduct(
        product_id="p1",
        title="Title 1",
        summary="Summary 1",
        tier="01_per_run",
        topic_tags=["t1"],
        source_count=1,
        confidence_score=0.9,
    )
    dist.disseminate([prod])

    assert len(received_mcp) == 1
    assert len(received_web) == 1
    assert len(dist.get_published_products()) == 1


def test_dissemination_distributor_phase_execution_and_compensation() -> None:
    dist = DisseminationDistributor()
    prod = IntelligenceProduct(
        product_id="p_comp",
        title="Title C",
        summary="Summary C",
        tier="01_per_run",
        topic_tags=["t_c"],
        source_count=1,
        confidence_score=0.9,
    )
    ctx = PhaseContext(cycle_id="c_dis", workspace_dir="/tmp", products=[prod])

    ctx = dist.execute(ctx)
    assert ctx.phase_statuses[IntelligencePhase.DISSEMINATION] == PhaseStatus.COMPLETED
    assert len(dist.get_published_products()) == 1

    dist.compensate(ctx)
    assert (
        ctx.phase_statuses[IntelligencePhase.DISSEMINATION] == PhaseStatus.COMPENSATED
    )
    assert len(dist.get_published_products()) == 0
