---
ID: 801
種別: Feature
優先度: High
ステータス: Closed
---

# [FEAT/PERF] 正常終了タスク向け Fast-path Termination による実行フェーズオーバーヘッドの削減 (ID: 801)

## 1. 概要 / Summary

Synapse 並行処理ランタイム（[DSN-37](../designs/DSN-37-synapse_dual_plane_concurrent_runtime_architecture.md)）において、タスク終了処理 `task-handle-termination!`（`ulisp/runtime/concurrency/links.scm`）は、タスクが正常終了（`reason == 'normal`）した場合であっても、以下の重厚な処理が無差別に実行されている：

1. **終了理由のディープコピー**: イミュータブルなシンボル `'normal` に対する無駄な `(channel-deep-copy reason)`
2. **無条件のバスロック更新**: リンクや監視が存在しない（未初期化または空リスト）場合でも、`atomic-swap!`（`LOCK XCHG` プレフィックス命令）を `monitored-by-box` と `links-box` に対して発行
3. **不要なリソース解放ループ**: 空リストに対する走査とクリーンアップオーバーヘッド
4. **レジストリ登録解除フック**: 登録されていないマイクロタスクに対するフック呼び出しオーバーヘッド
5. **ディスパッチの階層化**: `task-exit!` からの多重関数呼び出しとアリティディスパッチ

