#!/usr/bin/env python3
"""Static verification of R7RS specification traceability and diagnostic tags (Issue #665).

Validates:
1. All .sld files under ulisp/lib/ contain a Traceability header pointing to ulisp/docs/ref_r7rs_compliance.md.
2. All .scm files under ulisp/lib/ contain R7RS specification section comments (;; §...).
3. Compiler diagnostic error messages in frontend passes contain [R7RS §...] specification tags.
4. ref_r7rs_compliance.md maintains traceability references for all libraries.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
ULISP_DIR = REPO_ROOT / "ulisp"
LIB_DIR = ULISP_DIR / "lib"
DOCS_DIR = ULISP_DIR / "docs"
FRONTEND_DIR = ULISP_DIR / "frontend"


def verify_sld_traceability_headers() -> list[str]:
    """Verify that all .sld files in ulisp/lib/ contain Traceability metadata."""
    errors = []
    sld_files = sorted(LIB_DIR.glob("**/*.sld"))
    if not sld_files:
        errors.append("No .sld library definition files found in ulisp/lib/")
        return errors

    expected_marker = "Traceability: ulisp/docs/ref_r7rs_compliance.md"
    for sld in sld_files:
        content = sld.read_text(encoding="utf-8")
        if expected_marker not in content:
            rel_path = sld.relative_to(REPO_ROOT)
            errors.append(f"{rel_path}: Missing '{expected_marker}' in header")
    return errors


def verify_scm_section_comments() -> list[str]:
    """Verify that ulisp/lib/*.scm contain R7RS section comments (;; §...)."""
    errors = []
    scm_files = sorted(LIB_DIR.glob("*.scm"))
    if not scm_files:
        errors.append("No .scm implementation files found in ulisp/lib/")
        return errors

    section_pattern = re.compile(r";;+.*§")
    for scm in scm_files:
        content = scm.read_text(encoding="utf-8")
        if not section_pattern.search(content):
            rel_path = scm.relative_to(REPO_ROOT)
            errors.append(f"{rel_path}: Missing R7RS section comments (;; §...)")
    return errors


def verify_frontend_diagnostic_tags() -> list[str]:
    """Verify that frontend macro expander and desugar passes use [R7RS §...] error tags."""
    errors = []
    macro_expander = FRONTEND_DIR / "020_macro_expander.scm"
    desugar = FRONTEND_DIR / "030_desugar.scm"

    tag_pattern = re.compile(r"\[R7RS\s+§[^\]]+\]")

    for pass_file in [macro_expander, desugar]:
        if not pass_file.exists():
            errors.append(f"Missing frontend pass: {pass_file.relative_to(REPO_ROOT)}")
            continue
        content = pass_file.read_text(encoding="utf-8")
        matches = tag_pattern.findall(content)
        if len(matches) < 2:
            rel_path = pass_file.relative_to(REPO_ROOT)
            errors.append(
                f"{rel_path}: Expected at least 2 [R7RS §...] diagnostic tags, found {len(matches)}"
            )
    return errors


def verify_compliance_doc() -> list[str]:
    """Verify that ref_r7rs_compliance.md exists and contains Section 3 and closed issues."""
    errors = []
    doc_path = DOCS_DIR / "ref_r7rs_compliance.md"
    if not doc_path.exists():
        errors.append(f"Missing compliance doc: {doc_path.relative_to(REPO_ROOT)}")
        return errors

    content = doc_path.read_text(encoding="utf-8")
    required_sections = [
        "## 3. R7RS 仕様トレーサビリティとライブラリメタデータ管理規約",
        "Issue #658",
        "Issue #659",
        "Issue #660",
        "Issue #661",
        "Issue #662",
        "Issue #663",
        "Issue #664",
        "Issue #665",
    ]
    for req in required_sections:
        if req not in content:
            errors.append(
                f"ref_r7rs_compliance.md: Missing required section/reference '{req}'"
            )
    return errors


def main() -> int:
    print("=" * 70)
    print(" Verifying R7RS Specification Traceability and Diagnostic Tags")
    print("=" * 70)

    all_errors = []

    print("[1/4] Auditing ulisp/lib/**/*.sld Traceability headers...")
    sld_errors = verify_sld_traceability_headers()
    if sld_errors:
        all_errors.extend(sld_errors)
        for err in sld_errors:
            print(f"  [FAIL] {err}")
    else:
        sld_count = len(list(LIB_DIR.glob("**/*.sld")))
        print(
            f"  [PASS] All {sld_count} .sld files contain valid Traceability headers."
        )

    print("[2/4] Auditing ulisp/lib/*.scm section comments...")
    scm_errors = verify_scm_section_comments()
    if scm_errors:
        all_errors.extend(scm_errors)
        for err in scm_errors:
            print(f"  [FAIL] {err}")
    else:
        scm_count = len(list(LIB_DIR.glob("*.scm")))
        print(
            f"  [PASS] All {scm_count} .scm files contain R7RS section comments (;; §...)."
        )

    print("[3/4] Auditing frontend compiler diagnostic tags...")
    diag_errors = verify_frontend_diagnostic_tags()
    if diag_errors:
        all_errors.extend(diag_errors)
        for err in diag_errors:
            print(f"  [FAIL] {err}")
    else:
        print("  [PASS] Frontend compiler diagnostics contain [R7RS §...] tags.")

    print("[4/4] Auditing ref_r7rs_compliance.md coverage...")
    doc_errors = verify_compliance_doc()
    if doc_errors:
        all_errors.extend(doc_errors)
        for err in doc_errors:
            print(f"  [FAIL] {err}")
    else:
        print(
            "  [PASS] ref_r7rs_compliance.md contains §3 and all recent issue references."
        )

    print("=" * 70)
    if all_errors:
        print(f" RESULT: FAILED ({len(all_errors)} errors detected)")
        print("=" * 70)
        return 1

    print(" RESULT: 100% PASS (All Traceability & Diagnostic Criteria Met)")
    print("=" * 70)
    return 0


if __name__ == "__main__":
    sys.exit(main())
