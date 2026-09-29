---
ID: 397
種別: Feature
優先度: Medium
ステータス: Closed
---

# [FEAT/ENH] 中断スパイダーの巡回状態（Frontier）保存・デーモンによる自動再開（Resume）機能の実装 (ID: 397)

## 1. 概要 / Summary

NVD/CVE や IACR、arXiv 等の長時間に及ぶクローラー実行がプロセス再起動、タイムアウト、レート制限バックオフ、または一時エラー等で中断された際、低レイヤーのクローラーエンジン（`src/spider/runner.py`, `src/spider/distributed/state_storage.py`）に備わっているフロンティア状態永続化・再開機能（`state_file`, `resume_from_state`）を、常駐デーモン（`SpiderDaemonWorker`）、透過クライアント（`SpiderDaemonClient`）、ワークフロータスク（`SpiderTaskOperator`）、および Web Gateway から透過的に活用可能とする。

これにより、中断ジョブ発生時や次回クローラー起動時に未巡回キュー（Frontier）および既訪問ブルームフィルタ（Bloom Filter）を安全に引き継ぎ、過去の取得重複を完全に防ぎながら自動再開（Resume）できる信頼性の高いパイプライン連携を確立する。

### 再開・中断シナリオ / Scenarios & Lifecycle

1. **クロール中断の発生**:
   - `nvd_cve` や `iacr` などの大規模クローラーが実行中に SIGTERM、例外、またはプロセス再起動により中断される。
2. **フロンティアとBloomフィルタの保護**:
   - 中断時に `outputs/spider/checkpoints/<spider_name>.state` に未巡回優先度キューおよび既巡回 Bloom フィルタのバイナリ状態がアトミックに書き出される。
3. **デーモン/クライアントによる自動再開**:
   - 次回実行時、未完了チェックポイントが存在する場合に `--resume`（`resume_from_state=True`）が自動適用され、既訪問 URL をスキップして未巡回 URL から再開。
4. **正常完了時の安全破棄**:
   - 全キューの巡回が完了（未巡回URLなし）した時点でチェックポイントファイルが安全に自動削除（アンリンク）され、クリーンな初期状態に復帰する。

### 対象環境 / Environment

- OS / Env: Linux x86_64 / Antigravity Python Core
- Target Files:
  - [src/core/structures/bloom_filter.py](../../src/core/structures/bloom_filter.py)
  - [src/spider/distributed/state_storage.py](../../src/spider/distributed/state_storage.py)
  - [src/spider/runner.py](../../src/spider/runner.py)
  - [src/spider/daemon/worker.py](../../src/spider/daemon/worker.py)
  - [src/spider/daemon/client.py](../../src/spider/daemon/client.py)
  - [src/workflow/operators/spider_operator.py](../../src/workflow/operators/spider_operator.py)
  - [src/web/gateway/handlers.py](../../src/web/gateway/handlers.py)

---

## 2. 影響範囲と関連ファイル / Scope and Affected Files

- [x] [src/core/structures/bloom_filter.py](../../src/core/structures/bloom_filter.py) (`BloomFilter.to_dict/from_dict`, `ScalableBloomFilter.to_dict/from_dict` 実装による完全状態復元のサポート)
- [x] [src/spider/distributed/state_storage.py](../../src/spider/distributed/state_storage.py) (`StateStorage.save_state`, `restore_state` の BloomFilter 連動、`has_checkpoint`, `clear_checkpoint`, `get_default_checkpoint_path` 等の管理メソッド追加)
- [x] [src/spider/runner.py](../../src/spider/runner.py) (`run_spider` におけるデフォルトチェックポイントパス解決、`auto_checkpoint`/`auto_resume` 引数、例外/中断時の確実な状態保存、正常完了時のチェックポイント自動削除)
- [x] [src/spider/daemon/worker.py](../../src/spider/daemon/worker.py) (`_execute_crawl` での `state_file` および `resume_from_state` / `auto_resume` パラメータ連携)
- [x] [src/spider/daemon/client.py](../../src/spider/daemon/client.py) (`_execute_local_async` での `state_file` および `resume_from_state` / `auto_resume` 透過連携)
- [x] [src/workflow/operators/spider_operator.py](../../src/workflow/operators/spider_operator.py) (`_merge_params` での `state_file`, `resume_from_state`, `auto_resume` 連携)
- [x] [src/web/gateway/handlers.py](../../src/web/gateway/handlers.py) (`handle_spider_trigger` での `resume` オプション対応および `CrawlJob.params` への伝搬)
- [x] [tests/spider/test_spider_distributed_and_runner.py](../../tests/spider/test_spider_distributed_and_runner.py) (Bloom Filter を含むフロンティア完全保存・再開テスト)
- [x] [tests/spider/test_spider_daemon.py](../../tests/spider/test_spider_daemon.py) (Worker / Client 経由の中断・再開ライフサイクルテスト)
- [x] [tests/spider/test_spider_core.py](../../tests/spider/test_spider_core.py) (`ScalableBloomFilter` の辞書シリアライズ/デシリアライズテスト)
- [x] [docs/issues/README.md](README.md) (Issue 台帳の進捗管理)

