# Custom Agent Rules for arxiv-security-papers

This file contains project-scoped rules and instructions for all AI agents working in the `arxiv-security-papers` repository.

---

## 1. Governance & PM-Led Multi-Agent Framework

All major feature additions, pipeline modifications, schema changes, and documentation restructuring MUST be conducted under the leadership of the **Project Manager (PM)** agent, integrating multi-perspective reviews from all 13 specialized agents:

1. **Project Manager (PM)** (Chair / Governance)
2. **Information Security Specialist** (Domain classification & Security Attestation)
3. **Systems Architect** (Pipeline Architecture & Dataflow)
4. **Software Quality Assurance Specialist** (Quality Gates & Idempotency)
5. **Database / Data Infrastructure Specialist** (Raw Data Storage & Index Catalog)
6. **Network Specialist** (arXiv API / RSS Fallback & HTTP Resilience)
7. **IT Specialist (NLP & Info Retrieval)** (`pdftotext` Extraction & Japanese Summary Quality)
8. **IT Strategist** (Executive Summary Tiering & Trend Analysis)
9. **IT Service Manager** (Batch Operations & Log Audit)
10. **Embedded Systems Specialist** (Low-level / IoT Security Tagging)
11. **Systems Auditor** (Traceability & Provenance Verification)
12. **UI/UX & Documentation Designer** (Markdown Table & Layout Visuals)
13. **Education Specialist** (Terminology Accuracy & Readability)

---

## 2. Development & Issue Workflow Rules

You MUST follow this structured, issue-driven development lifecycle for all modifications, documentations, and new features:

1. **Issue Creation (`create-issue`)**:
   - Every task, pipeline optimization, refactoring, or feature MUST start with an issue file under `docs/issues/`.
   - Use `create-issue` to initialize a new issue and register it in `docs/issues/README.md`.

2. **Issue Refinement (`polish-issue`)**:
   - Before modifying code or schemas, refine the issue using `polish-issue`.
   - Map dependencies, implementation steps, target files, branch name, and Definition of Done (DoD).

3. **Implementation & Python Quality Gates**:
   - Follow feature branch naming (`feat/<issue-id>-<desc>`, `fix/<issue-id>-<desc>`, `refactor/<issue-id>-<desc>`).
   - Run `python3 -m py_compile arxiv_okf_fetcher.py` and verify syntax cleanliness.
   - Run `verify-quality-gates` to validate OKF v0.2 schemas, relative links, idempotency state, and directory consistency.

4. **Issue Closing & Git Workflow (`git-workflow`)**:
   - Move issue file to `docs/issues/closed/<issue-id>-<desc>.md`.
   - Update `docs/issues/README.md`.
   - Use `git-workflow` to commit with Conventional Commit format referencing the Issue ID.

---

## 3. Google OKF v0.2 Specification Compliance

- All converted paper markdown documents in `outputs/okf_papers/YYYY-MM-DD/<clean_id>.md` MUST conform to Google Open Knowledge Format (OKF) v0.2.
- Mandatory YAML Frontmatter keys:
  - `type`: `"security-paper"`
  - `title`: Paper Title
  - `description`: Japanese 1-sentence executive summary
  - `resource`: `https://arxiv.org/abs/<arxiv_id>`
  - `tags`: Security domain tags (e.g. `cryptography`, `web-security`, `zero-trust`, `network-security`)
  - `timestamp`: ISO 8601 UTC timestamp
  - `provenance`: Origin (`arxiv.org`), relative path to raw metadata JSON, publication date, authors list
  - `trust`: Attestation / digital signature details

---

## 4. 5-Tier Executive Summaries (01-05 Sequential Directories)

Executive summaries in `outputs/executive_summaries/` MUST be maintained in sorted, zero-padded sequential directories (01_ to 05_):

1. **`01_per_run/`**: Per-execution batch summary (1日4回 00/06/12/18) (`run_HHMM.md`)
2. **`02_daily/`**: Daily aggregated summary (`YYYY-MM-DD.md`)
3. **`03_monthly/`**: Monthly trend summary (`monthly_YYYY-MM-DD.md`)
4. **`04_quarterly/`**: Quarterly summary (`quarterly_YYYY-MM-DD.md`)
5. **`05_annual/`**: Annual summary (`annual_YYYY-MM-DD.md`)

- **100% Japanese Compliance**: All summary prose, headers, and paper table entries MUST be 100% in Japanese.
- **Markdown Tables**: Paper listings within summaries MUST use structured markdown tables with columns: `arxiv_id`, `タイトル (日本語)`, `カテゴリ`, `要約 (1文)`, `詳細リンク`.

---

## 5. Raw Data Preservation & Idempotency Rules

- **Raw Data Storage**: `outputs/raw_data/YYYY-MM-DD/` MUST contain:
  - `<clean_id>_meta.json` (arXiv API JSON metadata)
  - `<clean_id>_raw_abstract.txt` (Original English Abstract)
  - `<clean_id>.pdf` (Direct PDF download from arXiv)
  - `<clean_id>.txt` (Full-text extracted via `pdftotext`)
- **Idempotency**: `processed_papers.json` MUST track all processed `arxiv_id`s to prevent duplicate processing.
- **Traceability**: All OKF documents MUST link back to their raw JSON metadata via relative paths.

---

## 6. Relative Link & Documentation Rules

- **Relative Paths Only**:
  - You MUST strictly use relative paths (never absolute paths like `file:///workspace/...` or `/root/...`) for all internal links across all `.md` files in `docs/`, `outputs/`, and `.agents/`.
- **Root Index Synchronization**:
  - Whenever new papers are converted or summaries generated, `outputs/index.md` and `outputs/log.md` MUST be updated.
