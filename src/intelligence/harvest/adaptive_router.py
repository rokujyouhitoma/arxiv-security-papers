"""Autonomous Self-Healing & Dynamic Route Mutation Harvester.

Provides circuit breaking, health monitoring, and automatic route mutation
across external intelligence sources (arXiv API, RSS, Spiders, Local Fallbacks).
"""

import time
from dataclasses import dataclass, field
from typing import Any, Callable, Dict, List, Optional

from workflow.circuit import CircuitBreaker, CircuitState


@dataclass
class HarvestRoute:
    """A data source route with priority, circuit breaker, and health metrics."""

    route_id: str
    source_type: str
    priority: int  # 1 = Highest (Primary), 2 = Secondary, etc.
    handler_fn: Callable[[str, int], List[Dict[str, Any]]]
    circuit: CircuitBreaker = field(default_factory=CircuitBreaker)
    health_score: float = 1.0  # 0.0 (unhealthy) to 1.0 (perfect health)
    total_calls: int = 0
    success_count: int = 0
    failure_count: int = 0
    avg_latency_ms: float = 0.0

    def update_metrics(self, success: bool, latency_ms: float) -> None:
        """Updates health score EMA and latency statistics."""
        self.total_calls += 1
        if success:
            self.success_count += 1
            self.circuit.record_success()
            # EMA adaptation: weight = 0.2
            self.health_score = round(self.health_score * 0.8 + 1.0 * 0.2, 3)
        else:
            self.failure_count += 1
            self.circuit.record_failure()
            self.health_score = round(self.health_score * 0.8 + 0.0 * 0.2, 3)

        # Average latency update
        if self.total_calls == 1:
            self.avg_latency_ms = latency_ms
        else:
            self.avg_latency_ms = round(self.avg_latency_ms * 0.8 + latency_ms * 0.2, 2)


class AdaptiveHarvestRouter:
    """Orchestrates multi-source collection with dynamic route mutation on failures."""

    def __init__(self) -> None:
        self._routes: Dict[str, HarvestRoute] = {}

    def register_route(
        self,
        route_id: str,
        source_type: str,
        priority: int,
        handler_fn: Callable[[str, int], List[Dict[str, Any]]],
        failure_threshold: int = 3,
        cooldown_seconds: float = 30.0,
    ) -> HarvestRoute:
        """Registers a harvest route with priority and custom circuit parameters."""
        route = HarvestRoute(
            route_id=route_id,
            source_type=source_type,
            priority=priority,
            handler_fn=handler_fn,
            circuit=CircuitBreaker(
                failure_threshold=failure_threshold,
                cooldown_seconds=cooldown_seconds,
            ),
        )
        self._routes[route_id] = route
        return route

    def get_route(self, route_id: str) -> Optional[HarvestRoute]:
        return self._routes.get(route_id)

    def _get_sorted_routes(self) -> List[HarvestRoute]:
        """Returns routes sorted by priority (ascending) and health (descending)."""
        return sorted(
            self._routes.values(),
            key=lambda r: (r.priority, -r.health_score),
        )

    def _try_route(
        self, route: HarvestRoute, topic: str, quota: int
    ) -> Optional[List[Dict[str, Any]]]:
        """Attempts collection on a single route, updating its circuit and metrics."""
        t_start = time.perf_counter()
        try:
            records = route.handler_fn(topic, quota)
            latency_ms = (time.perf_counter() - t_start) * 1000.0
            route.update_metrics(success=True, latency_ms=latency_ms)
            return records
        except Exception:
            latency_ms = (time.perf_counter() - t_start) * 1000.0
            route.update_metrics(success=False, latency_ms=latency_ms)
            return None

    def harvest_topic(
        self, topic: str, quota: int
    ) -> tuple[List[Dict[str, Any]], str, List[Dict[str, Any]]]:
        """Collects records for a topic with automatic route mutation upon failures."""
        mutation_log: List[Dict[str, Any]] = []
        sorted_routes = self._get_sorted_routes()

        for route in sorted_routes:
            if not route.circuit.can_execute():
                mutation_log.append(
                    {
                        "route_id": route.route_id,
                        "action": "bypassed",
                        "reason": f"Circuit {route.circuit.state.value}",
                    }
                )
                continue

            records = self._try_route(route, topic, quota)
            if records is not None:
                mutation_log.append(
                    {
                        "route_id": route.route_id,
                        "action": "success",
                        "records_count": len(records),
                    }
                )
                return records, route.route_id, mutation_log
            else:
                mutation_log.append(
                    {
                        "route_id": route.route_id,
                        "action": "failed_mutating_to_next",
                        "circuit_state": route.circuit.state.value,
                    }
                )

        # Fallback if all routes fail
        fallback_records = [
            {
                "id": f"emergency_fallback_{topic}_{i+1}",
                "title": f"Emergency Cached Intelligence on {topic} #{i+1}",
                "topic": topic,
                "raw_text": f"Fallback content for {topic} when all harvest routes are unavailable.",
                "source": "emergency_router_cache",
            }
            for i in range(max(1, quota))
        ]
        return fallback_records, "emergency_fallback", mutation_log

    def get_routes_status(self) -> List[Dict[str, Any]]:
        """Returns structured status dictionary for all registered routes."""
        return [
            {
                "route_id": r.route_id,
                "source_type": r.source_type,
                "priority": r.priority,
                "circuit_state": r.circuit.state.value,
                "health_score": r.health_score,
                "total_calls": r.total_calls,
                "success_count": r.success_count,
                "failure_count": r.failure_count,
                "avg_latency_ms": r.avg_latency_ms,
            }
            for r in self._get_sorted_routes()
        ]

    def generate_status_markdown(self) -> str:
        """Generates a complete Japanese markdown table of route health statuses."""
        lines = [
            "# 🛰️ 自律型自己修復ハーベストルーター稼働状況",
            "",
            "| 優先度 | ルートID | 情報源種別 | 回線状態 (Circuit) | 健全度 (Health) | 成功/失敗 | 平均遅延 (ms) |",
            "| :---: | :--- | :--- | :---: | :---: | :---: | :---: |",
        ]
        for r in self._get_sorted_routes():
            state_icon = (
                "🟢 CLOSED"
                if r.circuit.state == CircuitState.CLOSED
                else (
                    "🔴 OPEN"
                    if r.circuit.state == CircuitState.OPEN
                    else "🟡 HALF_OPEN"
                )
            )
            lines.append(
                f"| {r.priority} | `{r.route_id}` | {r.source_type} | {state_icon} | {r.health_score:.2f} | "
                f"{r.success_count}/{r.failure_count} | {r.avg_latency_ms:.1f}ms |"
            )
        return "\n".join(lines)
