---
ID: 395
種別: Bug
優先度: High
ステータス: Closed
---

# [BUG/SEC] スパイダー実行の排他制御（Mutex）および二重起動防止の実装 (ID: 395)

## 1. 概要 / Summary
スパイダー手動トリガー API (`POST /api/spiders/trigger`) および Web コンソール UI (`site/app.js`, `site/index.html`) において、スパイダーが既に `RUNNING` 状態であっても排他制御や二重実行チェックが行われず、複数のスパイダースレッドが同時に並行実行されてしまう不具合を解消する。
API 側に対象スパイダー（または排他グループ）の実行中チェックおよびデータベース行による排他ロック判定を導入して `409 Conflict` を返却可能とし、Web UI 側でも実行中ステータスに応じたボタン非活性化とリアルタイムフィードバックを確立する。

### 再現手順 / Steps to Reproduce
1. Enterprise Cloud Console (`site/index.html`) の「Spider 実行管理」タブを開く。
2. 「今すぐ実行 (Manual Trigger)」ボタンを押下する。
3. 3 秒後にボタンが再活性化されるため、クロール処理（例: 数十秒〜数分以上）の最中に再度ボタンを押下する、または別スパイダーの実行を押下する。
4. `outputs/database/spider_execution.vdb` および「Spider 実行履歴」テーブルに、同一または複数のスパイダーの `status = 'RUNNING'` レコードが同時に複数生成され、バックグラウンドスレッドが多重起動する。

### 再現環境 / Environment
- OS / Env: Linux x86_64 / Web Gateway WSGI Server
- File: `src/web/gateway/handlers.py`, `src/spider/daemon/storage.py`, `site/app.js`, `site/index.html`

---

## 2. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [src/spider/daemon/storage.py](../../src/spider/daemon/storage.py) (`is_spider_running`, `get_running_job`, `has_running_job` の実装)
- [x] [src/web/gateway/handlers.py](../../src/web/gateway/handlers.py) (`handle_spider_trigger` 排他判定、409 Conflict レスポンス)
- [x] [site/app.js](../../site/app.js) (`loadSpiderStatus` におけるボタン状態連動、`triggerSpider` の多重防止と 409 ハンドリング)
- [x] [site/app-min.js](../../site/app-min.js) (Google Closure Compiler 再コンパイル)
- [x] [site/dashboard-min.js](../../site/dashboard-min.js) (Google Closure Compiler 再コンパイル)
- [x] [tests/web/test_web_server.py](../../tests/web/test_web_server.py) (スパイダートリガー 409 Conflict 排他制御テストの追加)
- [x] [tests/spider/test_spider_daemon.py](../../tests/spider/test_spider_daemon.py) (ストレージ排他判定テストの追加)

---

## 3. 根本原因分析 (RCA) / Root Cause Analysis
1. **API ハンドラの無条件スレッド生成と排他制御欠落**:
   - `handle_spider_trigger` では、リクエストを受けると毎回新規の `job_id`（`manual_{spider_name}_{timestamp}`）を発行し、DB レコードを作成した直後に `threading.Thread(target=_run_spider_job_bg, ...).start()` を呼び出している。
   - 該当スパイダーが現在実行中であるかの事前バリデーションや、プロセス内・DB レベルの排他ロック（Mutex）が実装されていなかった。
2. **同時リクエストにおける Race Condition**:
   - 複数のクライアントまたはダブルクリックによりミリ秒単位で同時にリクエストが到達した場合、DB クエリのみでは同一タイミングで実行中なしと判定され、重複起動する脆弱性（TOCTOU: Time-of-Check to Time-of-Use）が存在する。
3. **UI 側のタイマーによる強制再活性化**:
   - `site/app.js` の `triggerSpider` は、ボタン押下からわずか 3 秒後に `setTimeout` で `triggerBtn.disabled = false` に復帰させていた。
   - 実際のスパイダークロール処理（75秒〜数千秒）の完了を待たずにボタンが押下可能となるため、ユーザーの誤操作や連続クリックによる重複実行を誘発していた。

---

