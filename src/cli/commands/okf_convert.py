#!/usr/bin/env python3
"""src/cli/commands/okf_convert.py

Google OKF v0.2 structured stream filter subcommand conforming to DSN-01 Section 5.2.
Consumes JSON Lines from stdin and emits OKF-enriched JSON Lines or Markdown to stdout.
Pure Python, zero external dependencies, Xenon CC <= 5.
"""

from __future__ import annotations

import argparse
import datetime
import os
import sys
from typing import Any, Dict, List, Optional, Tuple

from pipeline.transformer.okf_serializer import generate_japanese_executive_summary
from pipeline.transformer.tagger import determine_security_tags
from pipeline.transformer.translator import translate_title_ja

from ..base import BaseCommand
from ..stream import DiagnosticLogger, StreamErrorPolicy, StreamReader, StreamWriter


def _normalize_paper_dict(record: Dict[str, Any]) -> Dict[str, Any]:
    """Ensures paper record has standard keys for OKF transformers."""
    arxiv_id = str(record.get("arxiv_id", ""))
    title = str(record.get("title", ""))
    summary = str(record.get("abstract") or record.get("summary", ""))
    return {
        "arxiv_id": arxiv_id,
        "clean_id": arxiv_id.replace("/", "_").replace(":", "_"),
        "title": title,
        "title_ja": record.get("title_ja") or translate_title_ja(title),
        "summary": summary,
        "abstract": summary,
        "authors": record.get("authors", []),
        "categories": record.get("categories", ["cs.CR"]),
        "published": record.get("published", ""),
        "pdf_url": record.get("pdf_url", f"https://arxiv.org/pdf/{arxiv_id}.pdf"),
        "abs_url": f"https://arxiv.org/abs/{arxiv_id}",
    }


def _build_okf_frontmatter(
    title: str,
    title_ja: str,
    desc: str,
    resource: str,
    tags: List[str],
    pub_date: str,
) -> str:
    """Renders Google OKF v0.2 YAML frontmatter block."""
    now_iso = datetime.datetime.now(datetime.timezone.utc).strftime(
        "%Y-%m-%dT%H:%M:%SZ"
    )
    tag_lines = "\n".join([f'  - "{t}"' for t in tags])
    safe_title = title.replace('"', '\\"').replace("\n", " ")
    safe_title_ja = title_ja.replace('"', '\\"').replace("\n", " ")
    safe_desc = desc.replace('"', '\\"').replace("\n", " ")
    return (
        f"---\n"
        f'type: "security-paper"\n'
        f'title: "{safe_title}"\n'
        f'title_ja: "{safe_title_ja}"\n'
        f'description: "{safe_desc}"\n'
        f'resource: "{resource}"\n'
        f"tags:\n{tag_lines}\n"
        f'timestamp: "{now_iso}"\n'
        f"provenance:\n"
        f'  origin: "arxiv.org"\n'
        f'  published: "{pub_date}"\n'
        f"trust:\n"
        f'  attestation: "processed_by: arxiv-security-agent"\n'
        f'  confidence: "high"\n'
        f"---"
    )


def _build_okf_markdown(
    paper: Dict[str, Any], frontmatter: str, summary: Dict[str, Any]
) -> str:
    """Builds complete OKF Markdown document string."""
    title = paper["title"]
    title_ja = paper["title_ja"]
    arxiv_id = paper["arxiv_id"]
    return (
        f"{frontmatter}\n\n"
        f"# {title}\n"
        f"### (日本語題名: {title_ja})\n\n"
        f"## エグゼクティブサマリー\n\n"
        f"### 1. 概要\n{summary.get('overview', '')}\n\n"
        f"### 2. 背景と課題\n{summary.get('background', '')}\n\n"
        f"### 3. 提案アプローチ\n{summary.get('technical_approach', '')}\n\n"
        f"### 4. セキュリティ影響\n{summary.get('results_impact', '')}\n\n"
        f"## 原論文情報\n"
        f"- **arXiv ID**: `{arxiv_id}`\n"
        f"- **論文URL**: {paper['abs_url']}\n"
    )


def _save_markdown_if_requested(
    clean_id: str, content: str, save_dir: Optional[str]
) -> None:
    """Saves OKF markdown to disk if save directory is configured."""
    if not save_dir:
        return
    os.makedirs(save_dir, exist_ok=True)
    target_path = os.path.join(save_dir, f"{clean_id}.md")
    with open(target_path, "w", encoding="utf-8") as f:
        f.write(content)


def _convert_record(
    record: Dict[str, Any], save_dir: Optional[str]
) -> Tuple[Dict[str, Any], str]:
    """Transforms a single record into OKF enriched format and Markdown."""
    paper = _normalize_paper_dict(record)
    exec_summary = generate_japanese_executive_summary(paper)
    tags = sorted(list(set(["cs.CR", "security"] + determine_security_tags(paper))))
    frontmatter = _build_okf_frontmatter(
        title=paper["title"],
        title_ja=paper["title_ja"],
        desc=exec_summary.get("one_liner", ""),
        resource=paper["abs_url"],
        tags=tags,
        pub_date=str(paper.get("published", "")),
    )
    md_content = _build_okf_markdown(paper, frontmatter, exec_summary)
    _save_markdown_if_requested(paper["clean_id"], md_content, save_dir)

    out = dict(record)
    out["title_ja"] = paper["title_ja"]
    out["executive_summary"] = exec_summary.get("one_liner", "")
    out["tags"] = tags
    out["okf_yaml"] = frontmatter
    out["markdown_content"] = md_content
    return out, md_content


class OkfConvertCommand(BaseCommand):
    """Subcommand to convert raw paper records to Google OKF v0.2 format."""

    name = "okf-convert"
    help_text = "Convert paper stream to Google OKF v0.2 structured JSONL or Markdown."

    def add_arguments(self, parser: argparse.ArgumentParser) -> None:
        parser.add_argument(
            "-f",
            "--format",
            dest="format",
            choices=["jsonl", "markdown"],
            default="jsonl",
            help="Output format: jsonl or markdown (default: jsonl).",
        )
        parser.add_argument(
            "--save-dir",
            dest="save_dir",
            default=None,
            help="Optional directory path to persist generated OKF Markdown files.",
        )
        parser.add_argument(
            "--on-error",
            dest="on_error",
            choices=["skip", "abort"],
            default="skip",
            help="Error policy for malformed input (skip or abort, default: skip).",
        )

    def handle(self, args: argparse.Namespace) -> int:
        policy = StreamErrorPolicy(args.on_error)
        reader = StreamReader(on_error=policy)
        writer = StreamWriter()
        logger = DiagnosticLogger()

        logger.info(f"Starting OKF conversion filter (format: '{args.format}')...")

        for record in reader:
            enriched, md_content = _convert_record(record, args.save_dir)
            if args.format == "markdown":
                sys.stdout.write(f"{md_content}\n---\n")
                sys.stdout.flush()
            else:
                writer.write_record(enriched)

        logger.info("OKF conversion completed successfully.")
        return 0
