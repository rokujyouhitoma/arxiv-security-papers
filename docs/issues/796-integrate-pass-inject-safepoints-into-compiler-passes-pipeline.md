---
ID: 796
種別: Bug
優先度: High
ステータス: Open (In Progress)
---

# [BUG/COMPILER] セーフポイント注入パス (pass-inject-safepoints) の本番コンパイラ PASSES パイプライン正式統合 (ID: 796)

## 1. 概要 / Summary
Issue #790 にてタスク強制終了（kill / cancel）のためのセーフポイント挿入パス（`pass_inject_safepoints.scm`）が実装されたが、本番のコンパイラ（`ulisp/compiler.scm` のビルド対象 `PASSES` リスト）に登録されておらず、本番コンパイルパイプラインから一度も呼び出されていない。
このため、通常の R7RS で記述されたユーザーコードおよびタスクはセーフポイント（`%synapse-safepoint-poll!`）が注入されず、強制終了シグナルを受信してもタスクが停止しない（DSN-37 要件「単一タスクの孤立停止」が本番未達）。現在のテスト（`test_preemption.scm` 等）は変換後の S 式を手書きして poll を直接呼び出している状態にとどまっていた。

本 Issue では、セーフポイント挿入パスを本番の `PASSES` に正式結合し、コンパイル後のアセンブリ出力に poll 呼び出しが含まれることを自動検証する。同時に、ランタイム内部のホットループや短いアクセサに過剰注入されて性能低下や再入循環を引き起こさない除外制御・インライン境界判定を導入する。

### 再現手順 / Steps to Reproduce
1. 通常の R7RS 構文で無限ループを行うタスクを記述し、通常コンパイラ（`ulisp-boot` / `compiler.scm`）でビルドする。
2. スケジューラ上で当該タスクを実行し、外部から `task-handle-termination!` または kill シグナルを送信する。
3. セーフポイントが自動挿入されていないため、タスクがシグナルを検知できず停止しない現象を確認する。

### 再現環境 / Environment
- OS / Env: Linux x86-64 / macOS arm64 / Windows MinGW
- Target Files:
  - `ulisp/Makefile`
  - `ulisp/compiler/pass_manager.scm`
  - `ulisp/lib/ulisp/concurrency/passes/pass_inject_safepoints.scm`
  - `ulisp/runtime/concurrency/preempt.scm`

---

## 2. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [ulisp/Makefile](../../ulisp/Makefile) - `PASSES_LIB` への `pass_inject_safepoints.scm` 追加およびビルドチェーン統合
- [ ] [ulisp/compiler/pass_manager.scm](../../ulisp/compiler/pass_manager.scm) - `init-default-pass-registry!` におけるデフォルト登録と順序保証
- [ ] [ulisp/lib/ulisp/concurrency/passes/pass_inject_safepoints.scm](../../ulisp/lib/ulisp/concurrency/passes/pass_inject_safepoints.scm) - ランタイム内部関数・極小アクセサ除外フィルタおよびインライン境界判定の実装
- [ ] [tests/concurrency/test_pass_inject_safepoints.scm](../../tests/concurrency/test_pass_inject_safepoints.scm) - 本番コンパイラパイプライン統合テストおよび除外ルール検証
- [ ] [tests/concurrency/test_preemption.scm](../../tests/concurrency/test_preemption.scm) - 手動 poll 呼び出しを撤廃し、純粋 R7RS ループタスクの自動プリエンプション停止検証

---

## 3. 根本原因分析 (RCA) / Root Cause Analysis
- `pass_inject_safepoints.scm` 単体の変換関数は実装されたが、`ulisp/Makefile` の `PASSES_LIB` / `FRONTEND_PASSES` に含まれておらず、`compiler.scm`（`cat $(PASSES) > compiler.scm`）にコードが連結されていなかった。
- これにより、コンパイラ起動時に `inject-synapse-safepoints-pass!` が評価されず、`*pass-registry-init-hooks*` に登録されないため、`build-pipeline` のパス一覧から脱落していた。
- 結合が行われないまま、手動で `%synapse-safepoint-poll!` を埋め込んだ単体テストのみが記述されていたため、パイプライン未接続のまま Issue #790 がクローズされてしまっていた。

---

## 4. 脅威モデリングと安全性検証 / Threat Modeling & Safety Analysis
- **脅威ベクトル**:
  - 協調的マルチタスク環境において、悪意のある入力やバグによりタスクが無限ループ（ビジーウェイト）に陥った場合、セーフポイントが注入されていないとタスクを外部から停止できず、CPU リソース枯渇による DoS に至る。
  - ランタイムコア（スケジューラ、futex、セーフポイントポーリング自身）の内部関数にセーフポイントが注入された場合、ポーリング処理中に再びポーリングが呼ばれる無限再入やデッドロックが発生する。
