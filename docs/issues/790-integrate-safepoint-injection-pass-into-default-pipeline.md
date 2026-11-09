---
ID: 790
種別: Bug
優先度: High
ステータス: Open (In Progress)
---

# [BUG/SEC] R7RS タスク強制終了のためのセーフポイント挿入パス (pass-synapse-inject-safepoints) のコンパイラ統合 (ID: 790)

## 1. 概要 / Summary
通常の R7RS Scheme で記述された並行タスクに対し、協調的プリエンプションおよび非同期強制終了（Cancel / Termination / Panic propagation）を保証するためのセーフポイント自動挿入パス（`pass-synapse-inject-safepoints`）が、コンパイラの標準パスレジストリ（`init-default-pass-registry!`）およびコンパイルパイプラインに組み込まれておらず未接続となっている問題を解消する。

現在、`pass_inject_safepoints.scm` に実装されているセーフポイント挿入パスは、パス単体テスト（`test_pass_inject_safepoints.scm`）時のみ手動で `(inject-synapse-safepoints-pass!)` を呼び出して Pass Manager に動的注入されている。通常のコンパイラビルドおよび実行バイナリ生成時にはこのパスが実行されない。
さらに、プリエンプションの統合テスト（`test_preemption.scm`）においても、タスク本体コード内に手動で `(%synapse-safepoint-poll!)` や `(check-safepoint! ...)` を明示的に記述して検証していたため、純粋な R7RS Scheme ループ（`named-let`、再帰、タイトな計算ループ）を実行するタスクに対して外部から停止シグナル（Cancellation / Abort）を発行しても検知できず、タスクが CPU を独占して無限ループまたはハングアップに陥る脆弱性が残存している。

本 Issue では、セーフポイント自動挿入パスをコンパイラの標準パイプラインに正式に統合し、純粋な Scheme コードのループバックエッジおよび関数プロローグへ `%synapse-safepoint-poll!` を自動挿入可能とすることで、外部停止シグナルによる安全かつ確実なタスク終了機構を確立する。

---

## 2. セキュリティ脅威分析 / Threat Model & Security Impact
- **対象脆弱性**:
  - **CWE-400**: Uncontrolled Resource Consumption (CPU Starvation) - 協調的プリエンプションの欠如により、タイトなループを実行するタスクがワーカースレッドの CPU 時間を無期限に占有し、同一スケジューラ上の他タスクがスタベーションに陥る。
  - **CWE-835**: Loop with Unreachable Exit Condition ('Infinite Loop') / Uncancellable Task - スーパーバイザや親タスクから強制終了（`task-exit! 'killed'` / `task-panic!`）が要求されても、セーフポイントが存在しないため実行コンテキストが中断シグナルを検知できず、リソースの回収・クリーンアップが行われない。
- **STRIDE 分類**:
  - **Denial of Service (DoS)**: 悪意ある、あるいはバグを含むタスクが無限ループに突入した際、システム全体のワークステーションが停止・ハングアップする。
- **セキュリティ保証目標**:
  - すべてのループ構文（`named-let`、末尾再帰呼び出し、`while`/`for` 糖衣構文）および手続き境界（`define`、`lambda`）において、コンパイラが自動的に還元カウンタ減算および割込みポーリング（`%synapse-safepoint-poll!`）を挿入し、計算量に関わらず確定的・協調的なプリエンプションと外部キャンセレーションを保証する。

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [ulisp/compiler/pass_manager.scm](../../ulisp/compiler/pass_manager.scm): パスレジストリ初期化（`init-default-pass-registry!`）への `pass-synapse-inject-safepoints` の組み込み、DAG Prerequisites の解決。
- [ ] [ulisp/compiler.scm](../../ulisp/compiler.scm): モノリシックコンパイラ / pass_manager 同期コード内のパスレジストリ更新。
- [ ] [ulisp/lib/ulisp/concurrency/passes/pass_inject_safepoints.scm](../../ulisp/lib/ulisp/concurrency/passes/pass_inject_safepoints.scm): パス記述子（Prerequisites を `pass-synapse-fbip` 依存から柔軟な `pass-030-desugar` / `pass-040-analysis` 連携へリファクタリング、あるいは FBIP オプション有無への両対応）。
- [ ] [ulisp/lib/ulisp/concurrency/passes/inject_safepoints.sld](../../ulisp/lib/ulisp/concurrency/passes/inject_safepoints.sld): R7RS ライブラリエクスポートの確認・整備。
- [ ] [tests/concurrency/test_pass_inject_safepoints.scm](../../tests/concurrency/test_pass_inject_safepoints.scm): 単体テストにおける標準パイプラインおよび動的注入時の回帰検証。
- [ ] [tests/concurrency/test_preemption.scm](../../tests/concurrency/test_preemption.scm): 手動ポーリングを排除した純粋 R7RS ループによる協調的プリエンプション＆外部キャンセレーション統合テストの追加・改修。

---

## 4. 根本原因分析 (RCA) / Root Cause Analysis
1. **Pass Manager 標準パイプラインからの分離**:
   - `ulisp/compiler/pass_manager.scm` の `init-default-pass-registry!` では、標準 Nanopass パイプライン（`pass-010-library` 〜 `pass-133-lir-peephole`）のみが静的に登録されており、Synapse 並行性関連パスはオプトインの動的プラグインとしてのみ設計されていた。
   - コンパイルドライバ（`ulisp/compiler/driver.scm`）経由で通常の `.scm` をビルドする際、セーフポイント挿入パスが呼ばれず、生成されるネイティブコードにはポーリング命令が一切含まれていなかった。
