---
ID: 670
種別: Feature
優先度: Medium
ステータス: Closed
---

# [FEAT] 構造化クラッシュレポート (SASL 相当) 生成と Layer 1 コントロールプレーン非同期転送・可観測性基盤の実装 (ID: 670)

## 1. 概要 / Summary
Erlang/OTP の SASL（System Architecture Support Libraries）および Crash Logger を参考に、Synapse 並行タスクのクラッシュ時に原因特定のための詳細な診断コンテキストを構造化レポートとして生成し、Layer 1（R7RS コントロールプレーン）へ非同期に安全転送する可観測性（Observability）基盤を構築する。

Synapse ではタスク異常終了時に Fail-Fast "Let It Crash" セマンティクス（Issue #668）によってエフェメラルアリーナが $O(1)$ でリセットされ、スーパービジョンツリー（Issue #667）によって自動再起動が行われる。しかし、タスクがなぜ異常終了したのか（燃料枯渇、アサーション違反、メモリ割り当て超過、型エラー等）の診断コンテキストが記録されない場合、本番障害の解析・根本原因分析（RCA）が極めて困難になる。

本 Issue では、計算層（Layer 2）のリアルタイム並行実行を絶対に妨げないロックフリー・リングバッファを導入し、障害発生時にタスク ID、Epoch、消費 Fuel、アリーナ消費量、障害理由コード、直前メッセージサマリ等を構造化レコード `<crash-report>` として記録・バッファリングし、Layer 1（R7RS 制御プレーン）側で人間可読な SASL スタイル診断ログおよびメトリクスとして安全に回収・集計する基盤を提供する。

---

## 2. 背景とアーキテクチャ上の位置づけ

### 2.1 DSN-37 設計仕様との対応
- **DSN-37 Section 8.4.6**: 「構造化クラッシュレポート（SASL 相当）と Layer 1 境界非同期転送」
  - タスク異常終了時、障害解析に必要なコンテキスト（Task ID、Epoch、消費 Fuel、アリーナ消費量、障害理由コード、直前メッセージサマリ）を構造化レコード `<crash-report>` として瞬時にパックする。
  - ロックフリーキューを通じて Layer 1（R7RS 制御プレーン）の非同期ロガーへ転送し、計算層（Layer 2）のリアルタイム性を一切損なうことなく、本番環境での可観測性と監査トレーサビリティを確立する。
- **DSN-37 Section 14.8 Task 6.5**: 「構造化クラッシュレポート生成と Layer 1 可観測性基盤 (`crash_logger.scm`)」

### 2.2 二重プレーン分離とノンブロッキング可観測性の原則
1. **計算層（Layer 2）へのゼロインパクト**:
   - クラッシュレポートの enqueue はノンブロッキング・ロックフリーで行われ、リングバッファが満杯の場合は古いレポートの上書きまたはドロップカウンタの加算を行い、決して計算スレッドをブロッキング（待機）させない。
2. **Shared-Nothing メモリ隔離の厳守**:
   - Layer 2 のタスクアリーナから Layer 1 へレポートを引き渡す際、`boundary.scm` のサニタイズ（ディープコピー）を経由することで、Layer 1 と Layer 2 間でのポインタ共有を完全に排除する。
3. **機密情報のサニタイズ（Data Redaction）**:
   - メッセージサマリ等のペイロードに巨大データや機密情報が含まれるリスクを考慮し、文字数制限（例: 最大 256 文字）と再帰深度制限を適用してレポートの肥大化と情報漏洩（CWE-209）を防止する。

---

## 3. トレーサビリティ / Traceability
- **関連設計書**:
  - [DSN-37 ホスト・カーネル分離型 階層 CSP/アクター並行処理基盤](../designs/DSN-37-synapse_dual_plane_concurrent_runtime_architecture.md) (Section 8.4.6 & Section 14.8 Task 6.5)
