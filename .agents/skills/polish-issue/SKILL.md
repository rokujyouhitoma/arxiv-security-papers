---
name: polish-issue
description: Refine and polish an issue file in the issues/ directory before beginning implementation.
---
# polish-issue

This skill guides the agent in refining a raw issue into a concrete, action-ready design and task list before writing any code.

## Instructions

1. **Investigate Codebase**:
   - Research target files, dependencies, and relevant documents.
   - Read design docs and guidelines to identify potential side effects or constraints.
   - **If the issue introduces new input methods, data flows, or security mechanisms, analyze potential threat vectors. Identify security requirements and mitigations.**

2. **Define target Git branch**:
   - Determine the branch name format: `feat/<issue-id>-<description>` or `fix/<issue-id>-<description>`.
   - Write this target branch name at the beginning of the implementation plan.

3. **Establish Implementation Plan**:
   - Detail the exact step-by-step changes required in Section 4 or 5 (実装方針 / Implementation Plan).
   - Reference functions, variables, files, and tests that need updates.

4. **Define Success Criteria (DoD)**:
   - Specify clear, measurable goals in Section 5 or 6 (完了条件 / Success Criteria (DoD)).
   - Include testing requirements and manual verification steps.

5. **Update Issue Status & Ledger**:
   - Update the `ステータス` field in the metadata block at the top of the issue file to `Open (In Progress)`.
   - Open [docs/issues/README.md](README.md) (Issue台帳).
   - Update the status of the polished issue from `New` or `Analyzing` to `In Progress` to indicate it is ready for development.

6. **Self-Review**:
   - Review the completed issue file to verify if a developer/agent could execute it immediately without further research or ambiguity.
