---
ID: 336
種別: Bug
優先度: High
ステータス: Open (In Progress)
依存: 335 (完了済み)
---

# [BUG] スパイダー実行ログ台帳における「6時間ごと定期実行」ではなく数分おきに実行記録が蓄積される事象の根本原因調査と恒久対策 (ID: 336)

## 1. 概要 / Summary

Webコンソール (スパイダー監視 UI) において arXiv Spider の実行間隔として「6時間ごと (1日4回)」と表示されているにもかかわらず、`outputs/database/spider_execution.vdb` の実行ログ台帳には数分おきにレコードが生成されていた。

調査の結果、**本番スケジューラー自体の設定は正常 (6時間 = 21,600秒)** であり、ログ台帳の汚染は **開発中の品質検証コマンド (`make check` / `pytest`) によるテスト副作用** であることが判明した。

テストが本番 DB を直接参照し、かつジョブ ID 不一致により終了ステータスが更新されず RUNNING のまま残留するという二重の不具合が存在していた。

**Issue 335 にて以下は完了済み**：
- テスト DB 隔離 (`SPIDER_EXECUTION_DB_PATH` 環境変数 + `tests/conftest.py` グローバルフィクスチャ)
- 本番 DB の汚染レコードクリーンアップ

**本 Issue で対処する残存リスク**：
- `SpiderExecutionStorage.record_finish()` が存在しない `job_id` で呼ばれた場合にサイレント失敗する（警告ログなし）
- 当該防御パスのユニットテストが存在しない

### 再現手順 / Steps to Reproduce

> ⚠️ Issue 335 の修正後は本番 DB は汚染されなくなっている。以下は修正前の再現手順。

1. `git stash` で Issue 335 の修正を一時退避。
2. `make check` または `pytest tests/` を実行する。
3. `outputs/database/spider_execution.vdb` を確認する。
4. 実行間隔が数分おきの RUNNING ステータスのレコードが追加されていることを確認する。

### 再現環境 / Environment

- OS / Env: Linux (Docker), Python 3.12
- Files: `tests/workflow/test_spider_operator.py`, `tests/spider/test_spider_db_persistence.py`
- DB: `outputs/database/spider_execution.vdb`

---

## 2. 影響範囲と関連ファイル / Scope and Affected Files

### Issue 335 にて修正済み ✅

- [x] [`tests/workflow/test_spider_operator.py`](../../tests/workflow/test_spider_operator.py) (テスト DB 隔離実装済み)
- [x] [`tests/spider/test_spider_db_persistence.py`](../../tests/spider/test_spider_db_persistence.py) (ジョブID 修正・隔離実装済み)
- [x] [`tests/spider/test_spider_daemon.py`](../../tests/spider/test_spider_daemon.py) (DB 隔離実装済み)
- [x] [`tests/conftest.py`](../../tests/conftest.py) (グローバル隔離フィクスチャ実装済み)
- [x] [`src/spider/daemon/storage.py`](../../src/spider/daemon/storage.py) (環境変数 `SPIDER_EXECUTION_DB_PATH` 対応済み)
- [x] [`src/workflow/operators/spider_operator.py`](../../src/workflow/operators/spider_operator.py) (DB パス注入対応済み)
- [x] [`src/workflow/service.py`](../../src/workflow/service.py) (DB パス注入対応済み)
- [x] [`src/workflow/scheduler.py`](../../src/workflow/scheduler.py) (DB パス注入対応済み)
- [x] [`outputs/database/spider_execution.vdb`](../../outputs/database/spider_execution.vdb) (汚染レコードクリーンアップ済み)

### 本 Issue (336) で対応するファイル

- [ ] [`src/spider/daemon/storage.py`](../../src/spider/daemon/storage.py) — `record_finish()` に `rowcount` チェックと `WARNING` ログ追加
- [ ] [`tests/spider/test_spider_db_persistence.py`](../../tests/spider/test_spider_db_persistence.py) — `test_record_finish_with_unknown_job_id` テスト追加

