---
ID: 397
種別: Feature
優先度: Medium
ステータス: Open (In Progress)
---

# [FEAT/ENH] 中断スパイダーの巡回状態（Frontier）保存・デーモンによる自動再開（Resume）機能の実装 (ID: 397)

## 1. 概要 / Summary
NVD/CVE や IACR 等の長時間に及ぶクローラー実行がプロセス再起動、タイムアウト、レート制限バックオフ、または一時エラー等で中断された際、低レイヤーのクローラーエンジン（`src/spider/runner.py`, `src/spider/distributed/state_storage.py`）に備わっているフロンティア状態永続化・再開機能（`state_file`, `resume_from_state`）を、常駐デーモン（`SpiderDaemonWorker`）、透過クライアント（`SpiderDaemonClient`）、ワークフロータスク（`SpiderTaskOperator`）、および Web Gateway から透過的に活用可能とする。
これにより、中断ジョブ発生時や次回クローラー起動時に未巡回キュー（Frontier）および既訪問ブルームフィルタ（Bloom Filter）を安全に引き継ぎ、過去の取得重複を完全に防ぎながら自動再開（Resume）できる信頼性の高いパイプライン連携を確立する。

### 再開・中断シナリオ / Scenarios & Lifecycle
1. **クロール中断の発生**:
   - `nvd_cve` などの大規模クローラーが実行中に SIGTERM、例外、またはプロセス再起動により中断される。
2. **フロンティアとBloomフィルタの保護**:
   - 中断時に `outputs/spider/checkpoints/<spider_name>.state` に未巡回キューおよび既巡回Bloomフィルタのバイナリ状態がアトミックに書き出される。
3. **デーモン/クライアントによる自動再開**:
   - 次回実行時、未完了チェックポイントが存在する場合に `--resume`（`resume_from_state=True`）が自動適用され、未巡回URLから再開。
4. **正常完了時の安全破棄**:
   - 全キューの巡回が完了（未巡回URLなし）した時点でチェックポイントファイルが安全に自動削除（アンリンク）され、クリーンな初期状態に復帰する。

### 対象環境 / Environment
- OS / Env: Linux x86_64 / Antigravity Python Core
- Target Files: `src/core/structures/bloom_filter.py`, `src/spider/distributed/state_storage.py`, `src/spider/runner.py`, `src/spider/daemon/worker.py`, `src/spider/daemon/client.py`, `src/workflow/operators/spider_operator.py`

---

## 2. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [src/core/structures/bloom_filter.py](../../src/core/structures/bloom_filter.py) (`BloomFilter.to_dict/from_dict`, `ScalableBloomFilter.to_dict/from_dict` 実装による完全状態復元のサポート)
- [ ] [src/spider/distributed/state_storage.py](../../src/spider/distributed/state_storage.py) (`StateStorage.save_state`, `restore_state` の BloomFilter 連動、`has_checkpoint`, `clear_checkpoint`, `get_checkpoint_path` 等の管理メソッド追加)
- [ ] [src/spider/runner.py](../../src/spider/runner.py) (`run_spider` におけるデフォルトチェックポイントパス解決、例外/中断時の確実な状態保存、正常完了時のチェックポイント自動削除)
- [ ] [src/spider/daemon/worker.py](../../src/spider/daemon/worker.py) (`_execute_crawl` での `state_file` および `resume_from_state` パラメータ連携)
- [ ] [src/spider/daemon/client.py](../../src/spider/daemon/client.py) (`_execute_local_async` での `state_file` および `resume_from_state` 透過連携)
- [ ] [src/workflow/operators/spider_operator.py](../../src/workflow/operators/spider_operator.py) (`_merge_params` での `state_file` / `auto_resume` 連携)
- [ ] [src/web/gateway/handlers.py](../../src/web/gateway/handlers.py) (`handle_spider_trigger` での `resume` オプション対応)
- [ ] [tests/spider/test_spider_distributed_and_runner.py](../../tests/spider/test_spider_distributed_and_runner.py) (Bloom Filter を含むフロンティア完全保存・再開テスト)
- [ ] [tests/spider/test_spider_daemon.py](../../tests/spider/test_spider_daemon.py) (Worker / Client 経由の中断・再開ライフサイクルテスト)
- [ ] [tests/spider/test_spider_core.py](../../tests/spider/test_spider_core.py) (`ScalableBloomFilter` の辞書シリアライズ/デシリアライズテスト)

---

