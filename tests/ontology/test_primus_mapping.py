#!/usr/bin/env python3
"""
Unit Tests for PRIMUS CTI Precision Mapping Engine.
Validates Issue 128 requirements:
- CTI-RCM: Root Cause Mapping to CWE taxonomy (explicit & inferred)
- CTI-VSP: CVSS v3.1 exact mathematical score calculation and severity inference
- CTI-ATE: Attack Technique Extraction to MITRE ATT&CK & ATLAS
- Provenance Tiering (Gold vs Silver, confidence thresholds, rejection)
"""

import unittest

from ontology.primus import (
    AttackTechniqueExtractor,
    ProvenanceTier,
    RootCauseMapper,
    VulnerabilitySeverityPredictor,
    assign_provenance,
)


class TestPRIMUSMapping(unittest.TestCase):
    """Tests for PRIMUS CTI components."""

    def test_provenance_tier_assignment(self) -> None:
        """Verifies Gold, Silver, and Reject thresholds."""
        gold_rec = assign_provenance(
            "CWE-787", "CWE", 0.95, "snippet", is_explicit=True
        )
        self.assertIsNotNone(gold_rec)
        self.assertEqual(gold_rec.tier, ProvenanceTier.GOLD)

        silver_rec = assign_provenance(
            "CWE-787", "CWE", 0.75, "snippet", is_explicit=False
        )
        self.assertIsNotNone(silver_rec)
        self.assertEqual(silver_rec.tier, ProvenanceTier.SILVER)

        reject_rec = assign_provenance(
            "CWE-787", "CWE", 0.40, "snippet", is_explicit=False
        )
        self.assertIsNone(reject_rec)

    def test_cti_rcm_explicit_and_inferred(self) -> None:
        """Tests CTI-RCM extraction of explicit CWE IDs and natural language root causes."""
        text_explicit = "We analyzed CVE-2024-1234 which is classified under CWE-89."
        recs_explicit = RootCauseMapper.map_root_causes(text_explicit)
        self.assertTrue(
            any(
                r.mapped_id == "CWE-89" and r.tier == ProvenanceTier.GOLD
                for r in recs_explicit
            )
        )

        text_inferred = (
            "The attack exploits an out-of-bounds write leading to heap overflow."
        )
        recs_inferred = RootCauseMapper.map_root_causes(text_inferred)
        self.assertTrue(
            any(
                r.mapped_id == "CWE-787" and r.tier == ProvenanceTier.SILVER
                for r in recs_inferred
            )
        )

    def test_cti_vsp_cvss_v31_calculation(self) -> None:
        """
        Verifies CVSS v3.1 mathematical score calculation against official test vectors:
        1. Critical: CVSS:3.1/AV:N/AC:L/PR:N/UI:N/S:U/C:H/I:H/A:H -> 9.8
        2. High: CVSS:3.1/AV:N/AC:L/PR:L/UI:N/S:U/C:H/I:N/A:N -> 6.5 Medium or High
        """
        vec, score, rating = VulnerabilitySeverityPredictor.calculate_cvss_score(
            av="N", ac="L", pr="N", ui="N", s="U", c="H", i="H", a="H"
        )
        self.assertEqual(score, 9.8)
        self.assertEqual(rating, "CRITICAL")
        self.assertIn("AV:N", vec)

        # Predict from text
        text_rce = (
            "This unauthenticated remote code execution vulnerability allows "
            "complete takeover over the internet."
        )
        pred = VulnerabilitySeverityPredictor.predict_severity(text_rce)
        self.assertIsNotNone(pred)
        self.assertEqual(pred.severity_rating, "CRITICAL")
        self.assertEqual(pred.base_score, 9.8)

    def test_cti_ate_attack_technique_extraction(self) -> None:
        """Tests CTI-ATE extraction of MITRE ATT&CK and ATLAS IDs."""
        text_explicit = (
            "Adversaries leverage T1059 and AML.T0054 during adversarial testing."
        )
        recs_explicit = AttackTechniqueExtractor.extract_techniques(text_explicit)
        ids = [r.mapped_id for r in recs_explicit]
        self.assertIn("T1059", ids)
        self.assertIn("AML.T0054", ids)

        text_inferred = "The adversary utilized spearphishing emails with malicious attachments to gain entry."
        recs_inferred = AttackTechniqueExtractor.extract_techniques(text_inferred)
        ids_inferred = [r.mapped_id for r in recs_inferred]
        self.assertIn("T1566", ids_inferred)


if __name__ == "__main__":
    unittest.main()