2. **Prerequisites DAG の硬直性**:
   - `synapse-inject-safepoints-descriptor` の依存前提が `'(pass-synapse-fbip)` に固定されていたため、`pass-synapse-fbip` を組み込まない標準コンパイルパイプラインでは Prerequisites チェック（`validate-pipeline-prerequisites`）で不整合が発生する制約があった。
3. **テスト設計における欺瞞的パス**:
   - `test_preemption.scm` ではタスクループ内に直接 `(check-safepoint! ...)` や明示的 `(scheduler-yield! ...)` がハードコードされていたため、コンパイラによる自動注入が機能していなくてもテストが PASS してしまい、パイプライン非接続が見落とされていた。

---

## 5. 暫定対処と恒久対策 / Workaround & Permanent Fix
* **暫定対処 (Workaround)**:
  - ユーザーが作成するすべての Scheme 関数およびループ末尾に手動で `(%synapse-safepoint-poll!)` または `(scheduler-yield! ...)` を埋め込む（純粋な Scheme コードの可搬性が失われ、記述漏れによる DoS のリスクが残る）。
* **恒久対策 (Permanent Fix)**:
  1. `pass_inject_safepoints.scm` の記述子定義を見直し、Prerequisites を `'(pass-030-desugar)`（または `pass-035-scope-resolve` / `pass-040-analysis`）等の標準 Core パスに設定（`pass-synapse-fbip` や `inline-hotpath` がある場合はその後に自動配置されるよう配慮）。
  2. コンパイラの標準パイプライン（`pass_manager.scm` および `compiler.scm`）において、Core レベル（`L_core`）の標準変換フェーズに `pass-synapse-inject-safepoints` を登録（または `--enable-safepoints` / デフォルト有効フラグでパイプラインに組み込み）。
  3. 手動ポーリング呼び出しを一切含まない純粋な R7RS ループ（`let loop () (loop))`）をコンパイルした際、AST および生成 LIR に `%synapse-safepoint-poll!` が確実に注入されることを検証するテストを追加。
  4. `test_preemption.scm` に、手動チェックを行わない純粋なループタスクがタイムアウトや停止シグナル（`task-exit! 'killed'` / Reduction 枯渇）により正常にコンテキストスイッチおよび強制終了される新規テストグループを追加。

---

## 6. 実装方針 / Implementation Plan
Target Branch: `fix/790-integrate-safepoint-pass-to-pipeline`

### Step 1: パス記述子と DAG 依存関係の柔軟化
- `ulisp/lib/ulisp/concurrency/passes/pass_inject_safepoints.scm`:
  - `synapse-inject-safepoints-descriptor` の前提条件を調整。単体でも `pass-030-desugar` 直後に安全に挿入可能とし、かつ `pass-synapse-fbip` や `pass-synapse-inline-hotpath` が存在する場合はそれらの後続として挿入される順序保証ロジックを確立。

### Step 2: Pass Manager への統合
- `ulisp/compiler/pass_manager.scm` および `ulisp/compiler.scm`:
  - `init-default-pass-registry!` 内、または並行性サポート有効時のパイプライン構築において、`pass-synapse-inject-safepoints` を Core フェーズ（`pass-035-scope-resolve` と `pass-070-anf` の間）にデフォルト登録。
  - パスが無効化された場合（`--disable-pass pass-synapse-inject-safepoints`）のバイパス経路も担保。

### Step 3: AST 変換およびコンパイル検証テストの拡充
- `tests/concurrency/test_pass_inject_safepoints.scm`:
  - 標準パスレジストリ初期状態からのパイプライン構築（`build-pipeline 0 '()`）で `pass-synapse-inject-safepoints` が正しく認識され、Prerequisites DAG が PASS することを確認するテストケースを追加。
  - `(run-pass-pipeline forms #f #f)` を通じた自動変換で、純粋な `named-let` および `define` 関数に `%synapse-safepoint-poll!` が注入されることを検証。

### Step 4: プリエンプション＆タスク強制終了の統合実証
- `tests/concurrency/test_preemption.scm`:
  - Group 8 として「手動ポーリング無しの純粋 Scheme 無限ループタスクの強制終了テスト」を追加。
  - タスク A が純粋な `(let loop () (loop))` を実行中、スケジューラが reduction 減算によりタスク A をプリエンプトし、別タスク B の実行や外部からの終了リクエストを正常に完了できることを実証。

### Step 5: 全テストスイートの一括検証
- `make -C ulisp test_pass_inject_safepoints`
- `make -C ulisp test_pass_manager`
- `make -C ulisp test_preemption`
- `make -C ulisp test_concurrency`
- `make verify_quality`

---

## 7. 完了条件 / Success Criteria (DoD)
- [ ] `synapse-inject-safepoints-descriptor` の前提条件が整理され、標準パイプラインおよび動的プラグイン構成の双方で DAG 不整合（Prerequisites violation）が発生しないこと。
- [ ] コンパイラの標準パイプラインにおいて `pass-synapse-inject-safepoints` がデフォルトで登録・実行可能となっていること。
- [ ] 手動の `%synapse-safepoint-poll!` や `check-safepoint!` を一切記述しない純粋な Scheme ループコードに対して、コンパイラによってセーフポイントが自動挿入されること。
- [ ] 純粋なループを実行するタスクに対し、Reduction 枯渇によるプリエンプションおよび別タスク・スケジューラからの停止シグナルが正常に処理され、タスクがハングアップせずに終了できること。
- [ ] 既存の全 Nanopass コンパイラテスト、Pass Manager テスト、並行性テスト（`test_preemption`, `test_scheduler`, `test_supervisor`, `test_multithread_scheduler`）が 100% PASS すること。
- [ ] すべてのファイルリンクが相対パス（`../../...`）であり、絶対パスが 0 件であること。
