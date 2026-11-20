---
ID: 880
種別: Feature
優先度: High
ステータス: Closed (Completed)
---

# [FEAT] Pass Manager への Nanopass 文法完全消去アサーションの組み込み (ID: 880)

## 1. 概要 / Summary
DSN-33-03 §6.3 に基づき、中間言語 `L-StagePoly` から `L-Residual-ANF` への遷移（`stage-poly-lower` パス）直後に中間 AST を全走査し、未解決の `stage-now`, `stage-later`, `stage-lift`, `stage-quasiquote` などのメタ構文が 1 つでも残存していないかを静的アサーション検証する文法消去チェッカー `verify-residual-anf-conformance` を `verifier.scm` および `pass_manager.scm` に組み込む。

---

## 2. トレーサビリティ / Traceability
- 関連個別仕様書:
  - [DSN-33-03 §6.3 (Nanopass Verifier による文法消去アサーション)](docs/designs/DSN-33-03-ulisp_stage_polymorphic_metacompiler_and_futamura_projection_architecture.md#63-nanopass-verifier-による文法消去アサーション)
  - [DSN-33-03 §6.2 (L-Residual-ANF 言語定義)](docs/designs/DSN-33-03-ulisp_stage_polymorphic_metacompiler_and_futamura_projection_architecture.md#62-l-residual-anf-言語定義メタ構文の完全除外--)
- 関連 Issue:
  - #878 (Nanopass 中間言語 L-StagePoly および L-Residual-ANF の定義)
  - #879 (ステージ多相部分評価 Nanopass stage-poly-lower の実装)
  - #881 (3重差分テストオラクルとメタモルフィック摂動検証スイート)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [ulisp/compiler/verifier.scm](ulisp/compiler/verifier.scm) - メタ構文走査述語 `find-stage-meta-syntax` および `verify-residual-anf-conformance` の実装
- [x] [ulisp/compiler/pass_manager.scm](ulisp/compiler/pass_manager.scm) - `pass-out-lang` / `vphase` に応じた文法消去アサーションの自動フック
- [x] [ulisp/tests/test_grammar_conformance_assertion.scm](ulisp/tests/test_grammar_conformance_assertion.scm) - アサーション発火と文法消去の単体テスト
- [x] [ulisp/Makefile](ulisp/Makefile) - `test_grammar_conformance_assertion` ターゲット追加
- [x] [docs/issues/README.md](docs/issues/README.md) - 台帳ステータス更新

---

## 4. 詳細設計と実装方針 / Implementation Plan
Target Branch: `feat/880-integrate-grammar-conformance-assertion-in-pass-manager`

### 4.1 文法消去チェッカー `verify-residual-anf-conformance`
1. 再帰的 S 式走査関数 `(find-stage-meta-syntax form)` を実装:
   - 先頭シンボルが `stage-now`, `stage-later`, `stage-lift`, `stage-quasiquote` のいずれかであるリストを検出した場合、その式を返す。
   - `pair?` の car/cdr を深さ優先探索（DFS）で走査。
2. `(verify-residual-anf-conformance ast)`:
   - メタ構文が見つかった場合、`verifier-error` を呼び出し `"Grammar Conformance Violation: residual AST contains meta-syntax: ..."` を送出、`#f` を返す。
   - 見つからなければ `#t` を返す。
3. `verify-pass-output`:
   - `(case phase ... ((residual-anf stage-poly-lower) (verify-residual-anf-conformance data)) ...)` を追加。

### 4.2 パスマネージャ統合
- `run-single-pass` にて `(pass-out-lang pass-desc)` が `'L-Residual-ANF` である場合、または `vphase` が `'residual-anf` である場合、強制的に `verify-residual-anf-conformance` を実行。
- 違反時は `error` を送出し、未消去メタ構文のランタイム漏洩を遮断。

---

## 5. 完了条件 / Success Criteria (DoD)
- [x] 未評価メタ構文（`stage-now`, `stage-later`, `stage-lift`, `stage-quasiquote`）を含む AST に対してビルド/検証が確実に Fail（`Grammar Conformance Violation`）すること。
- [x] 正常に平坦化された `L-Residual-ANF` AST が 100% 検証をパスすること。
- [x] `make -C ulisp test_grammar_conformance_assertion` が 0件エラー PASS すること。
- [x] `make py_compile && make static_analysis` が PASS すること。
