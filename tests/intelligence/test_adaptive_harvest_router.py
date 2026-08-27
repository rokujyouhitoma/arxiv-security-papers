"""Test suite for Autonomous Self-Healing & Dynamic Route Mutation Harvester."""

from typing import Any, Dict, List

from intelligence.cli import main
from intelligence.contracts import (
    IntelligenceDirective,
    IntelligencePhase,
    PhaseContext,
    PhaseStatus,
)
from intelligence.harvest.adaptive_router import (
    AdaptiveHarvestRouter,
    CircuitBreaker,
    CircuitState,
)
from intelligence.harvest.coordinator import HarvestCoordinator


def test_circuit_breaker_transitions() -> None:
    cb = CircuitBreaker(failure_threshold=2, cooldown_seconds=10.0)
    assert cb.state == CircuitState.CLOSED
    assert cb.can_execute(current_time=100.0) is True

    # 1 failure -> still closed
    cb.record_failure(current_time=100.0)
    assert cb.state == CircuitState.CLOSED

    # 2 failures -> trips to OPEN
    cb.record_failure(current_time=101.0)
    assert cb.state == CircuitState.OPEN
    assert cb.can_execute(current_time=105.0) is False

    # After cooldown -> transitions to HALF_OPEN
    assert cb.can_execute(current_time=112.0) is True
    assert cb.state == CircuitState.HALF_OPEN

    # Success in HALF_OPEN -> restores CLOSED
    cb.record_success()
    assert cb.state == CircuitState.CLOSED
    assert cb.consecutive_failures == 0


def test_circuit_breaker_half_open_failure() -> None:
    cb = CircuitBreaker(failure_threshold=2, cooldown_seconds=10.0)
    cb.record_failure(current_time=100.0)
    cb.record_failure(current_time=101.0)
    assert cb.state == CircuitState.OPEN

    # Cooldown passed -> HALF_OPEN
    assert cb.can_execute(current_time=115.0) is True
    assert cb.state == CircuitState.HALF_OPEN

    # Failure in HALF_OPEN -> immediately returns to OPEN
    cb.record_failure(current_time=116.0)
    assert cb.state == CircuitState.OPEN
    assert cb.can_execute(current_time=120.0) is False


def test_harvest_route_metrics_and_ema() -> None:
    router = AdaptiveHarvestRouter()

    def dummy_success(t: str, q: int) -> List[Dict[str, Any]]:
        return [{"id": f"rec_{t}_{i}"} for i in range(q)]

    route = router.register_route(
        route_id="test_route",
        source_type="api",
        priority=1,
        handler_fn=dummy_success,
    )
    assert route.health_score == 1.0

    # Execute success
    records, used_route, _ = router.harvest_topic("crypto", 2)
    assert len(records) == 2
    assert used_route == "test_route"
    assert route.success_count == 1
    assert route.health_score == 1.0

    # Inject failure
    def dummy_fail(t: str, q: int) -> List[Dict[str, Any]]:
        raise ConnectionResetError("Remote API 429 Rate Limit")

    route.handler_fn = dummy_fail
    records, _, _ = router.harvest_topic("crypto", 2)
    assert route.failure_count == 1
    assert route.health_score < 1.0


def test_adaptive_router_route_mutation_fallback() -> None:
    router = AdaptiveHarvestRouter()

    # Route 1: Always fails (Primary)
    def primary_fail(t: str, q: int) -> List[Dict[str, Any]]:
        raise TimeoutError("arXiv API Gateway Timeout 504")

    # Route 2: Succeeds (Secondary / Fallback)
    def secondary_success(t: str, q: int) -> List[Dict[str, Any]]:
        return [{"id": f"rss_{t}_{i}", "source": "rss"} for i in range(q)]

    router.register_route(
        route_id="primary_arxiv_api",
        source_type="arxiv_api",
        priority=1,
        handler_fn=primary_fail,
        failure_threshold=1,
    )
    router.register_route(
        route_id="secondary_rss",
        source_type="rss_feed",
        priority=2,
        handler_fn=secondary_success,
    )

    records, used_route, mutation_log = router.harvest_topic("zero-trust", 3)
    assert len(records) == 3
    assert used_route == "secondary_rss"
    assert records[0]["source"] == "rss"

    # Check that route 1 tripped to OPEN
    r1 = router.get_route("primary_arxiv_api")
    assert r1 is not None
    assert r1.circuit.state == CircuitState.OPEN

    # Next attempt should bypass route 1 entirely without calling handler
    records2, used_route2, mutation_log2 = router.harvest_topic("zero-trust", 2)
    assert used_route2 == "secondary_rss"
    assert any(entry.get("action") == "bypassed" for entry in mutation_log2)


def test_adaptive_router_all_routes_fail_emergency_cache() -> None:
    router = AdaptiveHarvestRouter()

    def all_fail(t: str, q: int) -> List[Dict[str, Any]]:
        raise ConnectionRefusedError("Offline")

    router.register_route("r1", "api", 1, all_fail, failure_threshold=1)
    router.register_route("r2", "rss", 2, all_fail, failure_threshold=1)

    records, used_route, _ = router.harvest_topic("quantum", 3)
    assert used_route == "emergency_fallback"
    assert len(records) == 3
    assert records[0]["source"] == "emergency_router_cache"


def test_harvest_coordinator_router_integration(tmp_path) -> None:
    coordinator = HarvestCoordinator()
    assert len(coordinator.router.get_routes_status()) >= 2

    ctx = PhaseContext(cycle_id="test_cycle", workspace_dir=str(tmp_path))
    ctx.directive = IntelligenceDirective(
        directive_id="dir_01",
        target_topics=["cryptography"],
        topic_weights={"cryptography": 1.0},
        crawl_quotas={"cryptography": 3},
    )

    ctx = coordinator.execute(ctx)
    assert ctx.phase_statuses[IntelligencePhase.COLLECTION] == PhaseStatus.COMPLETED
    assert len(ctx.raw_records) == 3

    # Compensation
    coordinator.compensate(ctx)
    assert ctx.phase_statuses[IntelligencePhase.COLLECTION] == PhaseStatus.COMPENSATED
    assert len(ctx.raw_records) == 0


def test_cli_harvest_commands(tmp_path, capsys) -> None:
    # 1. Test harvest status
    code_status = main(["--workdir", str(tmp_path), "harvest", "status"])
    assert code_status == 0
    captured_status = capsys.readouterr()
    assert "自律型自己修復ハーベストルーター稼働状況" in captured_status.out
    assert "CLOSED" in captured_status.out

    # 2. Test harvest test
    code_test = main(
        [
            "--workdir",
            str(tmp_path),
            "harvest",
            "test",
            "--topic",
            "post-quantum",
            "--quota",
            "4",
        ]
    )
    assert code_test == 0
    captured_test = capsys.readouterr()
    assert "ADAPTIVE HARVEST ROUTE MUTATION TEST" in captured_test.out
    assert "Collected Records: 4" in captured_test.out
