---
ID: 875
種別: Feature
優先度: High
ステータス: Closed (Completed)
---

# [FEAT] 動的分岐配下の純粋性解析と投機的副作用・例外の自動 Later 降格 (ID: 875)

## 1. 概要 / Summary
DSN-33-03 §4.2 に基づき、動的条件分岐（Later `if`）配下に含まれる Now 式の純粋性（Purity）および例外発生リスクを解析し、副作用（I/O, 状態更新）や例外（ゼロ除算など）を伴う式を自動的に Later（残余コード）へと降格させ、Speculative Trap（投機的誤発火）を根絶する。
これにより、実行時には到達しないはずの分岐でのコンパイル時クラッシュを完全に排除し、実行時の遅延評価意味論および副作用順序（Effect Ordering）と 100% 一致させる。

---

## 2. トレーサビリティ / Traceability
- 関連仕様書:
  - [DSN-33-03 §4.2 (Cross-Stage Persistence & Speculative Trap Protection)](docs/designs/DSN-33-03-ulisp_stage_polymorphic_metacompiler_and_futamura_projection_architecture.md#42-越境規則cross-stage-persistenceと動的分岐下の副作用例外降格規約)
  - [DSN-33-02 §3.4 (Diagnostic S-Expression)](docs/designs/DSN-33-02-ulisp_self_healing_compiler_pipeline_and_diagnostic_s_expressions.md)
- 関連 Issue:
  - #872 (eval-in-stage コアループ)
  - #874 (4値束縛時間束 BTA)
  - #876 (CSP 越境バリデータと Dual Span 診断レポーター)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [ulisp/compiler/eval_in_language.scm](ulisp/compiler/eval_in_language.scm) - 投機的実行例外安全ガードと自動 Later 降格ルールの実装
- [x] [ulisp/tests/test_speculative_trap_demotion.scm](ulisp/tests/test_speculative_trap_demotion.scm) - Speculative Trap 防止と副作用順序保証の単体テスト
- [x] [ulisp/Makefile](ulisp/Makefile) - `test_speculative_trap_demotion` ターゲットの追加
- [x] [docs/issues/README.md](docs/issues/README.md) - 台帳ステータス更新

---

## 4. 詳細設計と実装方針 / Implementation Plan
Target Branch: `feat/875-implement-purity-analysis-and-speculative-trap-demotion`

### 4.1 純粋性解析と投機的トラップ分類
1. **安全な純粋演算（Safe Pure Primitives）**:
   - `+`, `-`, `*`, `abs`, `not`, `null?`, `pair?`, `boolean?`, `number?`, `symbol?`, `string?`, `char?`, `cons`, `<`, `>`, `<=`, `>=`, `=`, `eq?`, `bitwise-*`
   - これらは引数が静的値であれば例外なくコンパイル時計算（Now 評価）可能。
2. **潜在的例外演算（Potentially Trapping Operations）**:
   - `/`, `quotient`, `modulo`, `remainder`（除数が 0 の場合にゼロ除算例外）
   - `car`, `cdr`（引数が空リストや非ペアの場合に型例外）
   - `vector-ref`, `string-ref`（インデックス範囲外例外）
3. **副作用を伴う演算（Impure / Side-Effecting Operations）**:
   - I/O 出力（`display`, `write`, `newline`）
   - 可変セル更新（`set-car!`, `set-cdr!`）

### 4.2 自動 Later 降格規約（Demotion to Residual Code）
1. `Later` 辞書（残余化フェーズ）において、動的 `if` の分岐内節を評価する際：
   - 潜在的例外演算で除数が 0 などの異常値を検知した場合、コンパイル時 CSP エラーを発行せず、**自動的に残余呼び出し式（Later）へと降格**。
   - 不純な副作用演算が含まれる場合、Now での投機実行を即座に中止し、**残余コードとして発行**。
2. 一方、純粋かつ安全な静的項（例: `(+ 10 20)`）は動的分岐配下であっても通常どおり即時計算（30）に畳み込む。
3. 静的 `if`（条件がコンパイル時に確定）においては、選択されなかった死滅分岐内の例外・副作用はコンパイル時・実行時ともに完全消去される。

---

## 5. 完了条件 / Success Criteria (DoD)
- [x] 動的 if の分岐内にあるゼロ除算 `(/ 10 0)` がコンパイル時クラッシュせず、残余コード `(if-anf (< x 0) (/ 10 0) 42)` へ自動降格されること。
- [x] 動的 if の分岐内にある安全な静的式 `(+ 10 20)` は `(if-anf (< x 0) 30 42)` へ静的畳み込みされること。
- [x] 静的 if `(if #t 42 (/ 1 0))` において、死滅分岐の例外式が完全に消去されること。
- [x] `make -C ulisp test_speculative_trap_demotion` が 0件エラー PASS すること。
- [x] 全既存テスト（`test_bta_lattice`, `test_single_source_oracle`, `test_eval_in_stage`, `test_stage_dict`, `test_psds_provenance`, `test_eval_in_language`）が PASS すること。
- [x] `make py_compile && make static_analysis` が PASS すること。
