"""Hypothesis-Driven Autonomous Investigation and Verification Engine.

Formulates emerging security hypotheses from correlated research topics,
extracts empirical supporting/refuting evidence from literature, calculates
Bayesian-updated confidence scores, and produces actionable investigation reports.
"""

import json
import os
import re
from datetime import datetime, timezone
from typing import Any, Dict, List, Optional

from orchestrator.contracts import Hypothesis, HypothesisEvidence, HypothesisStatus


class HypothesisEngine:
    """Core intelligence engine for formulating and verifying academic hypotheses."""

    # Curated knowledge discovery templates for autonomous hypothesis generation
    HYPOTHESIS_TEMPLATES: List[Dict[str, Any]] = [
        {
            "id_prefix": "hypo_llm_mcp",
            "trigger_keywords": ["mcp", "tool use", "agent", "function calling"],
            "statement": "LLM エージェントおよび MCP (Model Context Protocol) 連携における攻撃ベクトルは、プロンプトインジェクションから権限昇格・不正ツール実行へ移行している",
            "target_topics": [
                "LLM・AIセキュリティ",
                "MCPセキュリティ",
                "エージェント脆弱性",
            ],
            "support_patterns": [
                r"privilege\s+escalation",
                r"tool\s+abuse",
                r"unauthorized\s+execution",
                r"mcp\s+exploit",
                r"agent\s+hijack",
            ],
            "refute_patterns": [
                r"sandboxing\s+prevents",
                r"strict\s+rbac\s+blocks",
                r"formal\s+verification\s+guarantees",
                r"zero\s+risk",
            ],
        },
        {
            "id_prefix": "hypo_pqc_sidechannel",
            "trigger_keywords": ["pqc", "kyber", "ml-kem", "dilithium", "post-quantum"],
            "statement": "NIST 標準化格子暗号 (ML-KEM / ML-DSA) に対する実用的脅威は、数論的解読ではなく実装サイドチャネル (SCA / 故障注入) に集中している",
            "target_topics": [
                "耐量子暗号",
                "サイドチャネル攻撃",
                "ハードウェアセキュリティ",
            ],
            "support_patterns": [
                r"side-channel",
                r"power\s+analysis",
                r"fault\s+injection",
                r"em\s+leakage",
                r"timing\s+attack",
            ],
            "refute_patterns": [
                r"constant-time\s+immune",
                r"masking\s+countermeasure\s+verified",
                r"sca\s+resistant",
            ],
        },
        {
            "id_prefix": "hypo_slopsquatting",
            "trigger_keywords": [
                "slopsquatting",
                "package hallucination",
                "dependency confusion",
                "typosquatting",
            ],
            "statement": "AI コード生成アシスタントの幻覚パッケージ名を悪用した Slopsquatting は、既存のサプライチェーン検査を容易にバイパスする",
            "target_topics": [
                "サプライチェーンセキュリティ",
                "依存関係汚染",
                "AI幻覚悪用",
            ],
            "support_patterns": [
                r"hallucinated\s+package",
                r"bypasses\s+scanner",
                r"unregistered\s+import",
                r"slopsquatting\s+attack",
            ],
            "refute_patterns": [
                r"hash\s+pinning\s+eliminates",
                r"private\s+registry\s+blocks",
                r"lockfile\s+prevents",
            ],
        },
    ]

    def __init__(self, storage_path: Optional[str] = None) -> None:
        self.storage_path = storage_path
        self._hypotheses: Dict[str, Hypothesis] = {}
        self._load_state()

    def _load_state(self) -> None:
        """Loads persistent hypotheses from disk if available."""
        if self.storage_path and os.path.exists(self.storage_path):
            try:
                with open(self.storage_path, "r", encoding="utf-8") as f:
                    data = json.load(f)
                    for item in data.get("hypotheses", []):
                        raw_status = item.get("status", "formulated")
                        try:
                            status_val = HypothesisStatus(raw_status)
                        except ValueError:
                            status_val = HypothesisStatus.FORMULATED

                        supp_ev = [
                            HypothesisEvidence(**ev)
                            for ev in item.get("supporting_evidence", [])
                        ]
                        ref_ev = [
                            HypothesisEvidence(**ev)
                            for ev in item.get("refuting_evidence", [])
                        ]

                        hypo = Hypothesis(
                            hypo_id=item["hypo_id"],
                            statement=item["statement"],
                            target_topics=item.get("target_topics", []),
                            confidence_score=item.get("confidence_score", 0.5),
                            status=status_val,
                            supporting_evidence=supp_ev,
                            refuting_evidence=ref_ev,
                            formulated_at=item.get("formulated_at", ""),
                            updated_at=item.get("updated_at", ""),
                            metadata=item.get("metadata", {}),
                        )
                        self._hypotheses[hypo.hypo_id] = hypo
            except Exception:
                pass

    def _save_state(self) -> None:
        """Saves hypotheses to disk."""
        if not self.storage_path:
            return
        try:
            os.makedirs(os.path.dirname(self.storage_path), exist_ok=True)
            payload = {
                "hypotheses": [
                    {
                        "hypo_id": h.hypo_id,
                        "statement": h.statement,
                        "target_topics": h.target_topics,
                        "confidence_score": h.confidence_score,
                        "status": h.status.value,
                        "supporting_evidence": [
                            {
                                "evidence_id": ev.evidence_id,
                                "paper_id": ev.paper_id,
                                "excerpt": ev.excerpt,
                                "polarity": ev.polarity,
                                "relevance_score": ev.relevance_score,
                                "recorded_at": ev.recorded_at,
                                "metadata": ev.metadata,
                            }
                            for ev in h.supporting_evidence
                        ],
                        "refuting_evidence": [
                            {
                                "evidence_id": ev.evidence_id,
                                "paper_id": ev.paper_id,
                                "excerpt": ev.excerpt,
                                "polarity": ev.polarity,
                                "relevance_score": ev.relevance_score,
                                "recorded_at": ev.recorded_at,
                                "metadata": ev.metadata,
                            }
                            for ev in h.refuting_evidence
                        ],
                        "formulated_at": h.formulated_at,
                        "updated_at": h.updated_at,
                        "metadata": h.metadata,
                    }
                    for h in self._hypotheses.values()
                ]
            }
            with open(self.storage_path, "w", encoding="utf-8") as f:
                json.dump(payload, f, indent=2, ensure_ascii=False)
        except Exception:
            pass

    def register_hypothesis(
        self, hypothesis: Hypothesis, save: bool = True
    ) -> Hypothesis:
        """Registers or updates a hypothesis."""
        self._hypotheses[hypothesis.hypo_id] = hypothesis
        if save:
            self._save_state()
        return hypothesis

    def get_hypothesis(self, hypo_id: str) -> Optional[Hypothesis]:
        return self._hypotheses.get(hypo_id)

    def list_hypotheses(
        self, status: Optional[HypothesisStatus] = None
    ) -> List[Hypothesis]:
        """Lists hypotheses with optional status filtering."""
        if status:
            return [h for h in self._hypotheses.values() if h.status == status]
        return list(self._hypotheses.values())

    def formulate_hypotheses(self, records: List[Dict[str, Any]]) -> List[Hypothesis]:
        """Autonomously formulates hypotheses by discovering thematic correlations in ingested literature."""
        new_hypotheses: List[Hypothesis] = []
        corpus_text = " ".join(
            (
                r.get("title", "")
                + " "
                + r.get("summary", "")
                + " "
                + " ".join(r.get("tags", []))
            ).lower()
            for r in records
        )

        for template in self.HYPOTHESIS_TEMPLATES:
            # Check if trigger keywords are prevalent in corpus
            matches = sum(
                1 for kw in template["trigger_keywords"] if kw.lower() in corpus_text
            )
            if matches >= 1:
                hypo_id = template["id_prefix"]
                if hypo_id not in self._hypotheses:
                    hypo = Hypothesis(
                        hypo_id=hypo_id,
                        statement=template["statement"],
                        target_topics=template["target_topics"],
                        confidence_score=0.5,
                        status=HypothesisStatus.FORMULATED,
                        metadata={"trigger_matches": matches},
                    )
                    self.register_requirement_hypothesis(hypo)
                    new_hypotheses.append(hypo)

        return new_hypotheses

    def register_requirement_hypothesis(self, hypo: Hypothesis) -> None:
        self._hypotheses[hypo.hypo_id] = hypo
        self._save_state()

    def _resolve_patterns(self, hypothesis: Hypothesis) -> tuple[List[str], List[str]]:
        """Resolves support and refute regex patterns for a given hypothesis."""
        for tmpl in self.HYPOTHESIS_TEMPLATES:
            if (
                tmpl["statement"] == hypothesis.statement
                or tmpl["id_prefix"] == hypothesis.hypo_id
            ):
                return tmpl["support_patterns"], tmpl["refute_patterns"]
        return [r"vulnerability", r"exploit", r"attack"], [
            r"defense",
            r"mitigation",
            r"secure",
        ]

    def _extract_evidence_for_paper(
        self,
        hypothesis: Hypothesis,
        record: Dict[str, Any],
        support_patterns: List[str],
        refute_patterns: List[str],
        existing_supp: set[str],
        existing_ref: set[str],
    ) -> tuple[float, float]:
        """Extracts support or refute evidence from a single paper record."""
        paper_id = str(record.get("id", ""))
        text = (
            record.get("title", "")
            + " "
            + record.get("summary", "")
            + " "
            + record.get("abstract", "")
        ).lower()
        delta_s, delta_r = 0.0, 0.0

        for pat in support_patterns:
            if re.search(pat, text, re.IGNORECASE) and paper_id not in existing_supp:
                ev = HypothesisEvidence(
                    evidence_id=f"ev_supp_{paper_id}_{len(hypothesis.supporting_evidence)+1}",
                    paper_id=paper_id,
                    excerpt=record.get("summary", record.get("title", ""))[:200],
                    polarity="support",
                    relevance_score=1.0,
                )
                hypothesis.supporting_evidence.append(ev)
                existing_supp.add(paper_id)
                delta_s += 1.0
                break

        for pat in refute_patterns:
            if re.search(pat, text, re.IGNORECASE) and paper_id not in existing_ref:
                ev = HypothesisEvidence(
                    evidence_id=f"ev_ref_{paper_id}_{len(hypothesis.refuting_evidence)+1}",
                    paper_id=paper_id,
                    excerpt=record.get("summary", record.get("title", ""))[:200],
                    polarity="refute",
                    relevance_score=1.0,
                )
                hypothesis.refuting_evidence.append(ev)
                existing_ref.add(paper_id)
                delta_r += 1.0
                break

        return delta_s, delta_r

    def _update_lifecycle_status(self, hypothesis: Hypothesis) -> None:
        """Determines updated lifecycle status based on evidence count and confidence."""
        total = len(hypothesis.supporting_evidence) + len(hypothesis.refuting_evidence)
        if total >= 3:
            if hypothesis.confidence_score >= 0.70:
                hypothesis.status = HypothesisStatus.SUPPORTED
            elif hypothesis.confidence_score <= 0.30:
                hypothesis.status = HypothesisStatus.REFUTED
            else:
                hypothesis.status = HypothesisStatus.INCONCLUSIVE
        elif total > 0:
            hypothesis.status = HypothesisStatus.INVESTIGATING

    def evaluate_hypothesis(
        self, hypothesis: Hypothesis, records: List[Dict[str, Any]]
    ) -> Hypothesis:
        """Evaluates a hypothesis against newly collected records and updates Bayesian confidence."""
        supp_pats, ref_pats = self._resolve_patterns(hypothesis)
        existing_supp = {ev.paper_id for ev in hypothesis.supporting_evidence}
        existing_ref = {ev.paper_id for ev in hypothesis.refuting_evidence}

        support_weight = sum(
            ev.relevance_score for ev in hypothesis.supporting_evidence
        )
        refute_weight = sum(ev.relevance_score for ev in hypothesis.refuting_evidence)

        for r in records:
            ds, dr = self._extract_evidence_for_paper(
                hypothesis, r, supp_pats, ref_pats, existing_supp, existing_ref
            )
            support_weight += ds
            refute_weight += dr

        # Calculate updated confidence score: C = (0.5 + S) / (1.0 + S + R)
        new_conf = (0.5 + support_weight) / (1.0 + support_weight + refute_weight)
        hypothesis.confidence_score = round(max(0.0, min(1.0, new_conf)), 3)
        hypothesis.updated_at = datetime.now(timezone.utc).isoformat()

        self._update_lifecycle_status(hypothesis)
        self._save_state()
        return hypothesis

    def evaluate_all(self, records: List[Dict[str, Any]]) -> List[Hypothesis]:
        """Evaluates all registered hypotheses against available records."""
        # Formulate new hypotheses if triggers exist
        self.formulate_hypotheses(records)

        evaluated: List[Hypothesis] = []
        for hypo in list(self._hypotheses.values()):
            evaluated.append(self.evaluate_hypothesis(hypo, records))
        return evaluated

    def synthesize_hypothesis_report(self, hypothesis: Hypothesis) -> str:
        """Synthesizes a 100% Japanese structured markdown investigation report."""
        status_labels = {
            HypothesisStatus.FORMULATED: "定式化済 (未検証)",
            HypothesisStatus.INVESTIGATING: "調査検証中 (証拠収集中)",
            HypothesisStatus.SUPPORTED: "立証・支持 (学術的・実証的根拠あり)",
            HypothesisStatus.REFUTED: "反証・棄却 (有効な防御策または成立困難)",
            HypothesisStatus.INCONCLUSIVE: "証拠拮抗 (結論保留)",
        }
        status_desc = status_labels.get(hypothesis.status, "調査中")

        lines = [
            f"# 🔬 学術仮説検証レポート: [{hypothesis.hypo_id}]",
            "",
            "| 項目 | 内容 |",
            "| :--- | :--- |",
            f"| **仮説命題** | **{hypothesis.statement}** |",
            f"| **検証ステータス** | **{status_desc}** |",
            f"| **確信度スコア** | **{hypothesis.confidence_score * 100:.1f}%** |",
            f"| **関連ドメイン** | {', '.join(hypothesis.target_topics)} |",
            f"| **最終評価日時** | {hypothesis.updated_at} |",
            "",
            "## 1. 支持証拠 (Supporting Evidence)",
        ]

        if not hypothesis.supporting_evidence:
            lines.append("- *現時点で直接的な支持証拠となる論文は観測されていません。*")
        else:
            lines.append("| 論文 ID | 証拠抜粋 / 観測所見 | 関連度 |")
            lines.append("| :---: | :--- | :---: |")
            for ev in hypothesis.supporting_evidence:
                lines.append(
                    f"| `{ev.paper_id}` | {ev.excerpt} | {ev.relevance_score:.1f} |"
                )

        lines.extend(
            [
                "",
                "## 2. 反証証拠・防御策 (Refuting Evidence & Defenses)",
            ]
        )

        if not hypothesis.refuting_evidence:
            lines.append(
                "- *現時点で反証または完全無力化を示す論文は観測されていません。*"
            )
        else:
            lines.append("| 論文 ID | 防御・反証抜粋 | 関連度 |")
            lines.append("| :---: | :--- | :---: |")
            for ev in hypothesis.refuting_evidence:
                lines.append(
                    f"| `{ev.paper_id}` | {ev.excerpt} | {ev.relevance_score:.1f} |"
                )

        lines.extend(
            [
                "",
                "## 3. セキュリティ組織・CISOへの示唆 (Strategic Implications)",
            ]
        )
        if hypothesis.status == HypothesisStatus.SUPPORTED:
            lines.append(
                f"- 🚨 **即時対策推奨**: 本仮説は複数の学術論文（{len(hypothesis.supporting_evidence)}件）により実効性が確認されています。"
                "対象領域のセキュリティ防御方針を直ちに Tactical レベルへ引き上げてください。"
            )
        elif hypothesis.status == HypothesisStatus.REFUTED:
            lines.append(
                "- 🛡️ **リスク低**: 本攻撃手法は既存の標準防御策により有効に緩和可能であることが確認されています。"
            )
        else:
            lines.append(
                "- ⏳ **継続監視**: 証拠が拮抗または収集中です。次回サイクルの PIR に特化クエリを注入し深掘り調査を継続します。"
            )

        return "\n".join(lines)

    def generate_investigation_queries(self, hypothesis: Hypothesis) -> List[str]:
        """Generates deep-dive search queries to resolve inconclusive hypotheses."""
        queries: List[str] = []
        for topic in hypothesis.target_topics:
            queries.append(f"{topic} exploit proof of concept")
            queries.append(f"{topic} defense benchmark evaluation")
        return queries
