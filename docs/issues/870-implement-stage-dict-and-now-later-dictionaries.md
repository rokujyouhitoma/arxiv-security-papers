---
ID: 870
種別: Feature
優先度: High
ステータス: Open (New)
---

# [FEAT] <stage-dict> レコードおよび Now/Later ステージ辞書の実装 (ID: 870)

## 1. 概要 / Summary
DSN-33-03 §3.1 に基づき、ステージ多相評価の第一級インフラとなる `<stage-dict>` レコードと、ホスト即時評価を行う `Now` 辞書、残余 ANF 命令ノードを生成する `Later` 辞書を実装する。コンパイラ自身のセルフホスト制約（No-set! / Fixed-Arity）に厳格に準拠する。

---

## 2. トレーサビリティ / Traceability
- 関連資料: [DSN-33-03 §3.1, §3.2, §3.3, §3.7](docs/designs/DSN-33-03-ulisp_stage_polymorphic_metacompiler_and_futamura_projection_architecture.md#31-stage-dict-レコードと辞書渡しプロトコル)
- 関連 Issue: #825 (eval-in-language)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [ulisp/compiler/eval_in_language.scm](ulisp/compiler/eval_in_language.scm)
- [ ] [ulisp/compiler/nanopass_meta.scm](ulisp/compiler/nanopass_meta.scm)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/870-implement-stage-dict-and-now-later-dictionaries`

1. `make-stage-dict` レコードを定義し、関数テーブル（apply-prim-1..4, bind-let, emit-if, emit-call, lift-val, signal-csp-error）を配備。
2. `make-now-dict` を実装（ホスト環境での即時計算）。
3. `make-later-dict` を実装（MIR-ANF の `let-anf` 命令生成）。
4. 内部状態は cons セル Box 化で保持し、トップレベル・局所 `set!` を完全排除。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] `<stage-dict>` がセルフホスト制約下でコンパイル・実行できること。
- [ ] `Now` 辞書と `Later` 辞書が同一インターフェースで呼び出し可能であること。
- [ ] `make py_compile` および `make static_analysis` が PASS すること。