---

## 3. 根本原因分析 (RCA) / Root Cause Analysis

### 原因 ① テストコードによる本番 DB 直接書き込み（Issue 335 で修正済み）

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

### 原因 ② ジョブ ID 不一致による RUNNING 残留（一部残存）

`tests/spider/test_spider_db_persistence.py` 内でモックの戻り値のジョブ ID が固定値 `"test"` に設定されていた（Issue 335 で修正済み）。

根本的な問題として **`SpiderExecutionStorage.record_finish()` が UPDATE 結果の影響件数をチェックしない** ため、存在しない `job_id` でも例外もログも出力せずサイレントに成功する：

```python
# src/spider/daemon/storage.py L98-L125 (現状の問題コード)
def record_finish(self, result: CrawlResult) -> None:
    ...
    with self._get_connection() as conn:
        cur = conn.cursor()
        cur.execute("UPDATE spider_execution_logs SET ... WHERE job_id = ?", (...,))
        conn.commit()
        # ← cur.rowcount が 0 でも何もしない（サイレント失敗）
```

`database/ipc/driver.py` の `Cursor` クラスは `self.rowcount: int = -1` として定義されており（L90）、`execute()` 後に `_resolve_cursor_rowcount()` (L95) で更新される。これを利用して防御ログを追加できる。

---

## 4. 暫定対処と恒久対策 / Workaround & Permanent Fix

- **暫定対処 (Workaround)**: 完了済み（Issue 335）。`DELETE FROM spider_execution_logs` でクリーンアップ + テスト DB 隔離実装。
- **恒久対策 (Permanent Fix)**:
  1. `SpiderExecutionStorage.record_finish()` で `cur.rowcount == 0` の場合に `WARNING` ログを出力する防御パスを追加する。
  2. `test_record_finish_with_unknown_job_id` テストを追加し、未知 `job_id` での `record_finish()` が例外なく完了し、かつ WARNING ログが出力されることを保証する。

---

## 5. 実装方針 / Implementation Plan

Target Branch: `fix/336-spider-execution-log-pollution-root-cause`

> **注記**: `feat/199-implement-multi-format-graph-export-ttl-jsonld-stix` ブランチの main マージ後、本ブランチを作成すること。

### ステップ 1: `src/spider/daemon/storage.py` — `record_finish()` 防御強化

**対象**: [`src/spider/daemon/storage.py`](../../src/spider/daemon/storage.py) L1-L16 (imports) + L98-L125 (`record_finish`)

**変更内容**:

1. ファイル先頭に `import logging` と `logger = logging.getLogger(__name__)` を追加する。
2. `record_finish()` メソッドで `conn.commit()` の後、`cur.rowcount` が `0` 以下の場合に `logger.warning(...)` を出力する。

変更後のコードイメージ：

```python
# 追加: imports ブロック末尾
import logging

logger = logging.getLogger(__name__)

# record_finish() の変更箇所
def record_finish(self, result: CrawlResult) -> None:
    """Updates the execution log entry with final status and statistics.

    If no matching job_id is found in the log table (e.g. due to a mock
    job_id mismatch in tests or a restart), a WARNING is emitted and the
    method returns without raising an exception.
    """
    status = "SUCCESS" if result.success else "FAILED"
    stats_json = json.dumps(result.stats or {})
    with self._get_connection() as conn:
        cur = conn.cursor()
        cur.execute(
            """
            UPDATE spider_execution_logs
            SET status = ?,
                finished_at = ?,
                duration_seconds = ?,
                item_count = ?,
                http_status_counts = ?,
                error_message = ?
            WHERE job_id = ?
            """,
            (
                status,
                _utc_now_iso(),
                result.duration_seconds,
                result.item_count,
                stats_json,
                result.error,
                result.job_id,
            ),
        )
        conn.commit()
        # ↓ 追加: rowcount チェック
        if cur.rowcount <= 0:
            logger.warning(
                "[SpiderExecutionStorage] record_finish: job_id '%s' not found "
                "in spider_execution_logs. "
                "This may indicate a job_id mismatch (e.g. test mock vs. dynamic ID). "
                "Status '%s' was NOT persisted.",
                result.job_id,
                status,
            )
```

