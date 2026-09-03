#!/usr/bin/env python3
"""
Unit Tests for STIX 2.1 Threat Knowledge Graph Generation Pipeline.
Validates Issue 127 requirements:
- OASIS STIX 2.1 spec conformance (spec_version='2.1', RFC 4122 UUID IDs)
- SDOs (AttackPattern, Vulnerability, CourseOfAction, Identity)
- SROs (exploits, mitigates, cites) with valid source_ref and target_ref
- STIX JSON Bundle generation and serialization
"""

import json
import unittest

from ontology.stix import STIXGenerator, generate_stix_id


class TestSTIXGenerator(unittest.TestCase):
    """Tests for STIX 2.1 SDO, SRO, Bundle, and Generator."""

    def test_stix_id_format(self) -> None:
        """Verifies RFC 4122 compliance of generated IDs."""
        id1 = generate_stix_id("attack-pattern")
        self.assertTrue(id1.startswith("attack-pattern--"))
        self.assertEqual(len(id1), len("attack-pattern--") + 36)

        id_seeded1 = generate_stix_id("vulnerability", seed="CWE-89")
        id_seeded2 = generate_stix_id("vulnerability", seed="CWE-89")
        self.assertEqual(id_seeded1, id_seeded2)

    def test_stix_generator_from_paper(self) -> None:
        """Verifies STIX 2.1 bundle synthesis from paper metadata."""
        bundle = STIXGenerator.generate_from_paper(
            paper_id="2401.12345",
            title="Analysis of Memory Corruption and Heap Overflow",
            abstract="This paper uncovers an out-of-bounds write heap overflow (CWE-787) exploitable via T1059.",
            cwes=["CWE-787"],
            attcks=["T1059"],
            defenses=["ASLR Hardening and Guard Pages"],
            authors=["Alice Cryptographer"],
        )

        self.assertEqual(bundle.type, "bundle")
        self.assertTrue(bundle.id.startswith("bundle--"))
        self.assertGreaterEqual(bundle.object_count, 4)

        raw_json = bundle.to_json()
        parsed = json.loads(raw_json)
        self.assertEqual(parsed["type"], "bundle")
        self.assertEqual(len(parsed["objects"]), bundle.object_count)

        # Verify all SRO references exist in bundle
        all_ids = {obj["id"] for obj in parsed["objects"]}
        for obj in parsed["objects"]:
            self.assertEqual(obj["spec_version"], "2.1")
            if obj["type"] == "relationship":
                self.assertIn(obj["source_ref"], all_ids)
                self.assertIn(obj["target_ref"], all_ids)
                self.assertIn(
                    obj["relationship_type"],
                    ["exploits", "mitigates", "targets", "cites"],
                )


if __name__ == "__main__":
    unittest.main()
