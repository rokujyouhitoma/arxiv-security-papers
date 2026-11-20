---
ID: 871
種別: Feature
優先度: High
ステータス: Open (New)
---

# [FEAT] PSDS（部分静的データ構造）と二重 Source Span 出自追跡の実装 (ID: 871)

## 1. 概要 / Summary
DSN-33-03 §3.4 に基づき、骨格のみ静的で葉が動的な部分静的データ構造（PSDS: Partially Static Data Structures）の `<stage-val>` を実装し、ペアやクロージャに対する静的還元を実現する。また、二村射影後のデバッグ性を保証するため、`host-span` と `guest-span` を保持する二重 Source Span（Provenance Stack）を統合する。

---

## 2. トレーサビリティ / Traceability
- 関連資料: [DSN-33-03 §3.4](docs/designs/DSN-33-03-ulisp_stage_polymorphic_metacompiler_and_futamura_projection_architecture.md#34-部分静的データ構造psdsと二重ソース位置情報dual-source-span)
- 関連 Issue: #824 (Source Span)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [ulisp/compiler/eval_in_language.scm](ulisp/compiler/eval_in_language.scm)
- [ ] [ulisp/compiler/binding.scm](ulisp/compiler/binding.scm)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/871-support-psds-and-dual-source-span-provenance`

1. `<stage-val>` に `kind`（'pure-static, 'partially-static, 'pure-dynamic）と `host-span`, `guest-span` を定義。
2. `stage-cons`, `stage-car`, `stage-cdr` による PSDS 還元ルールを実装（骨格はコンパイル時消去）。
3. AST 走査時に二重 Span を伝播し、残余ノードに Provenance を保持。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] PSDS ペアに対する `car`/`cdr` がコンパイル時に消去され、残余コードに残らないこと。
- [ ] エラー時にホストとゲストのソース位置が正確に分離して追跡できること。
- [ ] `make py_compile` が PASS すること。
