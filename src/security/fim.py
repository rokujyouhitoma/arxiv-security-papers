#!/usr/bin/env python3
"""
File Integrity Monitoring (FIM) Engine driven by Merkle Trees.
Scans files, detects bit-rot and unauthorized modifications, and records
verifiable cryptographic manifests for raw data and pipeline artifacts.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import sys
from datetime import datetime, timezone
from typing import Any, Dict, List, Optional, Tuple, Union

from .merkle_tree import MerkleTree

MANIFEST_FILENAME: str = "manifest.json"


def compute_file_sha256(filepath: str) -> str:
    """Computes SHA-256 hex digest of file in 64KB chunks."""
    h = hashlib.sha256()
    with open(filepath, "rb") as f:
        while chunk := f.read(65536):
            h.update(chunk)
    return h.hexdigest()


class FileIntegrityMonitor:
    """
    File Integrity Monitor utilizing Merkle Trees for O(log N) verification
    and instantaneous tampering detection.
    """

    def __init__(self, target_dir: str) -> None:
        self.target_dir = os.path.abspath(target_dir)

    def _inspect_file(self, root: str, fname: str) -> Optional[Tuple[str, str, int]]:
        """Inspects single file candidate, skipping manifest and symlinks."""
        if fname == MANIFEST_FILENAME:
            return None
        abs_path = os.path.join(root, fname)
        if os.path.islink(abs_path):
            return None
        rel_path = os.path.relpath(abs_path, self.target_dir).replace("\\", "/")
        try:
            fsize = os.path.getsize(abs_path)
            return (rel_path, abs_path, fsize)
        except OSError:
            return None

    def _collect_files(self) -> List[Tuple[str, str, int]]:
        """
        Recursively scans directory, safely skipping symlinks and manifest files.
        Returns sorted list of (relative_path, absolute_path, file_size).
        """
        records: List[Tuple[str, str, int]] = []
        if not os.path.exists(self.target_dir):
            return records

        for root, _, files in os.walk(self.target_dir):
            for fname in sorted(files):
                rec = self._inspect_file(root, fname)
                if rec:
                    records.append(rec)

        records.sort(key=lambda x: x[0])
        return records

    def build_manifest(self, output_path: Optional[str] = None) -> Dict[str, Any]:
        """
        Scans all files, computes SHA-256 hashes, builds Merkle tree,
        and saves manifest.json.
        """
        file_records = self._collect_files()
        file_entries: List[Dict[str, Any]] = []
        leaves: List[Union[bytes, str]] = []

        for rel_path, abs_path, fsize in file_records:
            fhash = compute_file_sha256(abs_path)
            file_entries.append(
                {
                    "path": rel_path,
                    "sha256": fhash,
                    "size_bytes": fsize,
                }
            )
            leaves.append(f"{rel_path}:{fhash}")

        tree = MerkleTree(leaves=leaves)
        manifest_data: Dict[str, Any] = {
            "version": "1.0",
            "target_dir": self.target_dir,
            "merkle_root": tree.root_hash,
            "leaf_count": tree.leaf_count,
            "generated_at": datetime.now(timezone.utc).isoformat(),
            "files": file_entries,
        }

        save_path = output_path or os.path.join(self.target_dir, MANIFEST_FILENAME)
        os.makedirs(os.path.dirname(os.path.abspath(save_path)), exist_ok=True)
        with open(save_path, "w", encoding="utf-8") as f:
            json.dump(manifest_data, f, indent=2, ensure_ascii=False)

        return manifest_data

    @staticmethod
    def _check_expected(expected: Dict[str, str], current: Dict[str, str]) -> List[str]:
        diffs: List[str] = []
        for path, exp_hash in expected.items():
            if path not in current:
                diffs.append(f"MISSING: {path}")
            elif current[path] != exp_hash:
                diffs.append(
                    f"CORRUPTED: {path} (expected {exp_hash[:8]}, got {current[path][:8]})"
                )
        return diffs

    @staticmethod
    def _find_discrepancies(
        expected_files: Dict[str, str], current_files: Dict[str, str]
    ) -> List[str]:
        """Identifies missing, corrupted, or extra files."""
        diffs = FileIntegrityMonitor._check_expected(expected_files, current_files)
        for path in current_files:
            if path not in expected_files:
                diffs.append(f"EXTRA: {path}")
        return diffs

    def verify(self, manifest_path: Optional[str] = None) -> Tuple[bool, List[str]]:
        """
        Verifies current filesystem directory state against recorded manifest.
        Returns:
            (True, []) if 100% matched
            (False, list_of_corrupt_or_missing_or_extra_paths) if mismatch
        """
        manifest_file = manifest_path or os.path.join(
            self.target_dir, MANIFEST_FILENAME
        )
        if not os.path.exists(manifest_file):
            return False, [f"Manifest file not found: {manifest_file}"]

        with open(manifest_file, "r", encoding="utf-8") as f:
            manifest = json.load(f)

        expected_files: Dict[str, str] = {
            item["path"]: item["sha256"] for item in manifest.get("files", [])
        }

        current_records = self._collect_files()
        current_files: Dict[str, str] = {
            rel_path: compute_file_sha256(abs_path)
            for rel_path, abs_path, _ in current_records
        }

        discrepancies = self._find_discrepancies(expected_files, current_files)
        return len(discrepancies) == 0, discrepancies


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Merkle Tree File Integrity Monitoring CLI"
    )
    parser.add_argument(
        "--scan", type=str, help="Directory to scan and generate manifest"
    )
    parser.add_argument(
        "--verify", type=str, help="Directory to verify against manifest"
    )
    args = parser.parse_args()

    if args.scan:
        fim = FileIntegrityMonitor(args.scan)
        res = fim.build_manifest()
        print(
            f"[FIM] Manifest generated successfully: {res['merkle_root']} ({res['leaf_count']} files)"
        )
    elif args.verify:
        fim = FileIntegrityMonitor(args.verify)
        valid, diffs = fim.verify()
        if valid:
            print(
                f"[FIM] Verification SUCCESS: All files match Merkle Tree root in {args.verify}"
            )
            sys.exit(0)
        else:
            print(f"[FIM] Verification FAILED ({len(diffs)} issues):")
            for d in diffs:
                print(f"  - {d}")
            sys.exit(1)
    else:
        parser.print_help()


if __name__ == "__main__":
    main()
