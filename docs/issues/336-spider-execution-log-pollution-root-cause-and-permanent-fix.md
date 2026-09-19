---
ID: 336
種別: Bug
優先度: High
ステータス: Open (New)
---

# [BUG] スパイダー実行ログ台帳における「6時間ごと定期実行」ではなく数分おきに実行記録が蓄積される事象の根本原因調査と恒久対策 (ID: 336)

## 1. 概要 / Summary

Webコンソール (スパイダー監視 UI) において arXiv Spider の実行間隔として「6時間ごと (1日4回)」と表示されているにもかかわらず、`outputs/database/spider_execution.vdb` の実行ログ台帳には数分おきにレコードが生成されていた。

調査の結果、**本番スケジューラー自体の設定は正常 (6時間 = 21,600秒)** であり、ログ台帳の汚染は **開発中の品質検証コマンド (`make check` / `pytest`) によるテスト副作用** であることが判明した。

テストが本番 DB を直接参照し、かつジョブ ID 不一致により終了ステータスが更新されず RUNNING のまま残留するという二重の不具合が存在していた。

### 再現手順 / Steps to Reproduce

1. `make check` または `pytest tests/` を実行する。
2. `outputs/database/spider_execution.vdb` を確認する。
3. 実行間隔が数分おきの RUNNING ステータスのレコードが追加されていることを確認する。

### 再現環境 / Environment

- OS / Env: Linux (Docker), Python 3.12
- Files: `tests/workflow/test_spider_operator.py`, `tests/spider/test_spider_db_persistence.py`
- DB: `outputs/database/spider_execution.vdb`

---

## 2. 影響範囲と関連ファイル / Scope and Affected Files

- [x] [`tests/workflow/test_spider_operator.py`](../../tests/workflow/test_spider_operator.py) (テスト DB 隔離未実施 → 本番 DB 汚染)
- [x] [`tests/spider/test_spider_db_persistence.py`](../../tests/spider/test_spider_db_persistence.py) (ジョブID 不一致 → RUNNING 残留)
- [x] [`tests/spider/test_spider_daemon.py`](../../tests/spider/test_spider_daemon.py) (DB 隔離不足)
- [x] [`tests/conftest.py`](../../tests/conftest.py) (グローバル隔離フィクスチャ追加が必要)
- [x] [`src/spider/daemon/storage.py`](../../src/spider/daemon/storage.py) (環境変数 `SPIDER_EXECUTION_DB_PATH` 対応)
- [x] [`src/workflow/operators/spider_operator.py`](../../src/workflow/operators/spider_operator.py) (DB パス注入対応)
- [x] [`src/workflow/service.py`](../../src/workflow/service.py) (DB パス注入対応)
- [x] [`src/workflow/scheduler.py`](../../src/workflow/scheduler.py) (DB パス注入対応)
- [x] [`outputs/database/spider_execution.vdb`](../../outputs/database/spider_execution.vdb) (汚染レコードのクリーンアップ)

---

## 3. 根本原因分析 (RCA) / Root Cause Analysis

### 原因 ① テストコードによる本番 DB 直接書き込み

以下のテストケースで `SpiderExecutionStorage` の保存先が一時ディレクトリに隔離されず、デフォルトの `outputs/database/spider_execution.vdb` を参照していた：

| テストファイル | 問題のテストケース | 汚染内容 |
| --- | --- | --- |
| `tests/workflow/test_spider_operator.py` | `test_direct_operator_execution` | `{"max_requests": 5}` パラメータで RUNNING 開始レコードを本番 DB に追加 |
| `tests/workflow/test_spider_operator.py` | `test_dag_workflow_integration` | `{"max_requests": 10}` パラメータで同様に本番 DB へ書き込み |
| `tests/workflow/test_spider_operator.py` | `test_workflow_scheduler_with_spider_task` | CWE スケジューラー起動がそのまま本番 DB へ書き込み |
| `tests/spider/test_spider_db_persistence.py` | `TestWorkflowService.test_task_scheduling_logic` | `WorkflowLifecycleHook()` を隔離なしで初期化し、arXiv/CWE/KEV-CVE の 3 タスクが即時発火して本番 DB へ記録 |

