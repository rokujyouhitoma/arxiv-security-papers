---
ID: 172
種別: Bug / Security
優先度: High
ステータス: Closed
---

# [BUG/SEC] Fix SSE Connection Saturation Blocking Web Workers and Eliminate Unused SSE in Dashboard (ID: 172)

## 1. 概要 / Summary
`http://localhost:8000/dashboard.html` や `index.html` 閲覧時、ブラウザおよびサーバーが応答しなくなり（ハング・ブロッキング状態）、curl や新規リクエストが一切通らなくなる障害が発生した。

### 再現手順 / Steps to Reproduce
1. Supervisor デフォルト起動（`python -m supervisor.cli start -D`：同期ワーカー 2 台 `worker_class="sync"`, `workers=2`）。
2. ブラウザで `http://localhost:8000/index.html` と `http://localhost:8000/dashboard.html` を複数タブで開く、あるいはリロードする。
3. `app.js` および `dashboard.html` 内の `EventSource('/api/stream/top?interval=1.0')` が同時に 2 つの常時接続を確立する。
4. 全ワーカー（`web_0`, `web_1`）が SSE ストリーム送信ループに占有され、利用可能なワーカー数が 0 になる。
5. 後続のすべての HTTP リクエスト（HTML, CSS, JS, API）がソケット backlog キューに入ったままタイムアウト・ブロックする。

### 再現環境 / Environment
- OS / Env: Linux x86_64 / Python 3.14.7
- Component: `src/supervisor/`, `src/web/`, `site/dashboard.html`, `site/app.js`

---

## 2. 脅威分析およびセキュリティ要件 (Threat Model & Security Requirements)
- **脅威分類**: CWE-400 (Uncontrolled Resource Consumption / DoS), Slowloris 風の接続枯渇攻撃
- **攻撃経路 / 脅威シナリオ**:
  - SSE エンドポイント (`/api/stream/top`) は最大 3600 秒間接続を維持する。
  - 同期ワーカー（`SyncWorker`）構成時、攻撃者または通常の複数クライアントが SSE 接続を 2 つ開くだけで、全ワーカープロセスが枯渇し、正当なユーザーの全リクエスト（検索、論文閲覧、API）が完全に拒否・サービス停止（DoS）となる。
- **緩和策 (Mitigations)**:
  1. 不要な常時接続の排除: Supervisor テレメトリを表示しない `dashboard.html` から SSE 接続を完全撤廃。
  2. マルチスレッド並行処理（`GthreadWorker`）の標準化: デフォルト構成を `worker_class="gthread"`, `threads=4` 以上とし、長寿命接続が存在しても他の HTTP リクエストをスレッドプールで並行処理可能にする。
  3. クライアント側の接続ライフサイクル厳格管理: `app.js` での `onerror` 即時 close、`pagehide`/`beforeunload`/`visibilitychange` 連動切断による不要コネクションの即時解放。
  4. ワーカーシャットダウン・切断検知時の即時脱出制御: `SyncWorker` およびストリーミングイテレータのクリーンアップ徹底。

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [x] `site/dashboard.html`: Supervisor タブ削除に伴い不要となった SSE 常時接続（`/api/stream/top`）および関連関数の完全撤廃
- [x] `src/supervisor/workers/sync_worker.py`: SSE ストリーミングループ内でのワーカー生存状態（`self.alive`）確認と即時イテレータクローズ
- [x] `src/supervisor/workers/gthread_worker.py`: プール設定からの動的 `threads` 引数受け入れ対応
- [x] `src/supervisor/arbiter.py`: ワーカー生成時に `WorkerSpec` の `threads` を `GthreadWorker` へ確実に伝播
- [x] `src/supervisor/config.py`: デフォルトワーカー設定の耐久性強化（`PoolConfig` のデフォルト `worker_class="gthread"`, `threads=4`）
- [x] `config/supervisor.json`: デフォルト構成ファイルの `web` プールを `worker_class="gthread"`, `threads=4` に更新
- [x] `config/supervisor.sample.json`: サンプル設定の `gthread` 化
- [x] `config/supervisor.sample.toml`: サンプル設定の `gthread` 化
- [x] `config/supervisor.sample.py`: サンプル設定の `gthread` 化
- [x] `site/app.js`: SSE 接続管理の健全化（`onerror` 時のクローズ、タイマー重複の根絶、タブ非表示時の切断、再表示時の再接続）
- [x] `site/app-min.js`: Google Closure Compiler による再ビルド
- [x] `tests/web/test_dashboard_html.py`: `dashboard.html` に不要な SSE 接続が存在しないことのテスト更新
- [x] `tests/web/test_dashboard_rapid_reload.py`: SSE 接続非存在確認とコンソール側クリーンアップテストの更新
- [x] `docs/issues/README.md`: Issue 台帳の更新

---

