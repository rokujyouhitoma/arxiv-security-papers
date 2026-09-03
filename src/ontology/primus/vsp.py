#!/usr/bin/env python3
"""
PRIMUS CTI-VSP (Vulnerability Severity Prediction).
Infers CVSS v3.1 metric vectors from natural language vulnerability impact descriptions
and implements the exact FIRST.org CVSS v3.1 Base Score mathematical formula.
"""

from __future__ import annotations

import math
import re
from dataclasses import dataclass
from typing import Any, Dict, Optional, Tuple

from .provenance import ProvenanceRecord, assign_provenance


def roundup(val: float) -> float:
    """Rounds floating value up to the nearest 1 decimal place per CVSS v3.1 specification."""
    int_val = int(round(val * 100000))
    if int_val % 10000 == 0:
        return int_val / 100000.0
    return math.floor(int_val / 10000.0 + 1) / 10.0


@dataclass
class CVSSPrediction:
    """Represents an inferred CVSS v3.1 vulnerability rating."""

    vector_string: str
    base_score: float
    severity_rating: str
    provenance: ProvenanceRecord

    def to_dict(self) -> Dict[str, Any]:
        return {
            "vector_string": self.vector_string,
            "base_score": self.base_score,
            "severity_rating": self.severity_rating,
            "provenance": self.provenance.to_dict(),
        }


class VulnerabilitySeverityPredictor:
    """CTI-VSP Engine: computes CVSS v3.1 base score and predicts severity from text."""

    @classmethod
    def _cvss_impact(cls, iss: float, s: str) -> float:
        if s == "U":
            return 6.42 * iss
        return 7.52 * (iss - 0.029) - 3.25 * ((iss - 0.02) ** 15)

    @classmethod
    def _cvss_base_score(cls, impact: float, exploitability: float, s: str) -> float:
        if impact <= 0:
            return 0.0
        if s == "U":
            return min(roundup(impact + exploitability), 10.0)
        return min(roundup(1.08 * (impact + exploitability)), 10.0)

    @classmethod
    def _cvss_rating(cls, score: float) -> str:
        if score >= 9.0:
            return "CRITICAL"
        if score >= 7.0:
            return "HIGH"
        if score >= 4.0:
            return "MEDIUM"
        if score > 0.0:
            return "LOW"
        return "NONE"

    @classmethod
    def calculate_cvss_score(
        cls,
        av: str = "N",
        ac: str = "L",
        pr: str = "N",
        ui: str = "N",
        s: str = "U",
        c: str = "H",
        i: str = "H",
        a: str = "H",
    ) -> Tuple[str, float, str]:
        """Calculates official CVSS v3.1 base score from individual metric values."""
        av_w = {"N": 0.85, "A": 0.62, "L": 0.55, "P": 0.20}.get(av, 0.85)
        ac_w = {"L": 0.77, "H": 0.44}.get(ac, 0.77)
        ui_w = {"N": 0.85, "R": 0.62}.get(ui, 0.85)
        cia_w = {"N": 0.0, "L": 0.22, "H": 0.56}
        c_w, i_w, a_w = cia_w.get(c, 0.56), cia_w.get(i, 0.56), cia_w.get(a, 0.56)

        pr_w = (
            {"N": 0.85, "L": 0.62, "H": 0.27}.get(pr, 0.85)
            if s == "U"
            else {"N": 0.85, "L": 0.68, "H": 0.50}.get(pr, 0.85)
        )

        iss = 1.0 - ((1.0 - c_w) * (1.0 - i_w) * (1.0 - a_w))
        impact = cls._cvss_impact(iss, s)
        exploitability = 8.22 * av_w * ac_w * pr_w * ui_w
        base_score = cls._cvss_base_score(impact, exploitability, s)
        rating = cls._cvss_rating(base_score)
        vector_str = f"CVSS:3.1/AV:{av}/AC:{ac}/PR:{pr}/UI:{ui}/S:{s}/C:{c}/I:{i}/A:{a}"
        return vector_str, base_score, rating

    @classmethod
    def _infer_av(cls, text: str) -> str:
        if re.search(
            r"(?i)\b(remote|network|over the internet|unauthenticated api|web)\b", text
        ):
            return "N"
        if re.search(r"(?i)\b(adjacent|bluetooth|wifi|lan)\b", text):
            return "A"
        if re.search(
            r"(?i)\b(local|privilege escalation|root|physical access)\b", text
        ):
            return "L"
        return "N"

    @classmethod
    def _infer_pr(cls, text: str) -> str:
        if re.search(
            r"(?i)\b(unauthenticated|no credentials|no auth required)\b", text
        ):
            return "N"
        if re.search(r"(?i)\b(admin privilege|root required)\b", text):
            return "H"
        return "N"

    @classmethod
    def _infer_cia(cls, text: str) -> Tuple[str, str, str]:
        if re.search(
            r"(?i)\b(remote code execution|arbitrary code execution|complete takeover)\b",
            text,
        ):
            return "H", "H", "H"
        if re.search(r"(?i)\b(denial of service|dos|crash)\b", text):
            return "N", "N", "H"
        if re.search(
            r"(?i)\b(information disclosure|data leak|memory leak|read sensitive)\b",
            text,
        ):
            return "H", "N", "N"
        return "H", "H", "N"

    @classmethod
    def predict_severity(cls, text: str) -> Optional[CVSSPrediction]:
        """Infers attack prerequisites and impact CIA from academic vulnerability description."""
        av = cls._infer_av(text)
        ac = (
            "H"
            if re.search(
                r"(?i)\b(race condition|complex timing|difficult setup|rarely)\b", text
            )
            else "L"
        )
        pr = cls._infer_pr(text)
        ui = (
            "R"
            if re.search(
                r"(?i)\b(phishing|clickjacking|user click|victim opens)\b", text
            )
            else "N"
        )
        s = (
            "C"
            if re.search(
                r"(?i)\b(escape|sandbox escape|container breakout|vm escape)\b", text
            )
            else "U"
        )
        c, i, a = cls._infer_cia(text)

        vec, score, rating = cls.calculate_cvss_score(av, ac, pr, ui, s, c, i, a)
        rec = assign_provenance(
            mapped_id=f"{rating}:{score}",
            category="CVSS",
            confidence=0.78,
            evidence_snippet=f"AV:{av} AC:{ac} PR:{pr} UI:{ui} S:{s} Impact:{c}/{i}/{a}",
            is_explicit=False,
            source_rule="CTI-VSP-Inference",
        )
        if not rec:
            return None

        return CVSSPrediction(
            vector_string=vec,
            base_score=score,
            severity_rating=rating,
            provenance=rec,
        )
