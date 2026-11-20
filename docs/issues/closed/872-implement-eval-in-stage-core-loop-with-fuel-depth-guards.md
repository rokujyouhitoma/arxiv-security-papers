---
ID: 872
種別: Feature
優先度: High
ステータス: Closed (Completed)
---

# [FEAT] eval-in-stage コアループと Fuel/Depth リソースバウンドガードの実装 (ID: 872)

## 1. 概要 / Summary
DSN-33-03 §2.6, §3.5, §3.7 に基づき、ステージ多相評価器の再帰コアループ `eval-in-stage` を実装した。
単一の AST 走査コードで即時評価（Now）と残余 ANF 生成（Later）の両面を実行可能とし、CWE-400（制御不能なリソース消費）対策としてステップ数（`fuel`）および再帰深度（`depth`）を厳格に制限。
さらに、多層タワー（$L_3 \to L_2 \to L_1 \to L_0$）の平坦化に向けた相対ステージレベル遷移規則（Stage-Level デクリメント規律）と、セルフホスト制約（No-set!, Fixed-Arity, cons Box 化）を完備。

---

## 2. トレーサビリティ / Traceability
- 関連仕様書:
  - [DSN-33-03 §2.6, §3.5, §3.7](docs/designs/DSN-33-03-ulisp_stage_polymorphic_metacompiler_and_futamura_projection_architecture.md#35-eval-in-stage-コアループ仕様と安全リソースバウンド-fueldepth)
  - [DSN-33-02 §7.1 (LIR Reference VM)](docs/designs/DSN-33-02-ulisp_self_healing_compiler_pipeline_and_diagnostic_s_expressions.md)
- 関連 Issue:
  - #825 (CTFE Fuel / CWE-400 ガード)
  - #870 (stage-dict および Now / Later 辞書)
  - #871 (PSDS `<stage-val>` および二重 Source Span)
  - #873 (単一ソース意味論オラクル回帰検証)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [ulisp/compiler/eval_in_language.scm](ulisp/compiler/eval_in_language.scm) - `eval-in-stage`, `stage-eval-expr`, `stage-eval-level` の追加
- [x] [ulisp/tests/test_eval_in_stage.scm](ulisp/tests/test_eval_in_stage.scm) - コアループ・Fuel/Depth・相対レベルの単体テスト
- [x] [ulisp/Makefile](ulisp/Makefile) - `test_eval_in_stage` ターゲットの追加
- [x] [docs/issues/README.md](docs/issues/README.md) - Issue ステータス更新

---

## 4. 詳細設計と実装方針 / Implementation Plan
Target Branch: `feat/872-implement-eval-in-stage-core-loop-with-fuel-depth-guards`

### 4.1 `eval-in-stage` コアループ仕様
`(eval-in-stage dict env expr fuel depth)`
1. **リソースバウンド検証（CWE-400 ガード）**:
   - `fuel <= 0`: `(stage-signal-csp-error dict 'ctfe-fuel-exhausted expr)` を呼び出して安全停止。
   - `depth <= 0`: `(stage-signal-csp-error dict 'ctfe-depth-overflow expr)` を呼び出して安全停止。
2. **構文ディスパッチ**:
   - リテラル / 定数 (`number?`, `boolean?`, `string?`, `char?`, etc.):
     - `make-static-val` で pure-static な `<stage-val>` を生成。
   - クォート (`(quote datum)`):
     - `make-static-val` で pure-static な datum を返却。
   - シンボル参照:
     - `env` から探索。見つかればその束縛値、未束縛なら `make-dynamic-val`。
   - 条件分岐 (`(if test then else)`):
     - `test` を再帰評価。
     - `stage-val-pure-static?` の場合:
       - 静的分岐判定を実行。`stage-val-payload` が真値なら `then` のみ評価、偽値なら `else` のみ評価（静的死滅コード消去）。
     - 動的 / PSDS の場合:
       - `(stage-emit-if dict test-val (lambda () then-thunk) (lambda () else-thunk))` で残余 `if` を発行。
   - 局所束縛 (`(let ((var val) ...) body)`):
     - 各束縛式を評価し、環境を拡張して `body` を評価。動的束縛は残余 `let` を発行。
   - プリミティブ・関数適用 (`(op arg ...)`):
     - 演算子および実引数を再帰評価し、`stage-apply` (固定長ディスパッチ) を呼び出す。

### 4.2 相対ステージレベル遷移 (`stage-eval-level`)
1. 式評価コンテキストに `stage-level` (整数) を導入。
2. 外側の評価器を通過するごとに `stage-level` を 1 減算。
3. `stage-level > 0` の間は `Now` 辞書（即時インメモリ評価・マクロ展開）。
4. `stage-level == 0` の場合は `Later` 辞書（残余コード生成）へと自動切り替え。
5. `stage-level < 0` は CSP 違反として遮断。

### 4.3 セルフホスト No-set! / Fixed-Arity 規律
- 評価器内での `(set! ...)` の使用を完全禁止。
- 内部ディスパッチは `apply` や `. rest` を使わず、固定長シグネチャまたはリスト再帰で処理。

---

## 5. 完了条件 / Success Criteria (DoD)
- [x] `eval-in-stage` が `Now` 辞書と `Later` 辞書の双方で決定論的に動作すること。
- [x] 静的 `if` において不要な分岐がコンパイル時に 100% 消去されること。
- [x] 動的 `if` において両節が残余化され、正しく残余 AST が発行されること。
- [x] `fuel <= 0` で `ctfe-fuel-exhausted` エラーが捕捉され、無限ループが確実に遮断されること。
- [x] `depth <= 0` で `ctfe-depth-overflow` エラーが捕捉され、スタックオーバーフローが防止されること。
- [x] `stage-eval-level` により相対レベル方式のステージ遷移が正しく機能すること。
- [x] `make -C ulisp test_eval_in_stage` が 0件エラー PASS すること。
- [x] `make -C ulisp test_stage_dict` および `test_psds_provenance` を含む全テストが PASS すること。
- [x] `make py_compile && make static_analysis` が PASS すること。