## 3. 根本原因分析 (RCA) / Root Cause Analysis
1. **上位オーケストレーション層でのパラメータ脱落**:
   - `src/spider/runner.py` は `state_file` と `resume_from_state` を受け取る機能を保持しているが、`SpiderDaemonWorker._execute_crawl`、`SpiderDaemonClient._execute_local_async`、`SpiderTaskOperator._merge_params` のいずれにもこれらの引数が渡されておらず、上位層から利用不可能になっていた。
2. **StateStorage における Bloom Filter シリアライズの欠落**:
   - 従来の `StateStorage.save_state` は `bloom_count`（件数数値）のみを保存し、実際の BloomFilter ビット配列を保存していなかった。
   - そのため再開時に `scheduler.bloom` が空となり、`start_urls` や既にスクレイプ済みの URL が再登録され、重複クロールを引き起こす重大な欠陥が存在していた。
3. **ライフサイクルと連動した例外安全な状態保存・破棄の欠落**:
   - `run_spider` 内の `StateStorage.save_state` は `engine.crawl()` の正常終了後にのみ配置されており、例外やキャンセル発生時に実行されなかった。
   - また、すべての巡回が完了した際にも状態ファイルが残り続けるため、次回実行時に古い空状態を読み込んでしまう設計上の不備があった。

---

## 4. セキュリティ・信頼性分析 (Security & Threat Model)
- **脅威カテゴリ**:
  - **CWE-400 (Uncontrolled Resource Consumption)**: 再開時に訪問済み状態が欠落すると、外部データソース（arXiv, NVD, IACR）へ数千〜数万件の重複リクエストを再送し、レート制限（429 Too Many Requests）や IP BAN を引き起こす。
  - **CWE-22 (Improper Limitation of a Pathname to a Restricted Directory)**: 外部パラメータ `state_file` にディレクトリトラバーサル文字列（例: `../../etc/passwd`）が渡された場合の任意ファイル上書きリスク。
  - **CWE-362 (Race Condition / Inconsistent State File)**: 保存処理中のプロセス中断により破損した JSON が残るリスク。
- **緩和策**:
  - `ScalableBloomFilter` のビット配列を完全保存・復元し、重複リクエストを 0 件に抑止。
  - `state_file` は許可されたディレクトリ（`outputs/spider/checkpoints/`）配下のファイル名（サニタイズされた `spider_name`）をデフォルトとし、相対・絶対パスの正規化検証を行う。
  - 一時ファイル（`.tmp`）への安全な書き出しと `os.replace` によるアトミック更新の徹底。

---

## 5. 暫定対処と恒久対策 / Workaround & Permanent Fix
* **暫定対処 (Workaround)**: CLI から `python3 -m spider.runner --spider nvd_cve --state-file outputs/spider/checkpoints/nvd_cve.state --resume` を直接手動指定して実行。
* **恒久対策 (Permanent Fix)**:
  1. `ScalableBloomFilter` および `BloomFilter` に `to_dict()` / `from_dict()` を追加し、BloomFilter のビット配列を可逆的に JSON 永続化可能にする。
  2. `StateStorage` にて未訪問リクエストキューと Bloom Filter の双方を完全シリアライズ。チェックポイント存在確認・削除ヘルパー（`has_checkpoint`, `clear_checkpoint`, `get_checkpoint_path`）を整備。
  3. `run_spider` において `try ... finally` を活用し、中断・例外時にチェックポイントを確実に保存、全巡回完了時には自動的にチェックポイントをクリーンアップ。
  4. `SpiderDaemonWorker`, `SpiderDaemonClient`, `SpiderTaskOperator`, `handle_spider_trigger` の全層へ `state_file` / `auto_resume` を透過的に連動。

---

## 6. 実装方針 / Implementation Plan
Target Branch: `feat/397-spider-frontier-state-persistence-and-daemon-resume`

1. **BloomFilter / ScalableBloomFilter の状態シリアライズ実装**:
   - `src/core/structures/bloom_filter.py`:
     - `BloomFilter.to_dict()`: `num_bits`, `num_hashes`, `capacity`, `error_rate`, `count`, `data_hex` (バイナリの 16 進表現) を出力。
     - `BloomFilter.from_dict(cls, data)`: 辞書から完全復元。
     - `ScalableBloomFilter.to_dict()`: `initial_capacity`, `error_rate`, `scale_factor`, `filters` (各サブフィルタ辞書リスト) を出力。
     - `ScalableBloomFilter.from_dict(cls, data)`: 全階層サブフィルタを含めて完全復元。
   - Xenon CC <= 3 を厳格に順守。