---

## 3. ガバナンス・専門エージェント多角的レビュー / Multi-Perspective Review

### Project Manager (PM)
- **優先度判断**: Medium（重要基盤改善）。長時間のバックフィルや定常スパイダーが外部タイムアウトやレート制限で中断された場合、最初から全取得をやり直すことによるリソース消費と外部 API への過負荷を撲滅する。
- **目標**: スパイダー低層（StateStorage）から上位層（Daemon, Workflow Operator, Web API）まで一気通貫でフロンティア保存・自動再開が透過的に機能するアーキテクチャを確立する。

### Systems Architect
- **データフロー一貫性**: 状態永続化を単一のモジュール `StateStorage` に集約し、`Engine` → `Scheduler` → `StateStorage` → `Runner` → `DaemonWorker` / `Client` → `SpiderTaskOperator` へのインターフェース規約を統一する。
- **冪等性・回復性**: 中断時は必ずアトミック書き出し（`.tmp` + `os.replace`）を行い、正常終了時にはチェックポイントを完全パージすることで、中途半端な破損状態ファイルによる次回起動異常を防止する。

### Software Development (SWD)
- **ゼロ外部依存 & 高速シリアライズ**: `BloomFilter` の `bit_array` を 16 進表現（`hex()` / `fromhex()`）で JSON 辞書化し、C 拡張やサードパーティライブラリなしで完全復元可能とする。
- **例外安全設計**: `run_spider` において `try ... finally` ブロックを活用し、未処理リクエスト（`scheduler.has_pending_requests()`）が残っている場合は確実に保存し、完了時は削除する。

### Information Security Specialist
- **CWE-400 (リソース消費) 防止**: Bloom Filter の完全復元により、中断再開時の重複リクエストを 0 件に抑止し、外部ソース（NVD, arXiv, IACR）からの IP BAN やレート制限ブロックを回避。
- **CWE-22 (パストラバーサル) 防御**: `state_file` パスに外部入力が直接使われないよう、既定ディレクトリ（`outputs/spider/checkpoints/`）配下の安全なサニタイズ名で固定解決する。

### Network Specialist
- **Politeness Cooldown 保持**: 再開時にドメイン別待機ディレイ（`Scheduler.default_delay`）が破綻しないよう、フロンティア再開直後のバーストアクセスを抑制する。

### Database / Data Infrastructure Specialist
- **台帳整合性**: チェックポイントのライフサイクル（保存・再開・破棄）と `spider_execution.vdb`（ジョブ実行履歴台帳）のステータス遷移（running, completed, failed）が完全に連動することを担保する。

### IT Service Manager
- **運用性向上**: デーモン再起動時や手動トリガー時に、デフォルトでチェックポイントからの自動再開（`auto_resume=True`）が働き、オペレーター介入なしで自己修復・継続実行できる運用モデルを実現する。

### Application Specialist (APS)
- **Web コンソール連携**: Web Gateway の `/api/spiders/trigger` において `resume` パラメータを受け付け、UI からの再実行時にも中断フロンティアをシームレスに再開可能とする。

### Software Quality Assurance Specialist (QA)
- **品質ゲート完全準拠**: Xenon CC <= 3 (Rank A)、Mypy Strict (型エラー 0 件)、およびユニット/統合テスト 100% PASS を保証する。

---

## 4. 脅威分析とセキュリティ要件 (Threat Model & Security Requirements)

1. **脅威カテゴリ**:
   - **CWE-400 (Uncontrolled Resource Consumption)**: 再開時に訪問済み状態が欠落すると、外部データソース（arXiv, NVD, IACR）へ数千〜数万件の重複リクエストを再送し、レート制限（429 Too Many Requests）や IP BAN を引き起こす。
   - **CWE-22 (Improper Limitation of a Pathname to a Restricted Directory)**: 外部パラメータ `state_file` にディレクトリトラバーサル文字列（例: `../../etc/passwd`）が渡された場合の任意ファイル上書きリスク。
   - **CWE-362 (Race Condition / Inconsistent State File)**: 保存処理中のプロセス中断により破損した JSON が残るリスク。