- **セキュリティ要件と対策**:
  - すべてのユーザーコード（Layer 1 / R7RS）の関数プロローグおよびループバックエッジに確実にセーフポイントを注入し、DSN-37 要件「単一タスクの孤立停止」を保証する。
  - セーフポイント注入パスに除外リスト（`*safepoint-excluded-functions*`）および除外述語を設け、ランタイム内部関数（`%synapse-*`, `task-*`, `thread-*`, `futex-*` 等）および極小アクセサ（単一の `car`, `cdr`, 定数返却等）への不要な注入を確実に抑止する。

---

## 5. 実装方針 / Implementation Plan
Target Branch: `fix/796-integrate-pass-inject-safepoints-into-compiler-passes`

### Step 1: 除外制御・インライン境界判定の拡充 (`pass_inject_safepoints.scm`)
1. ランタイム内部手続きおよびセーフポイント自身への注入を防止する除外述語 `(safepoint-excluded-procedure? name body)` を追加。
   - 除外対象: `%synapse-*`, `task-*`, `thread-*`, `futex-*`, `arena-*`, `atomic-*`
   - 極小アクセサ除外: 本体が 1 式のみで、かつ再帰やループ呼び出しを含まない短小手続き（`car`, `cdr`, フィールドアクセス等）。
2. `(declare (no-safepoints))` やメタデータによる明示的除外構文のサポート。

### Step 2: コンパイラビルドチェーンへの正式統合 (`ulisp/Makefile`, `compiler.scm`)
1. `ulisp/Makefile` の `FRONTEND_PASSES` または `PASSES_LIB` に `lib/ulisp/concurrency/passes/pass_inject_safepoints.scm` を追加。
2. `make -C ulisp compiler.scm` で `pass_inject_safepoints.scm` が正しく結合されることを確認。
3. `compiler/pass_manager.scm` の `init-default-pass-registry!` において、`pass-040-analysis` 直後（`pass-070-anf` の前）の Core AST フェーズに正式配置。

### Step 3: 自動注入およびアセンブリ出力の検証テスト追加
1. `tests/concurrency/test_pass_inject_safepoints.scm` を拡充し、デフォルトパイプライン（`build-pipeline 0 '()`）で自動的に `pass-synapse-inject-safepoints` が組み込まれることを確認。
2. 純粋 R7RS ループ（手動 poll なし）をコンパイラでコンパイルし、出力コードに `synapse-safepoint-poll!` 呼び出しが自動生成されることを検証。
3. 極小アクセサや除外指定手続きにはセーフポイントが注入されないことを検証。

### Step 4: 実行時協調プリエンプション結合テストの改修 (`test_preemption.scm`)
1. `tests/concurrency/test_preemption.scm` の手動 `%synapse-safepoint-poll!` 記述を削除し、純粋な Scheme ループコードに置換。
2. コンパイラによる自動注入経由で、タスク終了シグナル送信時に確実に 5 回以内のループで停止することを実機検証。

### Step 5: 全体回帰テストと品質ゲートの検証
1. `make -C ulisp test`（全テストターゲット）を実行し、コンパイラ自己ホスティングや基本言語機能にリグレッションがないことを検証。
2. `make -C ulisp bench_concurrency_gate` を実行し、スループットが厳格な DoD（>1,000,000 tasks/s）を維持していることを確認。

---

## 6. 完了条件 / Success Criteria (DoD)
- [ ] `ulisp/Makefile` の `PASSES_LIB` に `pass_inject_safepoints.scm` が含まれ、`compiler.scm` に正式統合されていること。
- [ ] `compiler/pass_manager.scm` のデフォルトパイプライン初期化により、手動フック登録なしに `pass-synapse-inject-safepoints` が組み込まれること。
- [ ] ランタイム内部関数および極小アクセサへの過剰注入を抑止する除外制御が実装されていること。
- [ ] 手動で poll を埋め込まない純粋な R7RS ループコードに対して、セーフポイントが自動注入されることが単体テストで確認されること。
- [ ] `tests/concurrency/test_preemption.scm` の純粋 R7RS ループタスクが外部シグナルにより即座に孤立停止（DSN-37 充足）すること。
- [ ] `make -C ulisp test` の全テストおよび `make -C ulisp bench_concurrency_gate` が 100% PASS すること。
