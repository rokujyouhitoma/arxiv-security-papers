---
ID: 876
種別: Feature
優先度: High
ステータス: Open (New)
---

# [FEAT] CSP 越境バリデータと Dual Span 診断レポーターの実装 (ID: 876)

## 1. 概要 / Summary
DSN-33-03 §4.2 および §4.3 に基づき、Control Plane の可変セル（`set!`）やホスト継続（`call/cc`）が不正に Data Plane へ持ち込まれるのを遮断する CSP 越境バリデータを実装する。違反検知時には二重ソースマップ（`guest-span` と `host-span`）を含む `CSP-001` 診断 S式を出力する。

---

## 2. トレーサビリティ / Traceability
- 関連資料: [DSN-33-03 §4.2, §4.3](docs/designs/DSN-33-03-ulisp_stage_polymorphic_metacompiler_and_futamura_projection_architecture.md#43-コンパイル時診断-s式仕様dual-span-伝播-reporter-833-準拠)
- 関連 Issue: #833 (Diagnostic Reporter)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [ulisp/compiler/verifier.scm](ulisp/compiler/verifier.scm)
- [ ] [ulisp/compiler/diagnostic.scm](ulisp/compiler/diagnostic.scm)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/876-implement-csp-boundary-validator-and-dual-span-diagnostics`

1. `lift` 操作時に対象オブジェクトの型とミュータビリティを検査する述語を実装。
2. 可変セルまたは継続の昇格を検知した場合、`CSP-001` エラー S式を構築。
3. `provenance` から `guest-span`（DSL側位置）と `host-span`（評価器側位置）を両方抽出してレポート。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] 不正な `lift` がコンパイル時に確実に遮断されること。
- [ ] 診断 S式に `guest-span` と `host-span` が正しく含まれること。
- [ ] `make py_compile` が PASS すること。