2. **セキュリティ要件**:
   - `ScalableBloomFilter` のビット配列を完全保存・復元し、重複リクエストを 0 件に抑止すること。
   - `state_file` は許可されたディレクトリ（`outputs/spider/checkpoints/`）配下のファイル名（サニタイズされた `spider_name`）をデフォルトとし、相対・絶対パスの正規化検証を行うこと。
   - 一時ファイル（`.tmp`）への安全な書き出しと `os.replace` によるアトミック更新を徹底すること。

---

## 5. 根本原因分析 (RCA) / Root Cause Analysis

1. **上位オーケストレーション層でのパラメータ脱落**:
   - `src/spider/runner.py` は `state_file` と `resume_from_state` を受け取る機能を保持しているが、`SpiderDaemonWorker._execute_crawl`、`SpiderDaemonClient._execute_local_async`、`SpiderTaskOperator._merge_params` のいずれにもこれらの引数が渡されておらず、上位層から利用不可能になっていた。
2. **StateStorage における Bloom Filter シリアライズの欠落**:
   - 従来の `StateStorage.save_state` は `bloom_count`（件数数値）のみを保存し、実際の BloomFilter ビット配列を保存していなかった。
   - そのため再開時に `scheduler.bloom` が空となり、`start_urls` や既にスクレイプ済みの URL が再登録され、重複クロールを引き起こす重大な欠陥が存在していた。
3. **ライフサイクルと連動した例外安全な状態保存・破棄の欠落**:
   - `run_spider` 内の `StateStorage.save_state` は `engine.crawl()` の正常終了後にのみ配置されており、例外やキャンセル発生時に実行されなかった。
   - また、すべての巡回が完了した際にも状態ファイルが残り続けるため、次回実行時に古い空状態を読み込んでしまう設計上の不備があった。

---

## 6. 暫定対処と恒久対策 / Workaround & Permanent Fix

* **暫定対処 (Workaround)**: CLI から `python3 -m spider.runner --spider nvd_cve --state-file outputs/spider/checkpoints/nvd_cve.state --resume` を直接手動指定して実行。
* **恒久対策 (Permanent Fix)**:
  1. `ScalableBloomFilter` および `BloomFilter` に `to_dict()` / `from_dict()` を追加し、BloomFilter のビット配列を可逆的に JSON 永続化可能にする。
  2. `StateStorage` にて未訪問リクエストキューと Bloom Filter の双方を完全シリアライズ。チェックポイント存在確認・削除ヘルパー（`has_checkpoint`, `clear_checkpoint`, `get_default_checkpoint_path`）を整備。
  3. `run_spider` において `try ... finally` を活用し、中断・例外時にチェックポイントを確実に保存、全巡回完了時には自動的にチェックポイントをクリーンアップ。
  4. `SpiderDaemonWorker`, `SpiderDaemonClient`, `SpiderTaskOperator`, `handle_spider_trigger` の全層へ `state_file` / `auto_resume` を透過的に連動。

---

## 7. 実装方針 / Implementation Plan

Target Branch: `feat/397-spider-frontier-state-persistence-and-daemon-resume`

### ステップ 1: BloomFilter / ScalableBloomFilter の状態シリアライズ実装
- [src/core/structures/bloom_filter.py](../../src/core/structures/bloom_filter.py):
  - `BloomFilter.to_dict()`: `num_bits`, `num_hashes`, `capacity`, `error_rate`, `count`, `data_hex` (バイナリの 16 進表現) を出力。
  - `BloomFilter.from_dict(cls, data)`: 辞書からビット配列を復元して `BloomFilter` を生成。
  - `ScalableBloomFilter.to_dict()`: `initial_capacity`, `error_rate`, `scale_factor`, `filters` (各サブフィルタ辞書リスト) を出力。
  - `ScalableBloomFilter.from_dict(cls, data)`: 全階層サブフィルタを含めて完全復元。
  - Xenon CC <= 3 を厳格に順守。