## 4. セキュリティ・スレッドモデル分析 (Threat Model)
- **脅威カテゴリ**: CWE-362 (Race Condition / Concurrent Execution using Shared Resource), CWE-400 (Uncontrolled Resource Consumption)
- **影響**: 同一データソース（arXiv API、NVD API、CWE サイト）への過剰な並行リクエストによる HTTP 429 Rate Limit や IP BAN の発生、ローカル CPU / メモリ枯渇、および DB トランザクション競合。
- **緩和策**:
  - DB 上の `RUNNING` 状態検査（データベース行の有無）による排他ガード。
  - 二重実行試行に対しては明確に `409 Conflict` ステータスコードと既存 `job_id` を返却。

---

## 5. 暫定対処と恒久対策 / Workaround & Permanent Fix
* **暫定対処 (Workaround)**: ユーザー側でクロール完了（履歴テーブルのステータス遷移）を確認するまで連続クリックを行わないよう運用徹底。
* **恒久対策 (Permanent Fix)**:
  1. `SpiderExecutionStorage` に `get_running_job(spider_name: str, max_age_seconds: float = 7200.0) -> Optional[Dict[str, Any]]` および `has_running_job(spider_name: str) -> bool` メソッドを実装。
  2. `src/web/gateway/handlers.py` の `handle_spider_trigger` において対象スパイダーが既に `RUNNING` 状態である場合は HTTP 409 Conflict (`{"status": "conflict", "error": "Spider '<name>' is already running (Job: active_job_id)"}`) を返却して新規スレッド起動を阻止。
  3. `site/app.js` において、スパイダーステータスが `RUNNING` である間はトリガーボタンを非活性化 (`disabled = true`) し、409 応答時にも適切な警告トーストを表示。

---

## 6. 実装方針 / Implementation Plan
Target Branch: `fix/395-spider-execution-concurrency-control-and-mutex`

1. **Storage 層への実行状態判定メソッド追加**:
   - `src/spider/daemon/storage.py` に `get_running_job`, `has_running_job`, `is_spider_running` を実装。
   - `SELECT {self.ALL_COLUMNS_SQL} FROM spider_execution_logs WHERE spider_name = ? AND status = 'RUNNING'` を PyDB 互換の構文で実行。
   - Xenon 循環的複雑度 A (CC <= 3) を厳格に遵守。

2. **Gateway API ハンドラの排他制御と 409 Conflict レスポンス**:
   - `handle_spider_trigger` 内で `storage.get_running_job(target_spider)` を呼び出し。
   - 実行中ジョブが存在する場合は即座に `status="409 Conflict"` レスポンスを返却。
   - 未実行時のみ `storage.record_start(job)` を実行し、バックグラウンドスレッドを開始。

3. **フロントエンド UI の状態連動とエラーハンドリング**:
   - `site/app.js` の `loadSpiderStatus()`:
     - 各スパイダーの `info.status === 'RUNNING'` の場合、該当カードのトリガーボタン (`btn-trigger-spider`) を `setAttribute('disabled', 'true')`, `textContent = '⏳ 実行中...'` に設定。
     - 非 `RUNNING` の場合、`removeAttribute('disabled')`, `textContent = '⚡ 今すぐ実行 (Manual Trigger)'` に復元。
   - `triggerSpider()`:
     - 409 レスポンス受信時に warning トーストを表示し、ボタンを無効状態のまま維持。
     - 3秒後の無条件復帰タイマーを撤去し、DB 実ステータス主導の制御に切り替え。

4. **テストの追加とバンドル再コンパイル**:
   - `tests/web/test_web_server.py` に `test_spider_trigger_conflict_409` を追加。
   - `tests/spider/test_spider_daemon.py` に `TestSpiderExecutionStorageLock` を追加。
   - `python3 scripts/compile_frontend.py` で Closure Compiler ビルドを実行（app-min.js, dashboard-min.js）。

---

## 7. 完了条件 / Success Criteria (DoD)
- [x] 既に `RUNNING` 状態のスパイダーに対して `POST /api/spiders/trigger` を送信した場合、HTTP 409 Conflict が返却され、追加スレッドが生成されないこと。
- [x] スパイダー実行中に Web UI の「今すぐ実行」ボタンが非活性化され、クロール完了まで再クリックが防止されること。
- [x] `tests/web/` (185件) および `tests/spider/` (92件) のテストが全件 PASS すること。
- [x] Google Closure Compiler によるフロントエンドビルドがエラー 0 件で成功すること。
- [x] `make static_analysis` (Xenon A, Mypy strict) をパスすること。
