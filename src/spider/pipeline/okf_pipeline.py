"""Backward-compatibility re-export shim for OkfItemPipeline.

This module is deprecated. Domain logic has been moved to:
    domain.security.pipeline.okf_pipeline
"""

from __future__ import annotations

from domain.security.pipeline.okf_pipeline import (
    OkfItemPipeline,
    SecurityOkfItemPipeline,
    _build_okf_markdown,
    _build_paper_okf_markdown,
    _build_vulnerability_okf_markdown,
    _clean_seq,
    _extract_date_folder,
    _extract_epss_score,
    _extract_sec_meta_dict,
    _first_val,
    _format_cvss_meta,
    _format_paper_authors,
    _format_tags_yaml,
    _format_yaml_val,
    _get_vuln_cve_and_title,
    _normalize_string_list,
    _parse_dict_cvss,
    _persist_to_dsn14_db,
    _render_cvss_display,
    _render_vuln_affected_products,
    _render_vuln_body,
    _render_vuln_frontmatter,
    _render_vuln_metrics_table,
    _render_vuln_references,
    _sanitize_path_id,
    _sanitize_string,
    _score_to_severity,
    _truncate_desc,
)

__all__ = [
    "OkfItemPipeline",
    "SecurityOkfItemPipeline",
    "_sanitize_string",
    "_sanitize_path_id",
    "_extract_date_folder",
    "_truncate_desc",
    "_first_val",
    "_score_to_severity",
    "_parse_dict_cvss",
    "_format_cvss_meta",
    "_clean_seq",
    "_normalize_string_list",
    "_format_paper_authors",
    "_format_tags_yaml",
    "_format_yaml_val",
    "_build_paper_okf_markdown",
    "_render_cvss_display",
    "_render_vuln_metrics_table",
    "_render_vuln_affected_products",
    "_render_vuln_references",
    "_extract_epss_score",
    "_render_vuln_frontmatter",
    "_render_vuln_body",
    "_extract_sec_meta_dict",
    "_get_vuln_cve_and_title",
    "_build_vulnerability_okf_markdown",
    "_build_okf_markdown",
    "_persist_to_dsn14_db",
]
