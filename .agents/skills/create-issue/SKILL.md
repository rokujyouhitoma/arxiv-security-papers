---
name: create-issue
description: Create a new issue file under the issues/ directory in the workspace.
---
# create-issue

This skill dictates how to initialize a new issue file to ensure uniformity and clarity.

## Instructions

1. **Check Existing Issues**:
   - List the files under `docs/issues/` to find the next sequential number.
   - If no issues exist, the first issue will be `001`.

2. **Filename Format**:
   - The file MUST be created under the `docs/issues/` directory.
   - Format: `docs/issues/<3-digit-padded-number>-<hyphenated-lowercase-title>.md`.
   - Example: `docs/issues/001-implement-keyboard-shortcuts.md`

3. **Content Template selection**:
   - Depending on the issue type, copy the content structure from either:
     - Bug Fixes / Vulnerabilities: `.agents/skills/create-issue/resources/template_bug.md`
     - Features / Refactoring / Enhancements: `.agents/skills/create-issue/resources/template_feature.md`
   - Fill in the metadata block at the top of the file:
     - `ID`: Set to the 3-digit padded number (e.g., `002`).
     - `種別`: Set to the issue type (`Bug` or `Feature`).
     - `優先度`: Set to `High`, `Medium`, or `Low`.
     - `ステータス`: Initialize to `Open (New)`.
   - Update the issue heading: `# [BUG/SEC] <Title> (ID: <3-digit-padded-number>)` or `# [FEAT/ENH] <Title> (ID: <3-digit-padded-number>)`.
   - Populate **1. 概要 / Summary** with a concise description of the objective or problem.
   - Populate **2. 影響範囲と関連ファイル / Scope and Affected Files** with a list of the target files or folders that need to be investigated or edited.
   - For bugs, fill in steps to reproduce or known environments. Keep other technical planning/DoD sections blank or placeholders. These will be filled in during the `polish-issue` phase.

4. **Register in Issue Ledger**:
   - Right after creating the issue file, open [docs/issues/README.md](README.md) (Issue台帳).
   - Append a new row to the **1. アクティブIssue一覧** table with the status set to `New` and linking to the newly created issue file.
