---
ID: 790
種別: Bug
優先度: High
ステータス: Closed
完了日: 2026-11-09
---

# [BUG/SEC] R7RS タスク強制終了のためのセーフポイント挿入パス (pass-synapse-inject-safepoints) のコンパイラ統合 (ID: 790)

## 1. 概要 / Summary
通常の R7RS Scheme で記述された並行タスクに対し、協調的プリエンプションおよび非同期強制終了（Cancel / Termination / Panic propagation）を保証するためのセーフポイント自動挿入パス（`pass-synapse-inject-safepoints`）が、コンパイラの標準パスレジストリ（`init-default-pass-registry!`）およびコンパイルパイプラインに組み込まれておらず未接続となっている問題を解消した。

従来、`pass_inject_safepoints.scm` に実装されているセーフポイント挿入パスは、パス単体テスト（`test_pass_inject_safepoints.scm`）時のみ手動で `(inject-synapse-safepoints-pass!)` を呼び出して Pass Manager に動的注入されており、Prerequisites が `'(pass-synapse-fbip)` に固定されていたため標準パイプラインでの自動接続が妨げられていた。
本改修では、Pass Manager に初期化フック機構（`register-pass-registry-init-hook!`）を導入し、セーフポイント挿入パスの DAG 前提条件を動的に適応（`pass-030-desugar` / `pass-040-analysis` / `pass-synapse-fbip` / `inline-hotpath` 両対応）させることで、標準パスレジストリの初期化時に自動登録・接続されるアーキテクチャを確立した。また、純粋なループに対するセーフポイント挿入と強制終了シグナル捕捉の実証テスト（Group 7 / Group 10）を追加し、100% PASS を達成した。

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
- [x] [ulisp/compiler/pass_manager.scm](../../../ulisp/compiler/pass_manager.scm): パスレジストリ初期化フック（`*pass-registry-init-hooks*`, `register-pass-registry-init-hook!`, `unregister-pass-registry-init-hook!`）の実装、`init-default-pass-registry!` からの自動起動。
- [x] [ulisp/compiler.scm](../../../ulisp/compiler.scm): モノリシックコンパイラ / pass_manager 同期コード内のパスレジストリ初期化フック更新。
- [x] [ulisp/lib/ulisp/concurrency/passes/pass_inject_safepoints.scm](../../../ulisp/lib/ulisp/concurrency/passes/pass_inject_safepoints.scm): `synapse-safepoint-prerequisites` による柔軟な DAG 前提条件解決、動的配置順序の適応、ロード時の初期化フック自動登録。
- [x] [ulisp/lib/ulisp/concurrency/passes/inject_safepoints.sld](../../../ulisp/lib/ulisp/concurrency/passes/inject_safepoints.sld): R7RS ライブラリエクスポートの確認・整備。
- [x] [tests/concurrency/test_pass_inject_safepoints.scm](../../../tests/concurrency/test_pass_inject_safepoints.scm): Group 7 としてデフォルトレジストリ自動登録、DAG 検証、動的無効化（`disable-pass!`）、AST 自動注入検証テストの追加。
- [x] [tests/concurrency/test_preemption.scm](../../../tests/concurrency/test_preemption.scm): Group 10 としてセーフポイント自動挿入ループにおける異常終了シグナル捕捉・タスク強制終了実証テストの追加。

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
  2. `pass_manager.scm` に初期化フック（`register-pass-registry-init-hook!`）を実装し、`pass_inject_safepoints.scm` ロード時に自動フックを登録することで、パイプライン初期化時に自動で組み込まれるようにした。
  3. 手動ポーリング呼び出しを一切含まない純粋な R7RS ループ（`let loop () (loop))`）をコンパイルした際、AST および生成 LIR に `%synapse-safepoint-poll!` が確実に注入されることを単体テスト（Group 7）で検証。
  4. `test_preemption.scm` に、手動チェックを行わない純粋なループタスクがタイムアウトや停止シグナル（`task-exit! 'killed'` / Reduction 枯渇）により正常にコンテキストスイッチおよび強制終了される新規テストグループ（Group 10）を追加。

---

## 6. 実装方針と検証結果 / Implementation Plan & Results
Target Branch: `fix/790-integrate-safepoint-pass-to-pipeline`

### Step 1: パス記述子と DAG 依存関係の柔軟化
- `ulisp/lib/ulisp/concurrency/passes/pass_inject_safepoints.scm`:
  - `synapse-safepoint-prerequisites` を実装。`pass-synapse-inline-hotpath`, `pass-synapse-fbip`, `pass-040-analysis`, `pass-035-scope-resolve`, `pass-030-desugar` を動的に検知して適切な前提パスを返すよう柔軟化。

### Step 2: Pass Manager への統合
- `ulisp/compiler/pass_manager.scm` および `ulisp/compiler.scm`:
  - `*pass-registry-init-hooks*` 管理機構を追加。
  - `init-default-pass-registry!` 末尾で登録済みフックを実行。
  - `pass_inject_safepoints.scm` ロード時に自動フック登録。

### Step 3: AST 変換およびコンパイル検証テストの拡充
- `tests/concurrency/test_pass_inject_safepoints.scm`:
  - Group 7 を追加し、デフォルトパイプライン自動登録、DAG 解決、動的無効化（`disable-pass!`）、AST 自動注入を検証（35 passed, 0 failed）。

### Step 4: プリエンプション＆タスク強制終了の統合実証
- `tests/concurrency/test_preemption.scm`:
  - Group 10 を追加し、ループバックエッジのセーフポイントによる外部終了シグナルの即時捕捉・脱出を実証（92 passed, 0 failed）。

### Step 5: 全テストスイートの一括検証
- `make -C ulisp test_pass_inject_safepoints`: 全 35 アサーション 100% PASS
- `make -C ulisp test_pass_manager`: 全 61 アサーション 100% PASS
- `make -C ulisp test_preemption`: 全 92 アサーション 100% PASS
- `make -C ulisp test_concurrency`: 全 13,600 アサーション 100% PASS
- `make -C ulisp test_passes`: 全 147 単体テスト 100% PASS
- `make verify_quality`: 2,766 テスト 100% PASS (83.15% coverage)

---

## 7. 完了条件 / Success Criteria (DoD)
- [x] `synapse-inject-safepoints-descriptor` の前提条件が整理され、標準パイプラインおよび動的プラグイン構成の双方で DAG 不整合（Prerequisites violation）が発生しないこと。
- [x] コンパイラの標準パイプラインにおいて `pass-synapse-inject-safepoints` がデフォルトで登録・実行可能となっていること。
- [x] 手動の `%synapse-safepoint-poll!` や `check-safepoint!` を一切記述しない純粋な Scheme ループコードに対して、コンパイラによってセーフポイントが自動挿入されること。
- [x] 純粋なループを実行するタスクに対し、Reduction 枯渇によるプリエンプションおよび別タスク・スケジューラからの停止シグナルが正常に処理され、タスクがハングアップせずに終了できること。
- [x] 既存の全 Nanopass コンパイラテスト、Pass Manager テスト、並行性テスト（`test_preemption`, `test_scheduler`, `test_supervisor`, `test_multithread_scheduler`）が 100% PASS すること。
- [x] すべてのファイルリンクが相対パス（`../../../...`）であり、絶対パスが 0 件であること。
