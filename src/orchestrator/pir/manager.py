"""Dynamic PIR (Priority Intelligence Requirements) Manager for Phase 1.

Implements the dynamic PIR/SIR registry and EMA topic weight vector updating:
w_{k+1} = alpha * w_k + (1 - alpha) * (beta * u_usage + gamma * g_gap + delta * d_drift)
"""

import json
import math
import os
from typing import Any, Dict, List, Optional

from orchestrator.contracts import (
    IntelligenceDirective,
    IntelligencePhase,
    IntelligencePhaseProtocol,
    PhaseContext,
    PhaseStatus,
)
from orchestrator.pir.models import PIRRequirement, TopicWeightVector


class PIRManager(IntelligencePhaseProtocol):
    """Phase 1: Planning & Direction Engine."""

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

    def _load_or_seed_defaults(self, auto_seed: bool = False) -> None:
        """Loads PIR registry from disk if available, otherwise optionally seeds domain defaults."""
        if self.storage_path and os.path.exists(self.storage_path):
            try:
                with open(self.storage_path, "r", encoding="utf-8") as f:
                    data = json.load(f)
                    for item in data.get("requirements", []):
                        req = PIRRequirement(
                            req_id=item["req_id"],
                            title=item["title"],
                            description=item.get("description", ""),
                            target_topics=item.get("target_topics", []),
                            priority_score=item.get("priority_score", 1.0),
                            is_active=item.get("is_active", True),
                        )
                        self._requirements[req.req_id] = req
                    if "weights" in data:
                        self._current_weights.weights = data["weights"]
                        return
            except Exception:
                pass

        if auto_seed and not self._requirements:
            self._seed_default_requirements()

    def _seed_default_requirements(self) -> None:
        """Seeds standard default security PIRs."""
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
            ),
            save=False,
        )
        self.register_requirement(
            PIRRequirement(
                req_id="pir_crypto_priv",
                title="Cryptography & Privacy Engineering",
                description="Monitor post-quantum crypto, zero-knowledge proofs, and side-channel defenses",
                target_topics=["暗号・プライバシー技術", "耐量子暗号", "ゼロ知識証明"],
                priority_score=0.8,
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

    def register_requirement(
        self, req: PIRRequirement, save: bool = True
    ) -> None:
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

    def get_weights(self) -> Dict[str, float]:
        return dict(self._current_weights.weights)

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

        # 1. Normalize usage vector
        total_usage = sum(usage_counts.values())
        u_usage: Dict[str, float] = {}
        for t in all_topics:
            u_usage[t] = (
                usage_counts.get(t, 0) / total_usage if total_usage > 0 else 0.0
            )

        # 2. Normalize gap vector
        total_gap = sum(knowledge_gaps.values())
        g_gap: Dict[str, float] = {}
        for t in all_topics:
            g_gap[t] = knowledge_gaps.get(t, 0.0) / total_gap if total_gap > 0 else 0.0

        # 3. Normalize drift vector
        total_drift = sum(topic_drifts.values())
        d_drift: Dict[str, float] = {}
        for t in all_topics:
            d_drift[t] = (
                topic_drifts.get(t, 0.0) / total_drift if total_drift > 0 else 0.0
            )

        # 4. Composite update
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

        self._current_weights.weights = new_weights
        self._current_weights.normalize()
        self._save_state()
        return self._current_weights

    def create_directive(
        self, directive_id: str, base_crawl_quota: int = 50
    ) -> IntelligenceDirective:
        """Generates an operational IntelligenceDirective with topic crawl quotas."""
        active_reqs = self.list_active_requirements()
        target_topics: List[str] = []
        for r in active_reqs:
            target_topics.extend(r.target_topics)
        target_topics = sorted(list(set(target_topics)))

        if not target_topics and self._current_weights.weights:
            target_topics = sorted(list(self._current_weights.weights.keys()))

        weights = self.get_weights()
        quotas: Dict[str, int] = {}
        for t in target_topics:
            w = weights.get(t, 1.0 / max(1, len(target_topics)))
            # Allocate quota proportional to weight: base * (1 + w * 2)
            quotas[t] = max(5, int(math.ceil(base_crawl_quota * w * 2.0)))

        return IntelligenceDirective(
            directive_id=directive_id,
            target_topics=target_topics,
            topic_weights=weights,
            crawl_quotas=quotas,
            priority_level=1,
            metadata={"active_pir_count": len(active_reqs)},
        )

    def execute(self, context: PhaseContext) -> PhaseContext:
        """Executes Phase 1: Formulates intelligence directives."""
        directive = self.create_directive(directive_id=f"dir_{context.cycle_id}")
        context.directive = directive
        context.phase_statuses[IntelligencePhase.PLANNING] = PhaseStatus.COMPLETED
        return context

    def compensate(self, context: PhaseContext) -> None:
        """Compensates Phase 1 if downstream fails."""
        context.directive = None
        context.phase_statuses[IntelligencePhase.PLANNING] = PhaseStatus.COMPENSATED
