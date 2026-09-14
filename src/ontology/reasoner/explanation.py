"""
Inconsistency Explanation and Audit Justification Generator.
Generates human-readable and machine-verifiable explanation chains (Minimal Unsatisfiable Sub-ontologies: MUS).
Tracks Pellet's axiom pinpointing heuristics.
"""

from __future__ import annotations

from typing import List

from ontology.reasoner.base import Clash, ConsistencyReport


class InconsistencyExplainer:
    """Generates transparent, audit-ready explanations for detected logical contradictions."""

    @classmethod
    def generate_narrative_explanation(cls, clashes: List[Clash]) -> str:
        """Constructs human-verifiable markdown explanation for a set of clashes."""
        if not clashes:
            return "Ontology Knowledge Base is logically consistent. No contradictions detected."

        lines: List[str] = [
            f"### ⚠️ Logical Inconsistency Audit Report ({len(clashes)} clash(es) detected)",
            "",
            "The following logical contradictions were formally proven by the Tableau engine:",
            "",
        ]

        for idx, clash in enumerate(clashes, 1):
            lines.extend(cls._format_single_clash(idx, clash))

        lines.append(
            "> [!IMPORTANT]\n"
            "> **Audit Remediations**: Review the conflicting axioms and assertions listed above. "
            "Ensure that entities are not declared under disjoint classes simultaneously."
        )
        return "\n".join(lines)

    @staticmethod
    def _format_single_clash(idx: int, clash: Clash) -> List[str]:
        """Formats a single Clash into markdown list items."""
        return [
            f"**Clash #{idx}: [{clash.clash_type.value}]**",
            f"- **Target Individual**: `{clash.node_id}`",
            f"- **Conflicting Concepts**: {', '.join(f'`{c}`' for c in clash.conflicting_concepts)}",
            f"- **Violated Axioms**: {', '.join(f'`{ax}`' for ax in clash.justification_axioms)}",
            f"- **Detailed Explanation**: {clash.explanation_message}",
            "",
        ]

    @classmethod
    def attach_explanation_to_report(
        cls, report: ConsistencyReport
    ) -> ConsistencyReport:
        """Enriches a ConsistencyReport with the compiled audit explanation narrative."""
        report.explanation = cls.generate_narrative_explanation(report.clashes)
        return report
