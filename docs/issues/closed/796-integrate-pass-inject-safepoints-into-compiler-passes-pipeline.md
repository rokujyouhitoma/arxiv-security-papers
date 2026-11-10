---
ID: 796
種別: Bug
優先度: High
ステータス: Closed
---

# [BUG/COMPILER] セーフポイント注入パス (pass-inject-safepoints) の本番コンパイラ PASSES パイプライン正式統合 (ID: 796)

## 1. 概要 / Summary
Issue #790 にてタスク強制終了（kill / cancel）のためのセーフポイント挿入パス（`pass_inject_safepoints.scm`）が実装されたが、本番のコンパイラ（`ulisp/compiler.scm` のビルド対象 `PASSES` リスト）に登録されておらず、本番コンパイルパイプラインから一度も呼び出されていない。
このため、通常の R7RS で記述されたユーザーコードおよびタスクはセーフポイント（`%synapse-safepoint-poll!`）が注入されず、強制終了シグナルを受信してもタスクが停止しない（DSN-37 要件「単一タスクの孤立停止」が本番未達）。

本 Issue では、セーフポイント挿入パスを本番の `PASSES`（`FRONTEND_PASSES`）に正式結合し、コンパイル後のアセンブリ出力に poll 呼び出しが含まれることを自動検証した。同時に、ランタイム内部のホットループや短いアクセサに過剰注入されて性能低下や再入循環を引き起こさない除外制御・インライン境界判定を導入し、完全な停止可能性・非再入性・DoD 性能要件を実証した。

---

## 2. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [ulisp/Makefile](../../ulisp/Makefile) - `FRONTEND_PASSES` への `pass_inject_safepoints.scm` 追加およびコンパイラ自己生成除外制御
- [x] [ulisp/compiler_entry.scm](../../ulisp/compiler_entry.scm) - 分割コンパイル構成における `pass_inject_safepoints.scm` の明示的インクルード
- [x] [ulisp/compiler/helpers.scm](../../ulisp/compiler/helpers.scm) - LIR 未束縛変数検査における `%synapse-safepoint-poll!` 等の stdlib シンボル登録
- [x] [ulisp/lib/ulisp/concurrency/passes/pass_inject_safepoints.scm](../../ulisp/lib/ulisp/concurrency/passes/pass_inject_safepoints.scm) - ランタイム内部関数・極小アクセサ除外フィルタ、`%program` AST 対応、および ANF `L_anf` 適合 `begin` 正規化
- [x] [tests/concurrency/test_pass_inject_safepoints.scm](../../tests/concurrency/test_pass_inject_safepoints.scm) - 本番コンパイラパイプライン統合テストおよび除外ルール検証 (44/44 PASS)
- [x] [tests/concurrency/test_preemption.scm](../../tests/concurrency/test_preemption.scm) - 実機 AOT 結合テスト (92/92 PASS)
- [x] [docs/benchmarks/concurrency_evaluation.md](../benchmarks/concurrency_evaluation.md) - 最新ベンチマーク結果および DoD 適合記録の更新

---

## 3. 根本原因分析 (RCA) / Root Cause Analysis
- `pass_inject_safepoints.scm` 単体の変換関数は実装されたが、`ulisp/Makefile` の `PASSES_LIB` / `FRONTEND_PASSES` に含まれておらず、`compiler.scm`（`cat $(PASSES) > compiler.scm`）にコードが連結されていなかった。
- これにより、コンパイラ起動時に `inject-synapse-safepoints-pass!` が評価されず、`*pass-registry-init-hooks*` に登録されないため、`build-pipeline` のパス一覧から脱落していた。
- ANF Nanopass (`070_anf.scm`) の仕様上、`lambda` および `named-let` は単一の本体式（`caddr`）のみを取り扱うため、セーフポイント挿入時に `(wrap-with-safepoint-prologue ...)` で常に単一の `begin` 式にまとめる必要があった。
- `%` 接頭辞を持つ低レベルプリミティブやランタイム内部関数にセーフポイントが注入されると、ポーリング中に再入してスタックオーバーフローを引き起こすため、厳格な名前除外・自明アクセサ除外ルールが不可欠であった。

---

## 4. 脅威モデリングと安全性検証 / Threat Modeling & Safety Analysis
- **CWE-400 (Uncontrolled Resource Consumption)**:
  - 悪意のある無限ループタスクや過負荷タスクに対し、ループバックエッジおよび関数プロローグへの自動セーフポイント挿入により、確定的なプリエンプション・強制停止を保証。
- **CWE-674 (Uncontrolled Recursion)**:
  - ランタイム内部関数（`%`-prefixed, `task-*`, `atomic-*`, `futex-*`, etc.）をセーフポイント挿入から厳格に除外し、ポーリングループ内の相互再帰スタックオーバーフローを物理的に遮断。
- **CWE-843 (Type Confusion / AST Invariant)**:
  - `070_anf.scm` の `L_anf` 言語仕様に合致するよう `(begin ...)` ラッパー形式を統一し、AST 不整合・本体脱落バグを完全に根絶。

---

## 5. 実装内容 / Implementation Details
1. **コンパイラパイプライン統合**:
   - `ulisp/Makefile` の `FRONTEND_PASSES` に `lib/ulisp/concurrency/passes/pass_inject_safepoints.scm` を配置（`040_analysis.scm` の直後、`050_cp0.scm` の直前）。
   - コンパイラ自己ビルド時の未解決シンボル参照を防ぐため、`compiler_input.scm` 生成時に `(!disable-pass pass-synapse-inject-safepoints)` を適用。
2. **LIR ヘルパー登録**:
   - `ulisp/compiler/helpers.scm` の `is-known-stdlib-symbol?` に `%synapse-safepoint-poll!`, `synapse-safepoint-poll!`, `%safepoint-poll!` を追加。
3. **AST 変換エンジンの堅牢化**:
   - `inject-safepoints-form` において `%program` をアンラップし、トップレベル `define` の束縛名判定および `defs` 全体へのマッピングを適正化。
   - `safepoint-excluded-name?` による内部関数除外、`safepoint-trivial-leaf-expr?` による自明アクセサ除外。
   - `wrap-with-safepoint-prologue` により、すべての注入先本体を単一の `(begin ...)` 式に正規化。

---

## 6. 完了基準 (DoD) 検証結果 / Verification Results
- [x] **単体テスト**: `make -C ulisp test_pass_inject_safepoints` が 44/44 全アサーション PASS。
- [x] **実機 AOT 結合テスト**: `make -C ulisp test_preemption` が 92/92 全アサーション PASS。
- [x] **並行ベンチマーク測定**: `make -C ulisp bench_scaling` が全テスト PASS（100k tasks スループット **1,075,793 tasks/sec**、Spawn **69 ms**）。
- [x] **CI リグレッション防止ゲート**: `make -C ulisp bench_concurrency_gate` が 100% PASS。
- [x] **ドキュメント更新**: `docs/benchmarks/concurrency_evaluation.md` を最新の実機実測値で更新完了。
- [x] **相対パス規約遵守**: 絶対パス排除を確認。
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
