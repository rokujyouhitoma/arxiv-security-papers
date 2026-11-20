---
ID: 880
種別: Feature
優先度: High
ステータス: Open (New)
---

# [FEAT] Pass Manager への Nanopass 文法完全消去アサーションの組み込み (ID: 880)

## 1. 概要 / Summary
DSN-33-03 §6.3 に基づき、`stage-poly-lower` パス実行直後に中間 AST を全走査し、未解決の `stage-now`, `stage-later`, `stage-lift` などのメタ構文が 1 つでも残存していないかを静的アサーション検証する文法消去チェッカーを組み込む。

---

## 2. トレーサビリティ / Traceability
- 関連資料: [DSN-33-03 §6.3](docs/designs/DSN-33-03-ulisp_stage_polymorphic_metacompiler_and_futamura_projection_architecture.md#63-nanopass-verifier-による文法消去アサーション)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [ulisp/compiler/verifier.scm](ulisp/compiler/verifier.scm)
- [ ] [ulisp/compiler/pass_manager.scm](ulisp/compiler/pass_manager.scm)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/880-integrate-grammar-conformance-assertion-in-pass-manager`

1. `verify-residual-anf-conformance` を実装。
2. メタ構文の残存を検知した場合は `Grammar Conformance Violation` エラーを即時送出。
3. パスマネージャのパイプライン検証ゲートに常時フック。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] 未評価メタ構文を含む AST に対してビルドが確実に Fail すること。
- [ ] 正常な部分評価 AST が 100% 検証を通過すること。
- [ ] `make py_compile` が PASS すること。