**エビデンス**: ログ台帳に現れるタイムスタンプ (UTC) と直近コミット前の `make check` 実行時刻を照合したところ完全一致した。

```
01:15〜01:17 UTC  ← Issue 329 テスト実行時
01:28〜01:40 UTC  ← Issue 330, 331, 333 テスト実行時
02:02〜02:12 UTC  ← Issue 334 テスト実行時
```

### 原因 ② ジョブ ID 不一致による RUNNING 残留

`tests/spider/test_spider_db_persistence.py` 内でモックの戻り値のジョブ ID が固定値 `"test"` に設定されていた：

```python
# テスト内モック（問題のコード）
mock_submit.return_value = CrawlResult(
    job_id="test",      # ← 固定値
    spider_name="arxiv",
    success=True,
)
```

一方、`SpiderTaskOperator.execute()` では開始時に動的なジョブ ID を生成して DB に RUNNING として登録する：

```python
job_id = f"scheduled_{self.spider_name}_{int(time.time())}"  # ← 動的生成
self.storage.record_start(job)          # scheduled_arxiv_<timestamp> で RUNNING 登録
result = self.client.submit_job(...)    # モックが "test" を返却
self.storage.record_finish(result)      # "test" で更新 → 該当レコードが存在せず放置
```

これにより `scheduled_arxiv_<timestamp>` レコードが永遠に RUNNING のまま残留した。

---

## 4. 暫定対処と恒久対策 / Workaround & Permanent Fix

- **暫定対処 (Workaround)**: `outputs/database/spider_execution.vdb` 内の汚染レコードを `DELETE FROM spider_execution_logs` で削除し、台帳をクリーンな状態に復元する（Issue 335 にて実施済み）。
- **恒久対策 (Permanent Fix)**:
  1. 全テストが一時ディレクトリを参照するように隔離フィクスチャを整備する。
  2. モックの `job_id` を `SpiderTaskOperator` の動的生成値と一致させる、または `record_finish` が未知の `job_id` を受け取った際に警告・スキップする防御コードを追加する。

---

## 5. 実装方針 / Implementation Plan

Target Branch: `fix/336-spider-execution-log-pollution-root-cause`

> **注記**: Issue 335 にてテスト DB 隔離の実装・クリーンアップは完了済み。本 Issue は事象の記録・トレーサビリティ維持を主目的とし、追加の残存リスクに対処する。

1. **`SpiderExecutionStorage.record_finish()` 防御強化**:
   - 更新対象の `job_id` が存在しない場合、`WARNING` ログを出力して静かにスキップする防御パスを追加する（現状は silently ignored）。
2. **テスト網羅性向上**:
   - `test_record_finish_with_unknown_job_id` テストを追加し、未知 `job_id` での `record_finish()` 呼び出しが例外なく完了することを保証する。
3. **`tests/conftest.py` の完全性確認**:
   - 全テストモジュールがグローバルフィクスチャで確実に隔離されていることを `make verify_quality` で確認する。

---

## 6. 完了条件 / Success Criteria (DoD)

- [ ] `make check` (122件以上のテスト) 完全 PASS。
- [ ] `make static_analysis` エラー 0 件。
- [ ] `make py_compile` エラー 0 件。
- [ ] `pytest tests/` 実行後、`outputs/database/spider_execution.vdb` に新規テスト由来レコードが 0 件であること。
- [ ] `SpiderExecutionStorage.record_finish()` に未知 `job_id` が渡された場合、`WARNING` ログが出力されて例外が発生しないこと。
- [ ] `test_record_finish_with_unknown_job_id` テスト PASS。
