#!/usr/bin/env python3
"""
Autonomous CTI Backfill & Enrichment Pipeline for OKF Papers (Issue 153).
Scans existing OKF markdown archives, extracts matching MITRE ATT&CK techniques,
maps MITRE mitigations, and updates YAML frontmatter in a safe, non-destructive manner.
"""

from __future__ import annotations

import argparse
import glob
import json
import os
from typing import Any, Dict, List, Optional, Tuple

from domain.security.cti.registry import MITRECTIRegistry
from domain.security.taxonomy.mitre import extract_mitre_techniques
from security.validation.path import get_default_workspace_dir, is_safe_workspace_path


class CTIBackfillEnricher:
    """Enriches OKF paper markdown files with MITRE ATT&CK techniques and mitigations."""

    def __init__(self, workspace_dir: Optional[str] = None) -> None:
        self.workspace_dir = os.path.abspath(
            workspace_dir or get_default_workspace_dir()
        )
        self.registry = MITRECTIRegistry.get_instance()
        self.okf_base_dir = os.path.join(self.workspace_dir, "outputs", "okf_papers")

    def find_all_okf_files(self) -> List[str]:
        """Discovers all .md files under outputs/okf_papers/."""
        pattern = os.path.join(self.okf_base_dir, "**", "*.md")
        files = glob.glob(pattern, recursive=True)
        return sorted(
            [f for f in files if is_safe_workspace_path(f, self.workspace_dir)]
        )

    @staticmethod
    def _parse_frontmatter(content: str) -> Tuple[Optional[str], str]:
        """Separates YAML frontmatter string and markdown body."""
        if not content.startswith("---"):
            return None, content
        parts = content.split("---", 2)
        if len(parts) < 3:
            return None, content
        return parts[1], parts[2]

    def _extract_paper_text(self, frontmatter_str: str, body_str: str) -> str:
        """Combines relevant textual fields for CTI keyword extraction."""
        return f"{frontmatter_str}\n{body_str}"

    def _resolve_techniques(self, tech_ids: List[str]) -> List[Dict[str, str]]:
        """Resolves technique metadata for extracted technique IDs."""
        enriched: List[Dict[str, str]] = []
        for tid in tech_ids:
            meta = self.registry.get_technique(tid) or {}
            enriched.append(
                {
                    "technique_id": tid,
                    "name": str(meta.get("name", "Unknown Technique")),
                }
            )
        return enriched

    def _resolve_mitigations(self, tech_ids: List[str]) -> List[Dict[str, str]]:
        """Resolves unique mitigations mapped to extracted techniques."""
        mits_map: Dict[str, Dict[str, str]] = {}
        for tid in tech_ids:
            for m in self.registry.get_mitigations_for_technique(tid):
                mid = m["mitigation_id"]
                mits_map.setdefault(
                    mid,
                    {
                        "mitigation_id": mid,
                        "name": str(m.get("name", "Unknown Mitigation")),
                    },
                )
        return sorted(list(mits_map.values()), key=lambda x: x["mitigation_id"])

    def _determine_enrichments(
        self, text: str
    ) -> Tuple[List[Dict[str, str]], List[Dict[str, str]]]:
        """Extracts techniques and maps corresponding mitigations."""
        tech_ids = extract_mitre_techniques(text)
        if not tech_ids:
            return [], []
        return self._resolve_techniques(tech_ids), self._resolve_mitigations(tech_ids)

    @staticmethod
    def _format_yaml_list(items: List[Dict[str, str]], key_name: str) -> List[str]:
        """Formats list of dictionaries as YAML frontmatter lines."""
        lines = [f"{key_name}:"]
        for item in items:
            fields = ", ".join(f'{k}: "{v}"' for k, v in item.items())
            lines.append(f"  - {{ {fields} }}")
        return lines

    @staticmethod
    def _is_cti_header(line: str) -> bool:
        """Checks if a frontmatter line begins a CTI block."""
        stripped = line.strip()
        return stripped.startswith("cti_techniques:") or stripped.startswith(
            "mitigations:"
        )

    @staticmethod
    def _is_indented(line: str) -> bool:
        """Checks if line starts with space or tab indentation."""
        return line.startswith("  ") or line.startswith("\t")

    @classmethod
    def _strip_existing_cti(cls, fm_lines: List[str]) -> List[str]:
        """Filters out existing cti_techniques and mitigations blocks."""
        new_lines: List[str] = []
        skip_block = False
        for line in fm_lines:
            if cls._is_cti_header(line):
                skip_block = True
                continue
            if skip_block and cls._is_indented(line):
                continue
            skip_block = False
            new_lines.append(line)
        return new_lines

    def _update_frontmatter_lines(
        self,
        fm_lines: List[str],
        techniques: List[Dict[str, str]],
        mitigations: List[Dict[str, str]],
    ) -> List[str]:
        """Updates or injects cti_techniques and mitigations in frontmatter lines."""
        new_lines = self._strip_existing_cti(fm_lines)
        if techniques:
            new_lines.extend(self._format_yaml_list(techniques, "cti_techniques"))
        if mitigations:
            new_lines.extend(self._format_yaml_list(mitigations, "mitigations"))
        return new_lines

    @staticmethod
    def _read_file_safe(filepath: str) -> Tuple[str, Optional[str]]:
        """Safely reads file content and returns (content, error_message)."""
        try:
            with open(filepath, "r", encoding="utf-8") as f:
                return f.read(), None
        except OSError as e:
            return "", str(e)

    def _apply_enrichment_to_content(
        self, content: str
    ) -> Tuple[Optional[str], int, int]:
        """Generates updated content with CTI enrichments injected."""
        fm_str, body_str = self._parse_frontmatter(content)
        if fm_str is None:
            return None, 0, 0

        combined_text = self._extract_paper_text(fm_str, body_str)
        techniques, mitigations = self._determine_enrichments(combined_text)
        if not techniques and not mitigations:
            return content, 0, 0

        fm_lines = [line for line in fm_str.strip("\n").split("\n")]
        updated_fm_lines = self._update_frontmatter_lines(
            fm_lines, techniques, mitigations
        )
        new_content = f"---\n{chr(10).join(updated_fm_lines)}\n---{body_str}"
        return new_content, len(techniques), len(mitigations)

    def enrich_file(self, filepath: str, dry_run: bool = False) -> Dict[str, Any]:
        """Enriches a single OKF paper file with CTI techniques and mitigations."""
        content, err = self._read_file_safe(filepath)
        if err:
            return {"file": filepath, "updated": False, "error": err}

        new_content, n_tech, n_mit = self._apply_enrichment_to_content(content)
        if new_content is None:
            return {"file": filepath, "updated": False, "reason": "No frontmatter"}
        if new_content == content:
            return {"file": filepath, "updated": False, "reason": "Unchanged"}

        if not dry_run:
            with open(filepath, "w", encoding="utf-8") as f:
                f.write(new_content)

        return {
            "file": filepath,
            "updated": True,
            "technique_count": n_tech,
            "mitigation_count": n_mit,
        }

    def run_backfill(
        self, dry_run: bool = False, max_papers: Optional[int] = None
    ) -> Dict[str, Any]:
        """Executes full backfill scan across all OKF papers."""
        all_files = self.find_all_okf_files()
        if max_papers is not None and max_papers > 0:
            all_files = all_files[:max_papers]

        stats: Dict[str, Any] = {
            "total_scanned": len(all_files),
            "updated_count": 0,
            "total_techniques_mapped": 0,
            "total_mitigations_mapped": 0,
            "dry_run": dry_run,
        }

        for fpath in all_files:
            res = self.enrich_file(fpath, dry_run=dry_run)
            if res.get("updated"):
                stats["updated_count"] += 1
                stats["total_techniques_mapped"] += res.get("technique_count", 0)
                stats["total_mitigations_mapped"] += res.get("mitigation_count", 0)

        return stats


def main() -> None:
    parser = argparse.ArgumentParser(description="CTI Backfill Enricher for OKF Papers")
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Perform scan without writing modifications",
    )
    parser.add_argument(
        "--max-papers", type=int, default=None, help="Limit number of papers to process"
    )
    args = parser.parse_args()

    enricher = CTIBackfillEnricher()
    results = enricher.run_backfill(dry_run=args.dry_run, max_papers=args.max_papers)
    print(json.dumps(results, indent=2, ensure_ascii=False))


if __name__ == "__main__":
    main()