- **関連 Issue**:
  - [Issue #641: 境界サニタイザ・ディープコピーの実装](closed/641-implement-synapse-boundary-sanitizer-and-deep-copy.md)
  - [Issue #666: タスク間双方向リンクと単方向モニタの実装](closed/666-implement-synapse-task-links-and-monitors.md)
  - [Issue #667: Erlang/OTP スーパービジョンツリーと再起動戦略の実装](closed/667-implement-synapse-supervision-tree-and-restart-strategies.md)
  - [Issue #668: エフェメラルアリーナ即時破棄と Fail-Fast セマンティクスの確立](closed/668-implement-synapse-fail-fast-let-it-crash-semantics.md)
  - [Issue #669: プロセス名レジストリと動的チャネル再バインドの実装](closed/669-implement-synapse-process-registry-and-dynamic-rebinding.md)
  - [Issue #676: Linux SYS_futex による省電力ワーカー待機・起床機構の実装](closed/676-implement-synapse-futex-park-unpark-primitives.md)

---

## 4. セキュリティと堅牢性設計 (STRIDE / CWE)

| 脅威カテゴリ | 対象 CWE | 潜在リスク | 対策方針 |
|---|---|---|---|
| **Denial of Service (DoS)** | CWE-400 | クラッシュループ時にレポートが無限蓄積しメモリ枯渇 | 固定長リングバッファ（デフォルト 256 エントリ）とドロップカウンタによりメモリ上限を完全固定 |
| **Deadlock** | CWE-833 | クラッシュロガーのバッファ満杯・同期書き込みでワーカースレッドがデッドロック | 完全ノンブロッキング CAS エンキューを保証。待機・ロックを一切排除 |
| **Race Condition** | CWE-362 | 複数ネイティブワーカーからの同時クラッシュレポート登録によるバッファ破壊 | `<atomic-box>` を用いたアトミックなインデックス前進と CAS 書き込み |
| **Information Exposure** | CWE-209 / CWE-212 | クラッシュレポートに未サニタイズの機密ペイロードや循環参照が混入 | メッセージサマリの文字列長制限（256 文字）および深さ制限サニタイズ |
| **Type Confusion** | CWE-843 | 不正なオブジェクトをロガー API に渡すことによるクラッシュ | `crash-report?`, `task-context?` 等の厳格な述語検査と型アサーション |

---

## 5. 影響範囲と関連ファイル / Scope and Affected Files

### 新規作成ファイル
- `ulisp/runtime/concurrency/crash_logger.scm`: `<crash-report>`、ロックフリー `<crash-ring-buffer>`、SASL 形式フォーマッタ、メトリクス集計
- `ulisp/lib/ulisp/concurrency/crash_logger.sld`: R7RS ライブラリ定義 `(ulisp concurrency crash-logger)`
- `tests/concurrency/test_crash_logger.scm`: クラッシュレポート生成、ノンブロッキングバッファ、境界転送、メトリクス集計テスト

### 修正対象ファイル
- `ulisp/runtime/concurrency/panic.scm`: パニック発生時に自動でクラッシュレポートをバッファリングするフックの追加
- `ulisp/runtime/concurrency/supervisor.scm`: スーパーバイザによる子タスク再起動時のクラッシュレポート記録フック
- `ulisp/runtime/concurrency/eval_adapter.scm`: クラッシュロガー API の評価環境バインド
- `ulisp/Makefile`: `test_crash_logger` ターゲット追加、`lint_sexpr` および `test:` への統合

---

## 6. 実装方針 / Implementation Plan

Target Branch: `feat/670-synapse-structured-crash-reporting`

### Step 1: 構造化クラッシュレポート `<crash-report>` の定義 (`crash_logger.scm`)
1. レコード型 `<crash-report>` の定義:
   ```scheme
   (define-record-type <crash-report>
     (%make-crash-report id tid registered-name epoch fuel-consumed
                         arena-allocated arena-capacity reason details
                         source-loc last-msg-summary timestamp)
     crash-report?
     (id                  crash-report-id)
     (tid                 crash-report-tid)
     (registered-name     crash-report-registered-name)
     (epoch               crash-report-epoch)
     (fuel-consumed       crash-report-fuel-consumed)
     (arena-allocated     crash-report-arena-allocated)
     (arena-capacity      crash-report-arena-capacity)
     (reason              crash-report-reason)
     (details             crash-report-details)
     (source-loc          crash-report-source-loc)
     (last-msg-summary    crash-report-last-msg-summary)
     (timestamp           crash-report-timestamp))
   ```
2. ビルダー関数 `(make-crash-report task reason [details] [source-loc] [last-msg])`:
   - `task-context` から TID、Epoch、消費 Fuel（`task-reductions`）、アリーナ消費量（`arena-offset`）、全容量を自動抽出。
   - `registered-name` を検索または引数から取得。
   - ペイロードサマリは最大長（256 文字）で安全に切り詰める。

### Step 2: ノンブロッキング・ロックフリー `<crash-ring-buffer>` の実装
1. 固定容量配列（デフォルト 256）とアトミックな書き込みインデックス (`write-head-box`)、読み出しインデックス (`read-tail-box`)、ドロップカウンタ (`dropped-count-box`) によるリングバッファ構造。
2. `(crash-buffer-enqueue! buf report)`:
   - アトミックにスロットを獲得し、古いエントリを上書きまたはバッファリング。
   - 計算層ワーカーを一切ブロックせず $O(1)$ で完了。
3. `(crash-buffer-dequeue! buf)`:
   - Layer 1 側が未読のクラッシュレポートを 1 件取り出す。空の場合は `#f`。
4. `(crash-buffer-drain! buf)`:
   - 未読の全クラッシュレポートをリストとして一括取得。

### Step 3: Layer 1 境界転送と SASL スタイル診断フォーマッタ
1. Layer 1 への境界転送:
   - `sanitize-from-arena` により、Layer 2 のアリーナメモリから Layer 1 の GC ヒープへ完全に独立したオブジェクトとしてディープコピー。
2. 人間可読な SASL スタイルフォーマッタ `(format-crash-report report)`:
   ```text
   =CRASH REPORT==== <timestamp> ===
     crashed_task: <tid> (registered_name: worker_actor)
     supervisor:   sup_1
     reason:       out-of-fuel
     details:      (reductions-exhausted)
     source_loc:   worker.scm:42
     fuel_used:    1000
     arena_used:   1280 / 4096 bytes (31%)
     last_message: (compute-digest "packet#128")
   ```
3. 構造化エクスポート:
   - `(crash-report->alist report)`: 連想リスト形式。
   - `(crash-report->sexpr report)`: S 式形式。

### Step 4: 可観測性メトリクス集計基盤
1. 集計カウンタの保持:
   - `total-crashes`: 発生したクラッシュ総数
   - `crashes-by-reason`: 理由別発生回数
   - `dropped-reports`: バッファ溢れによるドロップ数
2. API:
   - `(synapse-crash-metrics)`: 現在の集計結果をプロパティリスト/連想リストで返却。
   - `(synapse-reset-crash-metrics!)`: カウンタのリセット。

### Step 5: `panic.scm` および `supervisor.scm` との統合
1. `synapse-cleanup-task-resources!` または `synapse-panic!` 時に、デフォルトクラッシュバッファが有効であれば自動的に `<crash-report>` を生成して enqueue。
2. スーパーバイザの `supervisor-handle-child-down!` において、子タスクが異常終了した場合にもクラッシュログを記録。

### Step 6: テストスイート拡充と Makefile 統合
1. `tests/concurrency/test_crash_logger.scm`:
   - **Group 1**: `<crash-report>` 基本生成とフィールド抽出。
   - **Group 2**: ロックフリーリングバッファのノンブロッキング enqueue/dequeue/drain。
   - **Group 3**: SASL スタイルフォーマット出力と S 式変換。
   - **Group 4**: パニック・スーパーバイザ連携時の自動レポート生成。
   - **Group 5**: 高スループット耐久テスト（1,000 件連続クラッシュ時のバッファ溢れとドロップカウンタ整合性）。
   - **Group 6**: セキュリティ・境界ガード（CWE-843, CWE-400, CWE-209/212）。
2. `ulisp/Makefile` への `test_crash_logger` 統合。

---

## 7. 完了条件 / Success Criteria (DoD)

- [x] `crash_logger.scm` および `(ulisp concurrency crash-logger)` が実装され、`<crash-report>` およびリングバッファ API が提供されること。
- [x] タスクパニック・クラッシュ時に、TID、Epoch、Fuel、Arena使用量、Reason、直前メッセージサマリが欠損なく記録されること。
- [x] リングバッファが満杯時でも計算層のワーカースレッドがデッドロック・ブロックせず、ドロップカウンタが正確にインクリメントされること（CWE-400, CWE-833）。
- [x] Layer 1 側へ安全に転送され、SASL スタイルのフォーマット文字列および S 式として取得できること。
- [x] メトリクス集計 API（`synapse-crash-metrics`）により、障害総数や原因別カウンタが取得できること。
- [x] `make -C ulisp test_crash_logger`（全テスト PASS）および全体の `make -C ulisp test` が 100% エラーなく完走すること。
- [x] Python 品質ゲート（`make py_compile` および `make static_analysis`）が 100% PASS すること。
- [x] 相対パス規則（Gate 3）の完全適合（絶対パス 0 件）。

---

## 8. レビューア・担当エージェント
- **主幹**: IT Specialist (Programming Languages & Compilers / PLC)
- **並行基盤・可観測性設計**: Systems Architect & IT Service Manager
- **セキュリティ・監査**: Information Security Specialist & Systems Auditor
- **品質保証**: Software Quality Assurance Specialist