[Issue #800](closed/800-implement-lazy-allocation-for-task-context-atomic-boxes.md) において、未初期化メタデータタスクに対する最低限のバイパスが導入されたが、正常終了するマイクロタスクの大多数（ベンチマークでは 100%）に対して、依然として不要なディープコピーやレジストリ検査が実行されている。
本 Issue では、正常終了かつ monitor/link/owned-channels が存在しないタスク向けに、不要なディープコピーや box swap を全スキップして直ちにタスク状態を `terminated` に更新し、テーブルから削除して返却する「Fast-path Normal Exit」を導入する。
これにより、10 万タスク実行フェーズ所要時間（64 ms）のさらなる短縮（目標 <40 ms）と、1,800,000 tasks/sec 突破を目指す。

---

## 2. 脅威モデリングと安全性検証 / Threat Modeling & Safety Analysis

| 脅威 / 脆弱性 | 影響度 | 想定攻撃・故障シナリオ | 設計・実装による対策と検証プロトコル |
| :--- | :---: | :--- | :--- |
| **CWE-362 (Race Condition / TOCTOU)** | High | Fast-path 判定中に別ワーカーが `task-monitor` や `task-link!` を実行し、DOWN/EXIT 通知が消失する。 | 先行して `(task-state-set! task 'terminated)` をアトミック更新しメモリフェンスを発行。Issue #725 で確立された「終了済みタスクへの monitor/link は即時 DOWN/EXIT を返却する」不変条件により、通知消失を物理的に防止。 |
| **CWE-401 (Memory Leak / Unreleased Resources)** | High | Fast-path 判定の誤りにより、所有チャネルやアリーナが解放されずにプロセス内に残存・リークする。 | Fast-path の適用条件を「`reason == 'normal` かつ `meta` が `#f` または監視・リンク・所有チャネルがすべて空（`'()`）」に限定。所有チャネルやアリーナが存在する場合は確実に通常パス（Slow-path）へ委譲。 |
| **CWE-833 (Deadlock / Missed DOWN Signal)** | High | 監視対象タスクが Fast-path を誤通過し、ウォッチャーへの `'DOWN` シグナルが送信されず、受信側が永久デッドロックに陥る。 | `meta` が存在し `monitors-box` が非空リストである場合は 100% Slow-path（`%deliver-monitor-down!`）を強制。Fast-path へのバイパスは監視・リンクの完全不在が証明された場合に限定。 |
| **CWE-843 (Type Confusion)** | Medium | 非タスクオブジェクトや不正な reason 型が渡された際に Fast-path が誤動作する。 | 入口における型ガード `(task-context? task)` を堅持し、reason の `eq? 'normal` チェックにより型安全性を保証。 |

---

## 3. ガバナンス & 専門家レビュー / Specialist Perspectives

- **Project Manager (PM)**:
  - 10 万並行マイクロタスク耐久ベンチマークにおいて、Issue #800 で達成した 156 万 tasks/sec から、さらなる極限性能（180 万 tasks/sec 超え）を達成し、Go/Rust との差を極限まで縮めるための重要課題。
- **Systems Architect (SA)**:
  - 実行頻度が 99.9% を占める正常終了（`'normal`）と、0.1% 未満のエッジケースである異常終了（パニック・カスケードキル）の処理系パスを物理的に分岐。ホットパスからロック命令とメモリ割り当てを完全排除する。
- **Software Development (SWD)**:
  - `task-exit!` から `task-handle-termination!` に至るコールチェーンを最適化。イミュータブルシンボル `'normal` に対する `channel-deep-copy` をスキップし、単一の高速インラインチェックで終了状態へ遷移させる。
- **Software Quality Assurance (SQA)**:
  - `test_channel`, `test_links_monitors`, `test_multithread_scheduler`, `test_supervisor` の全テストに加え、10 回連続の `test_concurrency_stress` を通して、Fast-path 導入後も DOWN 通知やリンクカスケードの動作が 100% 狂わないことを機械的に保証。
- **Information Security Specialist (SEC)**:
  - タスク終了時のリソース解放保証（CWE-401）と、通知消失によるプロセスハング（CWE-833）の完全遮断。Fast-path の前提条件が崩れた場合のフェイルセーフ設計を徹底。

---

## 4. 影響範囲と関連ファイル / Scope and Affected Files

- [x] [ulisp/runtime/concurrency/links.scm](../../ulisp/runtime/concurrency/links.scm) - `task-handle-termination!` および `task-exit!` の Fast-path 最適化
- [x] [ulisp/runtime/concurrency/registry.scm](../../ulisp/runtime/concurrency/registry.scm) - `synapse-unregister-target!` における空レジストリ早期スキップ
- [x] [tests/concurrency/test_channel.scm](../../tests/concurrency/test_channel.scm) - 正常終了タスク向け Fast-path 検証テストの追加
- [x] [docs/benchmarks/concurrency_evaluation.md](../benchmarks/concurrency_evaluation.md) - 実行フェーズ所要時間およびスループット向上測定値の更新

---

## 5. 実装方針 / Implementation Plan

Target Branch: `feat/801-implement-fast-path-for-normal-task-termination`

### Step 1: `task-handle-termination!` における Fast-path 判定とディープコピー回避
1. 終了理由 `reason` が `'normal` であるか、または即値（シンボル・数値・真偽値）であるかを判定。
2. `reason` が `'normal` かつ `(not (task-meta-fast task))` の場合：
   - `channel-deep-copy` を完全バイパス。
   - `(task-state-set! task 'terminated)`
   - `(task-reductions-set! task 0)`
   - プロセスレジストリ未登録タスクの高速アンレジスタ
   - `(task-table-unregister! task)`
   - 即座に `#t` を返却（ヒープ確保 0、`LOCK XCHG` バスロック 0）。

### Step 2: メタデータ初期化済みタスクの Fast-path 判定（Lock-free 空判定）
1. `(task-meta-fast task)` が存在する場合でも、以下の条件をすべて満たす場合は Fast-path を適用：
   - `(eq? reason 'normal)`
   - `(null? (atomic-ref (task-monitors-box task)))`
   - `(null? (atomic-ref (task-links-box task)))`
   - `(null? (atomic-ref (task-owned-channels-box task)))`
2. 上記条件を満たす場合、`atomic-swap!`（`LOCK XCHG`）を発行することなく、単に `atomic-set!` で `'closed` へ更新するか、または必要時のみ閉塞して終了。

### Step 3: `task-exit!` コールチェーンのインライン最適化
1. `(task-exit! task)` （引数 1 つ）および `(task-exit! task 'normal)` の呼び出しに対し、直接 Fast-path を起動できるようディスパッチオーバーヘッドを最小化。

### Step 4: 単体テストおよび並行ストレステスト検証
1. `tests/concurrency/test_channel.scm` に Fast-path 正常終了テストを追加：
   - リンク・監視なしタスクが正常に `terminated` に遷移しテーブルから削除されること。
   - 監視付きタスクが正常終了した場合は確実に DOWN メッセージが配信されること。
   - リンク付きタスクが異常終了した場合は確実にカスケードキルされること。
2. `make -C ulisp lint_sexpr`
3. `make -C ulisp test_channel`
4. `make -C ulisp test_links_monitors`
5. `make -C ulisp test_multithread_scheduler`
6. `make test_concurrency_stress`（10 回連続 PASS）

### Step 5: ベンチマーク測定とドキュメント更新
1. `make -C ulisp bench_concurrency_gate` を実行し、10 万タスク実行フェーズ所要時間の短縮（<50 ms）とスループット（>1,600,000 tasks/sec）を確認。
2. `docs/benchmarks/concurrency_evaluation.md` を最新の実測値で更新。

---

## 6. 完了条件 / Success Criteria (DoD)

- [x] **Fast-path 正常終了**: リンク・監視を持たない正常終了タスクが不要なディープコピーやバスロックなしに即座に終了すること。
- [x] **並行安全性 (CWE-362 ゼロ)**: Fast-path 終了と並行して行われる `task-monitor` や `task-link!` において、通知の消失が発生しないこと。
- [x] **リソース漏洩ゼロ (CWE-401 ゼロ)**: チャネルやアリーナを保持するタスクが Fast-path で誤終了せず、確実にリソースが解放されること。
- [x] **通知完全性 (CWE-833 ゼロ)**: 監視付きタスクの終了時における `'DOWN` メッセージ配信が 100% 保証されること。
- [x] **単体テスト**: `make -C ulisp test_channel` および `test_links_monitors` が 100% PASS すること。
- [x] **並行ストレステスト**: `make test_concurrency_stress`（10 回反復）が 100% PASS すること。
- [x] **CI リグレッションゲート**: `make -C ulisp bench_concurrency_gate` が 100% PASS すること。
- [x] **相対パス規約遵守**: ドキュメントおよびコードにおいて絶対パスが完全排除されていること。