**考慮事項**:
- `rowcount` は `database/ipc/driver.py:Cursor._resolve_cursor_rowcount()` で `result.get("affected_rows", -1)` から取得される。UPDATE で 0 件ヒットの場合は `0` が返る。
- 例外は発生させない（既存の呼び出しコードが例外ハンドリングを行っていないため後方互換性を保つ）。

### ステップ 2: `tests/spider/test_spider_db_persistence.py` — 防御ログテスト追加

**対象**: [`tests/spider/test_spider_db_persistence.py`](../../tests/spider/test_spider_db_persistence.py) の `TestSpiderExecutionStorage` クラス末尾

**追加テスト**:

```python
def test_record_finish_with_unknown_job_id(self) -> None:
    """record_finish() with an unknown job_id must not raise an exception
    and must emit a WARNING log."""
    unknown_result = CrawlResult(
        job_id="nonexistent_job_id_xyz",
        spider_name="arxiv",
        success=True,
        item_count=0,
    )
    import logging
    with self.assertLogs("spider.daemon.storage", level="WARNING") as cm:
        # Must not raise
        self.storage.record_finish(unknown_result)
    # WARNING ログが出力されていること
    self.assertTrue(
        any("nonexistent_job_id_xyz" in line for line in cm.output),
        f"Expected WARNING with job_id in log output, got: {cm.output}",
    )
    # DB に新規レコードが作成されていないこと（UPDATE であり INSERT でないため）
    history = self.storage.list_history()
    self.assertEqual(len(history), 0)
```

**留意点**:
- `assertLogs` は Python 標準ライブラリに含まれており外部依存なし。
- `logger = logging.getLogger(__name__)` で `__name__` は `spider.daemon.storage` になる。

### ステップ 3: 品質ゲート確認

```bash
make format
make static_analysis   # xenon / flake8 / mypy すべて PASS
make check             # 全テスト PASS (122件以上)
# 追加確認: 本番 DB が汚染されていないこと
python3 -c "
from spider.daemon.storage import SpiderExecutionStorage
s = SpiderExecutionStorage()
print('records:', len(s.list_history()))
"
```

---

## 6. セキュリティ考慮事項 / Security Considerations

本 Issue の変更は入力値の検証やデータフローへの変更を伴わないため、新規の脅威ベクターは発生しない。

ただし以下の点を確認する：
- `logger.warning()` に渡す `result.job_id` および `status` は信頼できる内部生成値であるため、ログインジェクション攻撃のリスクはない。
- `%s` 形式のログフォーマット（遅延評価）を使用しているため、文字列連結によるパフォーマンス問題もない。

---

## 7. 完了条件 / Success Criteria (DoD)

- [ ] `make check` (122件以上のテスト) 完全 PASS。
- [ ] `make static_analysis` (xenon / flake8 / mypy) エラー 0 件。
- [ ] `make py_compile` エラー 0 件。
- [ ] `pytest tests/` 実行後、`outputs/database/spider_execution.vdb` に新規テスト由来レコードが 0 件であること。
- [ ] `SpiderExecutionStorage.record_finish()` に未知 `job_id` が渡された場合、`WARNING` ログが出力されて例外が発生しないこと。
- [ ] `test_record_finish_with_unknown_job_id` テスト PASS（`assertLogs` で WARNING を検証）。
- [ ] `src/spider/daemon/storage.py` が `import logging` / `logger = logging.getLogger(__name__)` を持つこと。

