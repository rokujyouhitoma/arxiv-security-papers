#!/usr/bin/env python3
"""
Autonomous CTI Backfill & Enrichment Pipeline for OKF Papers (Issue 153 & Issue 165).
Scans existing OKF markdown archives, infers MITRE ATT&CK techniques with confidence,
rule ontology (EIROM) mappings, and evidence quotes, maps mitigations, and syncs
with PropertyGraphEngine in an idempotent, non-destructive manner.
"""

from __future__ import annotations

import argparse
import glob
import json
import os
import re
from typing import Any, Dict, List, Optional, Tuple

from domain.security.cti.graph_bridge import sync_cti_inferences_to_graph
from domain.security.cti.inference import (
    InferredTechnique,
    TechniqueInferenceEngine,
    _compute_text_hash,
)
from domain.security.cti.registry import MITRECTIRegistry
from graph.engine import PropertyGraphEngine
from ontology.rule_registry import EdgeInferenceRuleRegistry
from security.validation.path import get_default_workspace_dir, is_safe_workspace_path


class CTIBackfillEnricher:
    """Enriches OKF paper markdown files with inferred ATT&CK techniques, rules, and graph sync."""

    def __init__(
        self,
        workspace_dir: Optional[str] = None,
        graph_db_path: Optional[str] = None,
        sync_graph: bool = True,
    ) -> None:
        self.workspace_dir = os.path.abspath(
            workspace_dir or get_default_workspace_dir()
        )
        self.registry = MITRECTIRegistry.get_instance()
        self.rule_registry = EdgeInferenceRuleRegistry()
        self.inference_engine = TechniqueInferenceEngine(
            rule_registry=self.rule_registry
        )
        self.okf_base_dir = os.path.join(self.workspace_dir, "outputs", "okf_papers")
        self.graph_db_path = graph_db_path
        self.sync_graph = sync_graph
        self._graph_engine: Optional[PropertyGraphEngine] = None

    @property
    def graph_engine(self) -> PropertyGraphEngine:
        """Lazily initializes and returns PropertyGraphEngine instance."""
        if self._graph_engine is None:
            self._graph_engine = PropertyGraphEngine(
                workspace_dir=self.workspace_dir,
                storage_path=self.graph_db_path,
            )
        return self._graph_engine

    def find_all_okf_files(self) -> List[str]:
        """Discovers all .md files under outputs/okf_papers/ within workspace."""
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

    @staticmethod
    def _extract_title(fm_str: str, body_str: str) -> str:
        """Extracts paper title from frontmatter or first header line."""
        match = re.search(r'title:\s*"([^"]+)"', fm_str)
        if match:
            return match.group(1).strip()
        for line in body_str.splitlines():
            if line.startswith("# "):
                return line[2:].strip()
        return "Untitled Paper"

    @staticmethod
    def _extract_paper_id(filepath: str, fm_str: str) -> str:
        """Extracts normalized paper identifier from frontmatter or filename."""
        match = re.search(r'arxiv_id:\s*"([^"]+)"', fm_str)
        if match:
            return match.group(1).strip()
        base = os.path.splitext(os.path.basename(filepath))[0]
        return re.sub(r"^arxiv:", "", base, flags=re.IGNORECASE)

    @staticmethod
    def _extract_existing_hash(fm_str: str) -> Optional[str]:
        """Extracts existing source_text_hash from YAML frontmatter if present."""
        match = re.search(r'source_text_hash:\s*"?([a-f0-9]+)"?', fm_str, re.IGNORECASE)
        return match.group(1) if match else None

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
        """Extracts techniques and maps corresponding mitigations (backward compatibility)."""
        inferences = self.inference_engine.infer(title="", text=text)
        techs = [
            {"technique_id": t.technique_id, "name": t.technique_name}
            for t in inferences
        ]
        mits = self._resolve_mitigations([t.technique_id for t in inferences])
        return techs, mits

    @staticmethod
    def _is_cti_header(line: str) -> bool:
        """Checks if a frontmatter line begins a CTI-related block or hash."""
        stripped = line.strip()
        return (
            stripped.startswith("cti_techniques:")
            or stripped.startswith("inferred_techniques:")
            or stripped.startswith("mitigations:")
            or stripped.startswith("source_text_hash:")
        )

    @staticmethod
    def _is_indented(line: str) -> bool:
        """Checks if line starts with space or tab indentation."""
        return line.startswith("  ") or line.startswith("\t")

    @classmethod
    def _strip_existing_cti(cls, fm_lines: List[str]) -> List[str]:
        """Filters out existing CTI blocks and hash from frontmatter lines."""
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

    @staticmethod
    def _format_inferred_techniques(inferences: List[InferredTechnique]) -> List[str]:
        """Formats inferred techniques list with full EIROM audit properties."""
        lines = ["inferred_techniques:"]
        for tech in inferences:
            quote = tech.evidence_quote.replace('"', '\\"').replace("\n", " ").strip()
            name = tech.technique_name.replace('"', '\\"').strip()
            prim_rule = tech.primary_rule_id or ""
            tier = tech.confidence_tier
            conf = float(round(tech.confidence, 4))
            mech = tech.inference_mechanism
            focus = tech.research_focus
            tid = tech.technique_id
            fields = (
                f'technique_id: "{tid}", '
                f'name: "{name}", '
                f"confidence: {conf}, "
                f'confidence_tier: "{tier}", '
                f'primary_rule_id: "{prim_rule}", '
                f'inference_mechanism: "{mech}", '
                f'research_focus: "{focus}", '
                f'evidence_quote: "{quote}"'
            )
            lines.append(f"  - {{ {fields} }}")
        return lines

    @staticmethod
    def _format_yaml_list(items: List[Dict[str, str]], key_name: str) -> List[str]:
        """Formats list of dictionaries as YAML frontmatter lines."""
        lines = [f"{key_name}:"]
        for item in items:
            fields = ", ".join(f'{k}: "{v}"' for k, v in item.items())
            lines.append(f"  - {{ {fields} }}")
        return lines

    def _update_frontmatter_lines(
        self,
        fm_lines: List[str],
        inferences: List[InferredTechnique],
        mitigations: List[Dict[str, str]],
        text_hash: str,
    ) -> List[str]:
        """Updates or injects CTI techniques, mitigations, and hash in frontmatter."""
        new_lines = self._strip_existing_cti(fm_lines)
        if inferences:
            new_lines.extend(self._format_inferred_techniques(inferences))
            legacy_techs = [
                {"technique_id": t.technique_id, "name": t.technique_name}
                for t in inferences
            ]
            new_lines.extend(self._format_yaml_list(legacy_techs, "cti_techniques"))
        if mitigations:
            new_lines.extend(self._format_yaml_list(mitigations, "mitigations"))
        new_lines.append(f'source_text_hash: "{text_hash}"')
        return new_lines

    @staticmethod
    def _read_file_safe(filepath: str) -> Tuple[str, Optional[str]]:
        """Safely reads file content and returns (content, error_message)."""
        try:
            with open(filepath, "r", encoding="utf-8") as f:
                return f.read(), None
        except OSError as e:
            return "", str(e)

    @staticmethod
    def _write_file_atomic(filepath: str, content: str) -> None:
        """Writes file content atomically via PID-tagged temp file and os.replace."""
        tmp_path = f"{filepath}.tmp.{os.getpid()}"
        try:
            with open(tmp_path, "w", encoding="utf-8") as f:
                f.write(content)
            os.replace(tmp_path, filepath)
        except Exception:
            if os.path.exists(tmp_path):
                try:
                    os.remove(tmp_path)
                except OSError:
                    pass
            raise

    def _read_and_parse(
        self, filepath: str
    ) -> Tuple[Optional[Tuple[str, str]], Optional[Dict[str, Any]]]:
        """Validates path and reads frontmatter and body."""
        if not is_safe_workspace_path(filepath, self.workspace_dir):
            return None, {
                "file": filepath,
                "updated": False,
                "error": "Unsafe workspace path",
            }
        content, err = self._read_file_safe(filepath)
        if err:
            return None, {"file": filepath, "updated": False, "error": err}
        fm_str, body_str = self._parse_frontmatter(content)
        if fm_str is None:
            return None, {
                "file": filepath,
                "updated": False,
                "reason": "No frontmatter",
            }
        return (fm_str, body_str), None

    @staticmethod
    def _is_hash_unchanged(
        existing_hash: Optional[str], text_hash: str, force: bool
    ) -> bool:
        """Checks if content hash is unchanged and re-processing is not forced."""
        return not force and existing_hash == text_hash

    @staticmethod
    def _is_content_unchanged(original: str, new_content: str, force: bool) -> bool:
        """Checks if generated content matches original without force."""
        return not force and original == new_content

    @staticmethod
    def _skipped_result(filepath: str, text_hash: str) -> Dict[str, Any]:
        """Constructs response dictionary for skipped paper."""
        return {
            "file": filepath,
            "updated": False,
            "skipped": True,
            "reason": "Unchanged (hash match)",
            "source_text_hash": text_hash,
        }

    @staticmethod
    def _build_success_result(
        filepath: str,
        inferences: List[InferredTechnique],
        mitigations: List[Dict[str, str]],
        edges_synced: int,
        text_hash: str,
    ) -> Dict[str, Any]:
        """Constructs response dictionary for successfully enriched paper."""
        return {
            "file": filepath,
            "updated": True,
            "technique_count": len(inferences),
            "mitigation_count": len(mitigations),
            "edges_synced": edges_synced,
            "source_text_hash": text_hash,
            "inferences": inferences,
        }

    def _generate_enriched_content(
        self,
        fm_str: str,
        body_str: str,
        inferences: List[InferredTechnique],
        text_hash: str,
    ) -> Tuple[str, List[Dict[str, str]]]:
        """Produces updated markdown file content and resolved mitigations list."""
        tech_ids = [t.technique_id for t in inferences]
        mitigations = self._resolve_mitigations(tech_ids)
        fm_lines = [line for line in fm_str.strip("\n").split("\n")]
        updated_fm = self._update_frontmatter_lines(
            fm_lines, inferences, mitigations, text_hash
        )
        new_content = f"---\n{chr(10).join(updated_fm)}\n---{body_str}"
        return new_content, mitigations

    def _sync_to_graph(
        self,
        paper_id: str,
        title: str,
        inferences: List[InferredTechnique],
    ) -> int:
        """Syncs paper and inferred technique edges to PropertyGraphEngine."""
        res = sync_cti_inferences_to_graph(
            paper_id=paper_id,
            title=title,
            inferences=inferences,
            graph_engine=self.graph_engine,
            save=False,
        )
        created: List[str] = list(res.get("edges_created", []))
        return len(created)

    def _sync_graph_if_active(
        self,
        paper_id: str,
        title: str,
        inferences: List[InferredTechnique],
        dry_run: bool,
    ) -> int:
        """Executes graph sync if enabled and not in dry-run mode."""
        if not self.sync_graph or dry_run or not inferences:
            return 0
        return self._sync_to_graph(paper_id, title, inferences)

    def _write_if_not_dry(self, filepath: str, content: str, dry_run: bool) -> None:
        """Performs atomic write if dry-run mode is disabled."""
        if not dry_run:
            self._write_file_atomic(filepath, content)

    def _execute_enrichment_write(
        self,
        filepath: str,
        paper_id: str,
        title: str,
        fm_str: str,
        body_str: str,
        text_hash: str,
        dry_run: bool,
        force: bool,
    ) -> Dict[str, Any]:
        """Performs technique inference, updates content, writes, and syncs graph."""
        inferences = self.inference_engine.infer(
            title=title, text=body_str, paper_id=paper_id
        )
        new_content, mits = self._generate_enriched_content(
            fm_str, body_str, inferences, text_hash
        )
        original_content = f"---\n{fm_str}\n---{body_str}"
        if self._is_content_unchanged(original_content, new_content, force):
            return {"file": filepath, "updated": False, "reason": "Unchanged"}

        self._write_if_not_dry(filepath, new_content, dry_run)
        edges_synced = self._sync_graph_if_active(paper_id, title, inferences, dry_run)
        return self._build_success_result(
            filepath, inferences, mits, edges_synced, text_hash
        )

    def enrich_file(
        self,
        filepath: str,
        dry_run: bool = False,
        force: bool = False,
    ) -> Dict[str, Any]:
        """Enriches a single OKF paper file with inferred CTI metadata and graph edges."""
        fm_body, err_res = self._read_and_parse(filepath)
        if err_res is not None:
            return err_res
        if fm_body is None:
            return {"file": filepath, "updated": False, "reason": "No frontmatter"}

        fm_str, body_str = fm_body
        title = self._extract_title(fm_str, body_str)
        paper_id = self._extract_paper_id(filepath, fm_str)
        text_hash = _compute_text_hash(title, body_str)

        if self._is_hash_unchanged(
            self._extract_existing_hash(fm_str), text_hash, force
        ):
            return self._skipped_result(filepath, text_hash)

        return self._execute_enrichment_write(
            filepath=filepath,
            paper_id=paper_id,
            title=title,
            fm_str=fm_str,
            body_str=body_str,
            text_hash=text_hash,
            dry_run=dry_run,
            force=force,
        )

    @staticmethod
    def _tally_tiers(
        inferences: List[InferredTechnique],
        tier_breakdown: Dict[str, int],
        tech_counter: Dict[str, int],
    ) -> None:
        """Tallies confidence tiers and technique occurrence frequency."""
        for tech in inferences:
            tier = tech.confidence_tier
            tier_breakdown[tier] = tier_breakdown.get(tier, 0) + 1
            tid = tech.technique_id
            tech_counter[tid] = tech_counter.get(tid, 0) + 1

    @staticmethod
    def _compile_top_techniques(
        tech_counter: Dict[str, int], limit: int = 10
    ) -> List[Dict[str, Any]]:
        """Compiles top frequent techniques into ranked list."""
        sorted_items = sorted(tech_counter.items(), key=lambda x: x[1], reverse=True)
        return [{"technique_id": k, "count": v} for k, v in sorted_items[:limit]]

    @staticmethod
    def _write_report_if_needed(
        stats: Dict[str, Any], report_file: Optional[str]
    ) -> None:
        """Writes execution stats report to JSON file if path is specified."""
        if not report_file:
            return
        os.makedirs(os.path.dirname(os.path.abspath(report_file)), exist_ok=True)
        with open(report_file, "w", encoding="utf-8") as f:
            json.dump(stats, f, indent=2, ensure_ascii=False)

    def _process_file_backfill(
        self,
        fpath: str,
        dry_run: bool,
        force: bool,
        stats: Dict[str, Any],
        tech_counter: Dict[str, int],
    ) -> None:
        """Enriches one file and records summary metrics."""
        res = self.enrich_file(fpath, dry_run=dry_run, force=force)
        if res.get("error"):
            stats["error_count"] += 1
            return
        if res.get("skipped"):
            stats["skipped_count"] += 1
            return
        if res.get("updated"):
            stats["updated_count"] += 1
            stats["total_techniques_mapped"] += res.get("technique_count", 0)
            stats["total_mitigations_mapped"] += res.get("mitigation_count", 0)
            stats["total_edges_synced"] += res.get("edges_synced", 0)
            inferences: List[InferredTechnique] = res.get("inferences", [])
            self._tally_tiers(inferences, stats["tier_breakdown"], tech_counter)

    @staticmethod
    def _limit_files(all_files: List[str], max_papers: Optional[int]) -> List[str]:
        """Limits paper file list if positive limit is supplied."""
        if max_papers and max_papers > 0:
            return all_files[:max_papers]
        return all_files

    @staticmethod
    def _init_backfill_stats(total: int, dry_run: bool, force: bool) -> Dict[str, Any]:
        """Initializes empty stats dictionary for backfill scan."""
        return {
            "total_scanned": total,
            "updated_count": 0,
            "skipped_count": 0,
            "error_count": 0,
            "total_techniques_mapped": 0,
            "total_mitigations_mapped": 0,
            "total_edges_synced": 0,
            "tier_breakdown": {"HIGH": 0, "MEDIUM": 0, "LOW": 0},
            "top_techniques": [],
            "dry_run": dry_run,
            "force": force,
        }

    def _save_graph_if_active(self, dry_run: bool) -> None:
        """Saves graph engine if active, not in dry-run mode, and initialized."""
        if dry_run or not self.sync_graph or self._graph_engine is None:
            return
        self._graph_engine.save()

    def run_backfill(
        self,
        dry_run: bool = False,
        force: bool = False,
        max_papers: Optional[int] = None,
        report_file: Optional[str] = None,
    ) -> Dict[str, Any]:
        """Executes full backfill scan across OKF papers with audit summary."""
        all_files = self._limit_files(self.find_all_okf_files(), max_papers)
        stats = self._init_backfill_stats(len(all_files), dry_run, force)
        tech_counter: Dict[str, int] = {}

        for fpath in all_files:
            self._process_file_backfill(fpath, dry_run, force, stats, tech_counter)

        self._save_graph_if_active(dry_run)
        stats["top_techniques"] = self._compile_top_techniques(tech_counter)
        self._write_report_if_needed(stats, report_file)
        return stats


