"""Dynamic PIR (Priority Intelligence Requirements) Manager for Phase 1.

Implements the dynamic PIR/SIR registry and EMA topic weight vector updating:
w_{k+1} = alpha * w_k + (1 - alpha) * (beta * u_usage + gamma * g_gap + delta * d_drift)
"""

import json
import math
import os
from datetime import datetime, timezone
from typing import Any, Dict, List, Optional, Set

from intelligence.contracts import (
    FeedbackTelemetry,
    IntelligenceDirective,
    IntelligencePhase,
    IntelligencePhaseProtocol,
    PhaseContext,
    PhaseStatus,
)
from intelligence.pir.models import PIRHorizon, PIRRequirement, TopicWeightVector


class PIRManager(IntelligencePhaseProtocol):
    """Phase 1: Planning & Direction Engine supporting 3-Horizon PIR Architecture."""

    def __init__(
        self,
        alpha: float = 0.7,
        beta: float = 0.4,
        gamma: float = 0.4,
        delta: float = 0.2,
        storage_path: Optional[str] = None,
        auto_seed: bool = False,
    ) -> None:
        self.alpha = alpha
        self.beta = beta
        self.gamma = gamma
        self.delta = delta
        self.storage_path = storage_path
        self._requirements: Dict[str, PIRRequirement] = {}
        self._current_weights = TopicWeightVector()
        self._load_or_seed_defaults(auto_seed=auto_seed)

    def _parse_pir_horizon(self, raw: str) -> PIRHorizon:
        try:
            return PIRHorizon(raw)
        except ValueError:
            return PIRHorizon.OPERATIONAL

    def _load_pir_item(self, item: Dict[str, Any]) -> PIRRequirement:
        horizon_val = self._parse_pir_horizon(item.get("horizon", "operational"))
        return PIRRequirement(
            req_id=item["req_id"],
            title=item["title"],
            description=item.get("description", ""),
            target_topics=item.get("target_topics", []),
            priority_score=item.get("priority_score", 1.0),
            horizon=horizon_val,
            escalation_level=item.get("escalation_level", 0),
            escalated_at=item.get("escalated_at"),
            is_active=item.get("is_active", True),
        )

    def _load_registry_from_disk(self) -> bool:
        if not self.storage_path:
            return False
        try:
            with open(self.storage_path, "r", encoding="utf-8") as f:
                data = json.load(f)
                for item in data.get("requirements", []):
                    req = self._load_pir_item(item)
                    self._requirements[req.req_id] = req
                if "weights" in data:
                    self._current_weights.weights = data["weights"]
                    return True
        except Exception:
            pass
        return False

    def _load_or_seed_defaults(self, auto_seed: bool = False) -> None:
        """Loads PIR registry from disk if available, otherwise optionally seeds domain defaults."""
        if self.storage_path and os.path.exists(self.storage_path):
            self._load_registry_from_disk()

        if auto_seed and not self._requirements:
            self._seed_default_requirements()

    def _seed_default_requirements(self) -> None:
        """Seeds standard default security PIRs across 3 temporal horizons."""
        self.register_requirement(
            PIRRequirement(
                req_id="pir_llm_sec",
                title="LLM & AI Safety Threats",
                description="Monitor prompt injection, jailbreaking, and foundation model security",
                target_topics=[
                    "LLM・AIセキュリティ",
                    "脱獄攻撃",
                    "プロンプトインジェクション",
                ],
                priority_score=0.9,
                horizon=PIRHorizon.TACTICAL,
            ),
            save=False,
        )
        self.register_requirement(
            PIRRequirement(
                req_id="pir_vuln_fuzz",
                title="Vulnerability Research & Penetration Testing",
                description="Monitor automated fuzzing, exploit payloads, and binary analysis",
                target_topics=[
                    "ファジング・脆弱性調査",
                    "ペネトレーションテスト・脆弱性検証",
                ],
                priority_score=0.85,
                horizon=PIRHorizon.TACTICAL,
            ),
            save=False,
        )
        self.register_requirement(
            PIRRequirement(
                req_id="pir_supply_chain",
                title="Software Supply Chain & Dependency Integrity",
                description="Monitor dependency confusion, Slopsquatting, and CI/CD security",
                target_topics=[
                    "サプライチェーンセキュリティ",
                    "依存関係汚染",
                ],
                priority_score=0.8,
                horizon=PIRHorizon.OPERATIONAL,
            ),
            save=False,
        )
        self.register_requirement(
            PIRRequirement(
                req_id="pir_crypto_priv",
                title="Cryptography & Privacy Engineering",
                description="Monitor post-quantum crypto, zero-knowledge proofs, and side-channel defenses",
                target_topics=["暗号・プライバシー技術", "耐量子暗号", "ゼロ知識証明"],
                priority_score=0.75,
                horizon=PIRHorizon.STRATEGIC,
            ),
            save=False,
        )

    def _save_state(self) -> None:
        """Persists PIR registry and topic weights to disk if storage_path is configured."""
        if not self.storage_path:
            return
        try:
            os.makedirs(os.path.dirname(self.storage_path), exist_ok=True)
            payload: Dict[str, Any] = {
                "requirements": [
                    {
                        "req_id": r.req_id,
                        "title": r.title,
                        "description": r.description,
                        "target_topics": r.target_topics,
                        "priority_score": r.priority_score,
                        "horizon": r.horizon.value,
                        "escalation_level": r.escalation_level,
                        "escalated_at": r.escalated_at,
                        "is_active": r.is_active,
                    }
                    for r in self._requirements.values()
                ],
                "weights": self._current_weights.weights,
            }
            with open(self.storage_path, "w", encoding="utf-8") as f:
                json.dump(payload, f, indent=2, ensure_ascii=False)
        except Exception:
            pass

    @property
    def phase_type(self) -> IntelligencePhase:
        return IntelligencePhase.PLANNING

    def register_requirement(self, req: PIRRequirement, save: bool = True) -> None:
        """Registers or updates a PIR requirement."""
        self._requirements[req.req_id] = req
        for topic in req.target_topics:
            if topic not in self._current_weights.weights:
                self._current_weights.weights[topic] = req.priority_score
            else:
                self._current_weights.weights[topic] = max(
                    self._current_weights.weights[topic], req.priority_score
                )
        self._current_weights.normalize()
        if save:
            self._save_state()

    def get_requirement(self, req_id: str) -> Optional[PIRRequirement]:
        return self._requirements.get(req_id)

    def list_active_requirements(self) -> List[PIRRequirement]:
        return [r for r in self._requirements.values() if r.is_active]

    def get_requirements_by_horizon(self, horizon: PIRHorizon) -> List[PIRRequirement]:
        """Filters active requirements belonging to a specific temporal horizon."""
        return [
            r
            for r in self._requirements.values()
            if r.is_active and r.horizon == horizon
        ]

    def escalate_requirement(
        self,
        req_id: str,
        reason: str,
        target_horizon: PIRHorizon = PIRHorizon.TACTICAL,
        max_level: int = 5,
    ) -> bool:
        """Dynamically escalates a PIR requirement to a higher-velocity horizon and boosts weight."""
        req = self.get_requirement(req_id)
        if not req or req.escalation_level >= max_level:
            return False

        req.horizon = target_horizon
        req.escalation_level += 1
        req.escalated_at = datetime.now(timezone.utc).isoformat()
        req.priority_score = min(1.0, req.priority_score + 0.15)
        req.metadata["last_escalation_reason"] = reason

        for topic in req.target_topics:
            old_w = self._current_weights.weights.get(topic, 0.5)
            self._current_weights.weights[topic] = min(1.0, old_w * 1.3 + 0.1)

        self._current_weights.normalize()
        self._save_state()
        return True

    def get_weights(self) -> Dict[str, float]:
        return dict(self._current_weights.weights)

    def _normalize_vector(
        self, topics: Set[str], source: Dict[str, Any], total: float
    ) -> Dict[str, float]:
        return {t: source.get(t, 0.0) / total if total > 0 else 0.0 for t in topics}

    def _calc_new_weights(
        self,
        all_topics: Set[str],
        u_usage: Dict[str, float],
        g_gap: Dict[str, float],
        d_drift: Dict[str, float],
    ) -> Dict[str, float]:
        new_weights: Dict[str, float] = {}
        for t in all_topics:
            w_old = self._current_weights.weights.get(
                t, 1.0 / len(all_topics) if all_topics else 1.0
            )
            feedback_term = (
                self.beta * u_usage.get(t, 0.0)
                + self.gamma * g_gap.get(t, 0.0)
                + self.delta * d_drift.get(t, 0.0)
            )
            w_new = self.alpha * w_old + (1.0 - self.alpha) * feedback_term
            new_weights[t] = max(0.001, w_new)
        return new_weights

    def update_weights_from_feedback(
        self,
        usage_counts: Dict[str, int],
        knowledge_gaps: Dict[str, float],
        topic_drifts: Dict[str, float],
    ) -> TopicWeightVector:
        """Applies EMA self-adapting feedback formula to recalculate topic weights."""
        all_topics = set(self._current_weights.weights.keys())
        all_topics.update(usage_counts.keys())
        all_topics.update(knowledge_gaps.keys())
        all_topics.update(topic_drifts.keys())

        if not all_topics:
            return self._current_weights

        u_usage = self._normalize_vector(
            all_topics, usage_counts, sum(usage_counts.values())
        )
        g_gap = self._normalize_vector(
            all_topics, knowledge_gaps, sum(knowledge_gaps.values())
        )
        d_drift = self._normalize_vector(
            all_topics, topic_drifts, sum(topic_drifts.values())
        )

        self._current_weights.weights = self._calc_new_weights(
            all_topics, u_usage, g_gap, d_drift
        )
        self._current_weights.normalize()
        self._save_state()
        return self._current_weights

    def _collect_target_topics(self, active_reqs: List[PIRRequirement]) -> List[str]:
        target_topics: List[str] = []
        for r in active_reqs:
            target_topics.extend(r.target_topics)
        target_topics = sorted(set(target_topics))
        if not target_topics and self._current_weights.weights:
            target_topics = sorted(self._current_weights.weights.keys())
        return target_topics

    def create_directive(
        self, directive_id: str, base_crawl_quota: int = 50
    ) -> IntelligenceDirective:
        """Generates an operational IntelligenceDirective with 3-Horizon quota allocation."""
        active_reqs = self.list_active_requirements()
        target_topics = self._collect_target_topics(active_reqs)

        weights = self.get_weights()
        quotas: Dict[str, int] = {}
        for t in target_topics:
            w = weights.get(t, 1.0 / max(1, len(target_topics)))
            quotas[t] = max(5, int(math.ceil(base_crawl_quota * w * 2.0)))

        horizon_counts: Dict[str, int] = {
            h.value: len(self.get_requirements_by_horizon(h)) for h in PIRHorizon
        }

        return IntelligenceDirective(
            directive_id=directive_id,
            target_topics=target_topics,
            topic_weights=weights,
            crawl_quotas=quotas,
            priority_level=1,
            metadata={
                "active_pir_count": len(active_reqs),
                "horizon_breakdown": horizon_counts,
            },
        )

    def _should_escalate_topic(
        self, topic: str, telemetry: FeedbackTelemetry, req: Any
    ) -> bool:
        gap = telemetry.knowledge_gaps.get(topic, 0.0)
        drift = telemetry.topic_drift_scores.get(topic, 0.0)
        return (gap > 0.35 or drift > 0.35) and req.horizon != PIRHorizon.TACTICAL

    def _escalate_req_if_needed(self, req: Any, telemetry: FeedbackTelemetry) -> None:
        for topic in req.target_topics:
            if self._should_escalate_topic(topic, telemetry, req):
                gap = telemetry.knowledge_gaps.get(topic, 0.0)
                drift = telemetry.topic_drift_scores.get(topic, 0.0)
                self.escalate_requirement(
                    req.req_id,
                    reason=f"Severe knowledge gap ({gap:.2f}) or drift ({drift:.2f})",
                    target_horizon=PIRHorizon.TACTICAL,
                )
                break

    def _escalate_requirements_from_gaps(self, telemetry: FeedbackTelemetry) -> None:
        for req in self._requirements.values():
            self._escalate_req_if_needed(req, telemetry)

    def _auto_create_pir_for_gaps(self, telemetry: FeedbackTelemetry) -> None:
        for gap_topic, gap_score in telemetry.knowledge_gaps.items():
            if gap_score > 0.3 and gap_topic not in self._requirements:
                horizon = (
                    PIRHorizon.TACTICAL if gap_score > 0.5 else PIRHorizon.OPERATIONAL
                )
                self.register_requirement(
                    PIRRequirement(
                        req_id=f"pir_auto_{len(self._requirements) + 1}",
                        title=f"Auto-Adapted PIR: {gap_topic}",
                        description=f"Self-adapted PIR triggered by knowledge gap score {gap_score:.3f}",
                        target_topics=[gap_topic],
                        priority_score=min(1.0, 0.5 + gap_score * 0.5),
                        horizon=horizon,
                    ),
                    save=True,
                )

    def adapt_queries_from_telemetry(
        self, telemetry: FeedbackTelemetry
    ) -> TopicWeightVector:
        """Adapts topic weights, triggers dynamic escalation, and injects zero-hit emerging topics."""
        self.update_weights_from_feedback(
            telemetry.frequent_topics,
            telemetry.knowledge_gaps,
            telemetry.topic_drift_scores,
        )
        self._escalate_requirements_from_gaps(telemetry)
        self._auto_create_pir_for_gaps(telemetry)
        return self._current_weights

    def execute(self, context: PhaseContext) -> PhaseContext:
        """Executes Phase 1: Formulates intelligence directives."""
        if context.telemetry:
            self.adapt_queries_from_telemetry(context.telemetry)
        directive = self.create_directive(directive_id=f"dir_{context.cycle_id}")
        context.directive = directive
        context.phase_statuses[IntelligencePhase.PLANNING] = PhaseStatus.COMPLETED
        return context

    def compensate(self, context: PhaseContext) -> None:
        """Compensates Phase 1 if downstream fails."""
        context.directive = None
        context.phase_statuses[IntelligencePhase.PLANNING] = PhaseStatus.COMPENSATED
