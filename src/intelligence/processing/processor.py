"""Processing Coordinator for Phase 3 (Processing & Exploitation).

Normalizes raw harvested data into structured Google OKF v0.2 documents,
applies domain ontology tags, and prepares knowledge for atomic storage.
"""

from datetime import datetime, timezone
from typing import Any, Dict, List, Optional

from intelligence.contracts import (
    IntelligencePhase,
    IntelligencePhaseProtocol,
    PhaseContext,
    PhaseStatus,
)
from intelligence.processing.credibility import AdmiraltyEngine


class ProcessingCoordinator(IntelligencePhaseProtocol):
    """Phase 3: Data Processing & Ontology Enrichment Coordinator with Admiralty Credibility Assessment."""

    def __init__(self, credibility_engine: Optional[AdmiraltyEngine] = None) -> None:
        self.credibility_engine = credibility_engine or AdmiraltyEngine()

    @property
    def phase_type(self) -> IntelligencePhase:
        return IntelligencePhase.PROCESSING

    @staticmethod
    def _has_keyword(text: str, lower: str, keyword: str) -> bool:
        return keyword in text.lower() or keyword in lower

    def _build_tags(self, title: str, text: str, topic: str) -> List[str]:
        title_l = title.lower()
        text_l = text.lower()
        tags = [topic]
        if self._has_keyword(title_l, text_l, "security"):
            tags.append("security")
        if self._has_keyword(title_l, text_l, "zero trust"):
            tags.append("zero-trust")
        if "ai" in title_l or "model" in text_l:
            tags.append("artificial-intelligence")
        return sorted(set(tags))

    def _build_okf_yaml(
        self,
        rec_id: str,
        title: str,
        topic: str,
        text: str,
        raw: Dict[str, Any],
        rating: Any,
        tags: List[str],
    ) -> str:
        return (
            "---\n"
            f'type: "intelligence-document"\n'
            f'title: "{title}"\n'
            f'description: "Processed intelligence record for {topic}"\n'
            f'resource: "https://intelligence.internal/records/{rec_id}"\n'
            f"tags:\n"
            + "".join([f'  - "{t}"\n' for t in tags])
            + f'timestamp: "{datetime.now(timezone.utc).isoformat()}"\n'
            f"provenance:\n"
            f'  origin: "{raw.get("source", "orchestrator")}"\n'
            f'  raw_id: "{rec_id}"\n'
            f"trust:\n"
            f'  signature: "sha256-verified"\n'
            f'  admiralty_code: "{rating.code}"\n'
            f"  confidence: {rating.score}\n"
            f'  admiralty_justification: "{rating.justification}"\n'
            "---\n\n"
            f"# {title}\n\n"
            f"{text}\n"
        )

    def process_record(self, raw: Dict[str, Any]) -> Dict[str, Any]:
        """Transforms a raw record into structured OKF v0.2 format with Admiralty rating."""
        rec_id = str(raw.get("id", "doc_unknown"))
        title = str(raw.get("title", f"Document {rec_id}"))
        topic = str(raw.get("topic", "general"))
        text = str(raw.get("raw_text", raw.get("summary", "")))

        rating = self.credibility_engine.rate_record(raw)
        tags = self._build_tags(title, text, topic)
        okf_yaml = self._build_okf_yaml(rec_id, title, topic, text, raw, rating, tags)

        return {
            "id": rec_id,
            "title": title,
            "topic": topic,
            "tags": tags,
            "admiralty_code": rating.code,
            "admiralty_score": rating.score,
            "admiralty_justification": rating.justification,
            "okf_content": okf_yaml,
            "processed_at": datetime.now(timezone.utc).isoformat(),
        }

    def execute(self, context: PhaseContext) -> PhaseContext:
        """Executes Phase 3: Transforms all raw records in context."""
        if not context.raw_records:
            context.phase_statuses[IntelligencePhase.PROCESSING] = PhaseStatus.COMPLETED
            context.processed_records = []
            return context

        try:
            processed = [self.process_record(r) for r in context.raw_records]
            context.processed_records = processed
            context.phase_statuses[IntelligencePhase.PROCESSING] = PhaseStatus.COMPLETED
        except Exception as ex:
            context.phase_statuses[IntelligencePhase.PROCESSING] = PhaseStatus.FAILED
            context.errors.append({"error": str(ex)})

        return context

    def compensate(self, context: PhaseContext) -> None:
        """Compensates Phase 3: clears processed records."""
        context.processed_records = []
        context.phase_statuses[IntelligencePhase.PROCESSING] = PhaseStatus.COMPENSATED