2. **StateStorage の完全永続化とチェックポイント管理 API**:
   - `src/spider/distributed/state_storage.py`:
     - `save_state(scheduler, filepath)`: `pending_requests` に加え `bloom_state: scheduler.bloom.to_dict()` を JSON 出力。
     - `restore_state(scheduler, filepath)`: `pending_requests` を優先度キューに復元し、`bloom_state` が存在する場合は `scheduler.bloom = ScalableBloomFilter.from_dict(...)` を復元。
     - `get_default_checkpoint_path(spider_name: str, base_dir: str = "outputs/spider/checkpoints") -> str`: パス解決（安全なファイル名サニタイズ）。
     - `has_checkpoint(spider_name: str, base_dir: str = "outputs/spider/checkpoints") -> bool`: 未完了チェックポイントの存在検査。
     - `clear_checkpoint(spider_name: str, base_dir: str = "outputs/spider/checkpoints") -> bool`: 状態ファイルの安全な削除。

3. **run_spider のライフサイクル連動型チェックポイント管理**:
   - `src/spider/runner.py`:
     - 引数 `auto_checkpoint: bool = True` を新設し、`state_file` 未指定時でもデフォルトチェックポイント（`outputs/spider/checkpoints/<spider_name>.state`）を自動適用可能とする。
     - `auto_resume: bool = True` の場合、既存チェックポイントが存在すれば自動で `resume_from_state=True` をセット。
     - `try ... finally` ブロックによる例外安全なハンドリング:
       - 巡回中断時または `scheduler.has_pending_requests()` の場合: `StateStorage.save_state(scheduler, state_file)` を実行。
       - 正常完了かつ未処理リクエスト 0 件の場合: `StateStorage.clear_checkpoint(spider_name)` によりチェックポイントを自動削除。

4. **Daemon Worker / Client への透過連携**:
   - `src/spider/daemon/worker.py`:
     - `_execute_crawl(job)`: `job.params` から `state_file`, `resume_from_state`, `auto_resume` を取り出して `run_spider` に引数伝搬。
   - `src/spider/daemon/client.py`:
     - `_execute_local_async(job)`: 同様に `run_spider` へパラメータ伝搬。

5. **Workflow Task Operator & Web API 連携**:
   - `src/workflow/operators/spider_operator.py`:
     - `_merge_params`: `state_file`, `resume_from_state`, `auto_resume` をサポート。
   - `src/web/gateway/handlers.py`:
     - `handle_spider_trigger`: クエリまたは JSON から `resume: bool = True` を受け取り、`CrawlJob.params` に格納。

6. **テスト作成と品質検証**:
   - `tests/spider/test_spider_core.py`: `ScalableBloomFilter.to_dict/from_dict` の往復テスト。
   - `tests/spider/test_spider_distributed_and_runner.py`: 中断（疑似停止）後の Bloom Filter 保持・未巡回キュー再開・完了時削除のテスト。
   - `tests/spider/test_spider_daemon.py`: Worker および Client を介したチェックポイント自動再開テスト。
   - `make static_analysis` (Xenon A, Mypy Strict) および `make test` の通過。

---

## 7. 完了条件 / Success Criteria (DoD)
- [ ] `ScalableBloomFilter` および `BloomFilter` がビット配列の欠落なく辞書経由で可逆的にシリアライズ／デシリアライズできること。
- [ ] クロール中断時に未巡回 URL キューおよび既巡回 Bloom Filter が `outputs/spider/checkpoints/<spider_name>.state` に安全に保存されること。
- [ ] チェックポイントが存在する状態で次回スパイダーを実行した際、既巡回 URL を再取得することなく未巡回リクエストから自動再開できること。
- [ ] 全ての未巡回リクエストを処理し正常終了した際には、チェックポイントファイルが安全に自動削除されること。
- [ ] `SpiderDaemonWorker`、`SpiderDaemonClient`、`SpiderTaskOperator`、および Gateway API 経由でチェックポイント再開が透過的に機能すること。
- [ ] 全ての新規・変更関数の循環的複雑度が CC <= 3 (Xenon Rank A) かつ Mypy Strict に適合すること。
- [ ] `tests/spider/` を含む全テスト（`make test`）および静的解析（`make static_analysis`）が 100% PASS すること。