def main() -> None:
    """CLI entry point for CTI backfill and enrichment."""
    parser = argparse.ArgumentParser(description="CTI Backfill Enricher for OKF Papers")
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Perform scan and inference without writing modifications",
    )
    parser.add_argument(
        "--force",
        action="store_true",
        help="Force re-inference and update even if content hash matches",
    )
    parser.add_argument(
        "--max-papers",
        type=int,
        default=None,
        help="Limit number of papers to process",
    )
    parser.add_argument(
        "--no-sync-graph",
        action="store_true",
        help="Disable synchronization to PropertyGraphEngine",
    )
    parser.add_argument(
        "--db-path",
        type=str,
        default=None,
        help="Path to PropertyGraph SQLite DB",
    )
    parser.add_argument(
        "--report-file",
        type=str,
        default=None,
        help="Path to save execution summary report as JSON",
    )
    args = parser.parse_args()

    enricher = CTIBackfillEnricher(
        graph_db_path=args.db_path,
        sync_graph=not args.no_sync_graph,
    )
    results = enricher.run_backfill(
        dry_run=args.dry_run,
        force=args.force,
        max_papers=args.max_papers,
        report_file=args.report_file,
    )
    print(json.dumps(results, indent=2, ensure_ascii=False))


if __name__ == "__main__":
    main()