## 4. 根本原因分析 (RCA) / Root Cause Analysis
1. **Head-of-Line Blocking によるワーカー枯渇**:
   - Supervisor は `config/supervisor.json` で定義された 2 プロセスの同期ワーカー（`SyncWorker`）で動作していた。同期ワーカーは 1 プロセスにつき同時に 1 リクエストしか処理できない。
   - SSE エンドポイント `/api/stream/top` は最大 3600 秒接続を保持する。
   - クライアントが複数タブを開く、あるいは切断検知前にリロードが発生すると、2 台のワーカープロセスが完全に SSE に専有され、サーバー全体の処理能力がゼロになっていた。
2. **`dashboard.html` における不要な SSE 受信**:
   - Issue 170 で Supervisor タブを削除して Knowledge & CTI Graph 専用画面にしたが、`initSseLiveStream()` が無条件で `/api/stream/top` への常時接続を開き続けており、ワーカーを 1 台浪費していた。
3. **`site/app.js` でのタイマーリークと onerror 処理不足**:
   - `visibilitychange` イベントで `initSseLiveStream()` が再実行されるたびに `setInterval(syncConsoleTelemetry, 5000)` が新規登録され、バックグラウンドポーリングタイマーが重複増殖していた。
   - `onerror` ハンドラで `sseEventSource.close()` が呼ばれず、ブラウザの自動再接続が異常状態で連続発生していた。
4. **ワーカーシャットダウン時のストリーム脱出制御の不足**:
   - `SyncWorker._stream_chunks_loop` で `self.alive` をチェックしていなかったため、シグナル受信時でもクライアント接続中はループから抜け出せなかった。

---

## 5. 実装方針 / Implementation Plan
Target Branch: `fix/172-fix-sse-saturation-blocking-web-workers`

### Step 1: `site/dashboard.html` の不要 SSE ロジック完全撤廃
- `initSseLiveStream()` 関数、`new EventSource('/api/stream/top?interval=1.0')`、イベントリスナー、および `updateSupervisorFromStream(sup)` を削除。
- `syncLiveMesh()` と `setInterval(syncLiveMesh, 5000)` のみを初期化ブロックで起動する。

### Step 2: `site/app.js` の EventSource 管理健全化
- `telemetryIntervalId` を保持し、`setInterval(syncConsoleTelemetry, 5000)` の重複登録を防止。
- `sseEventSource.onerror` で明示的に `sseEventSource.close()` を呼び出し `sseEventSource = null` に設定。
- `pagehide`, `beforeunload`, `visibilitychange` (hidden) で確実に close する。

### Step 3: Supervisor 設定およびワーカーの並行性強化
- `config/supervisor.json`: `web` プールを `worker_class="gthread"`, `threads=4` に設定。
- `config/supervisor.sample.*`: 同様に `gthread`, `threads=4` に統一。
- `src/supervisor/config.py`: `PoolConfig` のデフォルトを `worker_class="gthread"`, `threads=4` に設定。
- `src/supervisor/arbiter.py`: `_run_web_worker` で `spec.metadata.get("threads")` を取得し `worker_cls(..., threads=threads)` に渡す。
- `src/supervisor/workers/gthread_worker.py`: `threads: Optional[int] = None` を受け取り、指定されたスレッド数で `ThreadPoolExecutor` を初期化。
- `src/supervisor/workers/sync_worker.py`: `_stream_chunks_loop` で `if not self.alive: break` および終了時イテレータクローズを徹底。

### Step 4: テスト更新および新規検証
- `tests/web/test_dashboard_html.py`: `test_dashboard_sse_event_source_ui` を更新し、`dashboard.html` に `/api/stream/top` および `EventSource` が存在しないことを検証。
- `tests/web/test_dashboard_rapid_reload.py`: `test_dashboard_html_contains_unload_cleanup` を更新し、`site/app.js` のクリーンアップおよび `dashboard.html` の SSE 排除を検証。
- 新規テスト: `GthreadWorker` へのスレッド数伝播および同時接続耐性をテスト。

### Step 5: ビルドおよび品質検証
- `make build_js`: Closure Compiler で `site/app-min.js` を再コンパイル。
- `make check_format`, `make py_compile`, pytest を実行し品質ゲートを 100% 通過させる。

---

## 6. 完了条件 / Success Criteria (DoD)
- [x] `dashboard.html` から不要な `/api/stream/top` SSE 接続が完全に撤廃されていること。
- [x] `site/app.js` における SSE ライフサイクル（close / reconnect / timer 重複防止）が健全に管理されていること。
- [x] `config/supervisor.json` および Supervisor デフォルト設定で `GthreadWorker` (`threads=4`) が有効となり、SSE 接続中であっても別タブ・別クライアントからの HTTP リクエスト（`/dashboard.html`, `/index.html`, `/api/stats` 等）が一切ブロックされずに即時応答（HTTP 200）すること。
- [x] `SyncWorker` が停止シグナル時に即座にストリームループを脱出できること。
- [x] `make build_js` で `site/app-min.js` がエラーなくコンパイルされていること。
- [x] 関連テスト（`tests/web/`、`tests/supervisor/`）が 100% PASS すること。
- [x] `make check_format` および `make py_compile` がエラー 0 件で合格すること。
- [x] Issue 172 のステータスが更新されていること。