### ステップ 2: StateStorage の完全永続化とチェックポイント管理 API
- [src/spider/distributed/state_storage.py](../../src/spider/distributed/state_storage.py):
  - `save_state(scheduler, filepath)`: `pending_requests` に加え `bloom_state: scheduler.bloom.to_dict()` を JSON 出力。
  - `restore_state(scheduler, filepath)`: `pending_requests` を優先度キューに復元し、`bloom_state` が存在する場合は `scheduler.bloom = ScalableBloomFilter.from_dict(...)` を復元。
  - `get_default_checkpoint_path(spider_name: str, base_dir: str = "outputs/spider/checkpoints") -> str`: パス解決（安全なファイル名サニタイズ）。
  - `has_checkpoint(spider_name: str, base_dir: str = "outputs/spider/checkpoints") -> bool`: 未完了チェックポイントの存在検査。
  - `clear_checkpoint(filepath_or_name: str, base_dir: str = "outputs/spider/checkpoints") -> bool`: 状態ファイルの安全な削除。

### ステップ 3: run_spider のライフサイクル連動型チェックポイント管理
- [src/spider/runner.py](../../src/spider/runner.py):
  - 引数 `auto_checkpoint: bool = True`, `auto_resume: bool = True` を新設。
  - `state_file` 未指定時でもデフォルトチェックポイント（`outputs/spider/checkpoints/<spider_name>.state`）を自動適用。
  - 既存チェックポイントが存在しかつ `auto_resume=True` または `resume_from_state=True` の場合、自動でフロンティアと BloomFilter を復元。
  - `try ... finally` ブロックによる例外安全なハンドリング:
    - 巡回中断時または `scheduler.has_pending_requests()` の場合: `StateStorage.save_state(scheduler, state_file)` を実行。
    - 正常完了かつ未処理リクエスト 0 件の場合: `StateStorage.clear_checkpoint(state_file)` によりチェックポイントを自動削除。

### ステップ 4: Daemon Worker / Client への透過連携
- [src/spider/daemon/worker.py](../../src/spider/daemon/worker.py):
  - `_execute_crawl(job)`: `job.params` から `state_file`, `resume_from_state`, `auto_resume` を取り出して `run_spider` に引数伝搬。
- [src/spider/daemon/client.py](../../src/spider/daemon/client.py):
  - `_execute_local_async(job)`: 同様に `run_spider` へパラメータ伝搬。

### ステップ 5: Workflow Task Operator & Web API 連携
- [src/workflow/operators/spider_operator.py](../../src/workflow/operators/spider_operator.py):
  - `_merge_params`: `state_file`, `resume_from_state`, `auto_resume` をサポート。
- [src/web/gateway/handlers.py](../../src/web/gateway/handlers.py):
  - `handle_spider_trigger`: リクエストボディから `resume: bool` 等を取り出し、`CrawlJob.params` に格納。

### ステップ 6: テスト作成と品質検証
- [tests/spider/test_spider_core.py](../../tests/spider/test_spider_core.py): `ScalableBloomFilter.to_dict/from_dict` の往復テスト。
- [tests/spider/test_spider_distributed_and_runner.py](../../tests/spider/test_spider_distributed_and_runner.py): 中断（疑似停止）後の Bloom Filter 保持・未巡回キュー再開・完了時削除のテスト。
- [tests/spider/test_spider_daemon.py](../../tests/spider/test_spider_daemon.py): Worker および Client を介したチェックポイント自動再開テスト。
- `make check_format`
- `make static_analysis` (Xenon A, Mypy Strict)
- `make test`

---

## 8. 完了条件 / Success Criteria (DoD)

- [x] `ScalableBloomFilter` および `BloomFilter` がビット配列の欠落なく辞書経由で可逆的にシリアライズ／デシリアライズできること。
- [x] クロール中断時に未巡回 URL キューおよび既巡回 Bloom Filter が `outputs/spider/checkpoints/<spider_name>.state` に安全に保存されること。
- [x] チェックポイントが存在する状態で次回スパイダーを実行した際、既巡回 URL を再取得することなく未巡回リクエストから自動再開できること。
- [x] 全ての未巡回リクエストを処理し正常終了した際には、チェックポイントファイルが安全に自動削除されること。
- [x] `SpiderDaemonWorker`、`SpiderDaemonClient`、`SpiderTaskOperator`、および Gateway API 経由でチェックポイント再開が透過的に機能すること。
- [x] 全ての新規・変更関数の循環的複雑度が CC <= 3 (Xenon Rank A) かつ Mypy Strict に適合すること。
- [x] `tests/spider/` を含む全テスト（`make test`）および静的解析（`make static_analysis`）が 100% PASS すること。
