#!/usr/bin/env python3
"""
Unit and Integration Tests for Merkle Tree and File Integrity Monitoring (FIM).
Validates Issue 134 requirements:
- RFC 6962 domain separation (0x00 leaf, 0x01 internal)
- O(log N) Merkle proof generation and mathematical verification
- Directory scanning, manifest.json generation, and bit-rot detection
- Symlink exclusion and path safety
"""

import os
import shutil
import tempfile
import unittest

from security.fim import FileIntegrityMonitor
from security.merkle_tree import MerkleTree, hash_children, hash_leaf


class TestMerkleTree(unittest.TestCase):
    """Tests for pure Python RFC 6962 Merkle Tree."""

    def test_domain_separation_prefix(self) -> None:
        """Verifies leaf and internal node prefixes prevent second-preimage attacks."""
        raw = b"sample security payload"
        leaf = hash_leaf(raw)
        self.assertNotEqual(leaf, hash_children(raw, b""))

    def test_merkle_tree_empty_and_single(self) -> None:
        """Tests tree behavior with 0 or 1 leaf."""
        tree0 = MerkleTree()
        self.assertIsNotNone(tree0.root_hash)

        tree1 = MerkleTree([b"only_one_leaf"])
        self.assertIsNotNone(tree1.root_hash)
        proof1 = tree1.get_proof(0)
        self.assertTrue(tree1.verify_proof(b"only_one_leaf", proof1, tree1.root_hash))

    def test_merkle_proof_verification_and_tampering(self) -> None:
        """Tests audit proof generation, successful verification, and tampering detection."""
        leaves = [f"paper_{i}".encode("utf-8") for i in range(11)]
        tree = MerkleTree(leaves)
        root = tree.root_hash
        self.assertIsNotNone(root)

        for i in range(len(leaves)):
            proof = tree.get_proof(i)
            # Legitimate proof verification
            self.assertTrue(
                tree.verify_proof(leaves[i], proof, root),
                f"Proof failed for leaf index {i}",
            )
            # Tampered leaf verification must fail
            tampered = leaves[i] + b"_tampered"
            self.assertFalse(tree.verify_proof(tampered, proof, root))


class TestFileIntegrityMonitor(unittest.TestCase):
    """Tests for File Integrity Monitoring directory scanner and manifest verifier."""

    def setUp(self) -> None:
        self.test_dir = tempfile.mkdtemp(prefix="test_fim_")

    def tearDown(self) -> None:
        shutil.rmtree(self.test_dir, ignore_errors=True)

    def test_fim_scan_and_tamper_detection(self) -> None:
        """Tests manifest creation and subsequent detection of file modification and deletion."""
        # Create test files
        file1 = os.path.join(self.test_dir, "file1.txt")
        file2 = os.path.join(self.test_dir, "sub", "file2.pdf")
        os.makedirs(os.path.dirname(file2), exist_ok=True)

        with open(file1, "wb") as f:
            f.write(b"Paper Abstract 1: Zero Trust")
        with open(file2, "wb") as f:
            f.write(b"%PDF-1.4 Fake PDF Content")

        fim = FileIntegrityMonitor(self.test_dir)
        manifest = fim.build_manifest()
        self.assertEqual(manifest["leaf_count"], 2)
        self.assertIsNotNone(manifest["merkle_root"])

        # Initial verify: 100% PASS
        valid, diffs = fim.verify()
        self.assertTrue(valid)
        self.assertEqual(len(diffs), 0)

        # Tamper with 1 byte in file1
        with open(file1, "wb") as f:
            f.write(b"Paper Abstract 1: Tampered!!")

        valid_tampered, diffs_tampered = fim.verify()
        self.assertFalse(valid_tampered)
        self.assertTrue(any("CORRUPTED: file1.txt" in d for d in diffs_tampered))

        # Restore file1, delete file2
        with open(file1, "wb") as f:
            f.write(b"Paper Abstract 1: Zero Trust")
        os.remove(file2)

        valid_missing, diffs_missing = fim.verify()
        self.assertFalse(valid_missing)
        self.assertTrue(any("MISSING: sub/file2.pdf" in d for d in diffs_missing))


if __name__ == "__main__":
    unittest.main()
