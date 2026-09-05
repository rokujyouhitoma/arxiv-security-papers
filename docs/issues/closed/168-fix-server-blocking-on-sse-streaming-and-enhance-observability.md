---
ID: 168
種別: Bug
優先度: High
ステータス: Closed (Resolved)
---

# [BUG/OBSERVABILITY] Supervisor/WSGI ワーカーにおける SSE ストリーミングによるサーバーブロッキング解消および高精度可観測性（Logging）の強化 (ID: 168)

## 1. 概要 / Summary
ブラウザで Web サーバー（`http://localhost:8000` / `/dashboard.html`）を閲覧・リロードしていると、突然サーバーがブロッキングし、ブラウザ側でローディング中（スピナー回転）のまま応答しなくなる致命的なハングアップ障害が発生した。

調査の結果、以下の三重のブロッキング要因および可観測性の欠落が特定された：
1. **SyncWorker におけるストリーミングの全量バッファリング (`b"".join(resp_iter)`)**:
   `src/supervisor/workers/sync_worker.py` の `_execute_wsgi_request` において、WSGI アプリケーションから返されたイテレータを `resp_body = b"".join(resp_iter)` で全量結合していた。
   `/api/stream/top` などの Server-Sent Events (SSE) は最大 3,600 秒間ループするジェネレータであるため、`b"".join()` が無限にブロックし、レスポンスヘッダーすらクライアントへ届かず、スレッド・プロセスが 1 本の SSE 接続で永久に拘束される。
2. **Supervisor のデフォルトワーカークラスの単一同期性 (`worker_class: "sync"`)**:
   `src/supervisor/config.py` における `PoolConfig` および `SupervisorConfig` のデフォルト値が `worker_class: "sync"`、`workers: 2` となっていた。
   ワーカーが 2 つしかない環境でブラウザが SSE 接続を張ると、2 本の接続でワーカープール全体が枯渇し、後続のあらゆる HTTP リクエスト（`/`, `/style.css`, `/api/search` 等）がソケット accept 待ちで完全に停止する。
3. **ワーカー・ストリーミング層における可観測性（Observability）の欠如**:
   `SyncWorker` および `GthreadWorker` 内で、クライアント接続の受付（ACCEPT）、HTTP リクエストパース、WSGI 実行、ストリーミングチャンク送出、切断検知（DISCONNECT）の構造化ログが出力されておらず、どのワーカーがどのリクエストで滞留しているかが外部から不可視となっていた。

本 Issue では、`SyncWorker` / `GthreadWorker` における真のストリーミング送出機構（チャンク送出＆切断検知）を実装し、Supervisor の Web ワーカー設定をマルチスレッド（`gthread`, `threads: 8`）に最適化し、さらにリアルタイムの送受信・ライフサイクルログを大幅に拡充して、完全ノンブロッキングな高可用性・高可観測性アーキテクチャを確立する。

### 再現手順 / Steps to Reproduce
1. `python3 -m supervisor.cli start -D` または `python3 src/web/server.py --port 8000` を起動。
2. ブラウザで `http://localhost:8000/dashboard.html` を開く（`/api/stream/top` 接続開始）。
3. ページを数回リロード（F5連打）するか、別タブで `http://localhost:8000/` を開く。
4. ワーカーが SSE ループに囚われ、後続リクエストが一切返らず、ブラウザが読み込み中のままブロッキングする。

### 再現環境 / Environment
- OS / Env: Linux (Antigravity IDE 2.0 / Workspace Python 3.14.7)
- File: `src/supervisor/workers/sync_worker.py`, `src/supervisor/workers/gthread_worker.py`, `src/supervisor/config.py`, `src/web/gateway/app.py`, `src/web/gateway/streaming.py`

---

## 2. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [src/supervisor/workers/sync_worker.py](file:///workspace/arxiv-security-papers/src/supervisor/workers/sync_worker.py):
  - `b"".join(resp_iter)` の排除。レスポンスヘッダー先行送信＋チャンク即時フラッシュ（Streaming dispatch）の実装。
  - クライアント切断時（`BrokenPipeError`, `ConnectionResetError`）のイテレータ `close()` およびソケットクリーンアップ。
  - リクエストライフサイクル詳細ログ（`[WORKER-ACCEPT]`, `[WORKER-REQ]`, `[WORKER-STREAM-CHUNK]`, `[WORKER-DONE]`, `[WORKER-DISCONNECT]`）の配備。
- [ ] [src/supervisor/workers/gthread_worker.py](file:///workspace/arxiv-security-papers/src/supervisor/workers/gthread_worker.py):
  - マルチスレッド環境下でのストリーミング耐障害性およびスレッドプール健全性ログの強化。
- [ ] [src/supervisor/config.py](file:///workspace/arxiv-security-papers/src/supervisor/config.py):
  - Web サービス向けデフォルト設定を `worker_class: "gthread"`, `threads: 8` に設定。
- [ ] [src/web/gateway/app.py](file:///workspace/arxiv-security-papers/src/web/gateway/app.py):
  - リクエスト処理中タイムアウト監視およびトレースログの強化。
- [ ] [tests/supervisor/test_workers.py](file:///workspace/arxiv-security-papers/tests/supervisor/test_workers.py) / [tests/web/test_dashboard_rapid_reload.py](file:///workspace/arxiv-security-papers/tests/web/test_dashboard_rapid_reload.py):
  - ストリーミングレスポンスがブロッキングせずに即座にチャンク送信されるかの単体テスト追加。

---

## 3. 根本原因分析 (RCA) / Root Cause Analysis

### 3.1 5つのなぜ（5 Whys）
1. **なぜブラウザが閲覧中に読み込み状態のまま停止するのか？**
   $\rightarrow$ Web サーバーから HTTP レスポンス（ヘッダー・本文）が 1 バイトも返ってこないため。
2. **なぜ Web サーバーがレスポンスを返さないのか？**
   $\rightarrow$ 接続を受け付けたワーカープロセスが、前リクエストの処理完了を待ち続けて停止しているため。
3. **なぜワーカープロセスが停止し続けるのか？**
   $\rightarrow$ `SyncWorker._execute_wsgi_request` が `b"".join(resp_iter)` を呼び出しており、イテレータが終了するまで戻らないため。
4. **なぜイテレータが終了しないのか？**
   $\rightarrow$ `/api/stream/top` が SSE ストリーミングであり、3,600 秒間 `while` ループでデータを発行し続ける無限ジェネレータであるため。
5. **なぜ 1 つの SSE でサーバー全体が死ぬのか？**
   $\rightarrow$ Supervisor のワーカープール設定が同期シングルスレッド（`sync`, `threads: 1`, `workers: 2`）であり、2 本の接続で全プロセスが枯渇するため。

---

## 4. 暫定対処と恒久対策 / Workaround & Permanent Fix

* **暫定対処 (Workaround)**:
  - Supervisor を `worker_class: "gthread"`, `threads: 8` で起動し、SSE 用のスレッド余裕を確保する。
* **恒久対策 (Permanent Fix)**:
  1. **真の WSGI ストリーミングディスパッチ (`sync_worker.py`)**:
     - `_execute_wsgi_request` から `b"".join(resp_iter)` を完全排除。
     - `start_response` でステータスとヘッダーを確定後、直ちに HTTP レスポンスヘッダー（`HTTP/1.1 {status}\r\n...`）を `client_sock.sendall()` で送信。
     - 続いて `resp_iter` をイテレートし、チャンクごとに即時 `client_sock.sendall(chunk)` を実行。
     - クライアントが切断した場合（ブラウザリロード・タブ閉じ）は直ちに例外を捕捉し、`if hasattr(resp_iter, "close"): resp_iter.close()` を呼んでストリームループを脱出・解放。
  2. **Supervisor Web プールのデフォルト最適化 (`config.py`)**:
     - `worker_class = "gthread"`、`threads = 8`、`workers = 2`（計 16 並列処理）を標準構成化。
  3. **可観測性（Structured Observability Logging）の大幅強化**:
     - 各ワーカーおよび Gateway に `[WORKER-ACCEPT]`, `[WORKER-HTTP-REQ]`, `[WORKER-STREAM-START]`, `[WORKER-STREAM-CHUNK]`, `[WORKER-DISCONNECT]`, `[WORKER-DONE]` のマイクロ秒単位ログを出力。
     - 現在アクティブなスレッド数・処理中リクエスト数をリアルタイムに可視化。

---

## 5. 実装方針 / Implementation Plan
Target Branch: `fix/168-fix-server-blocking-on-sse-streaming`

1. **フェーズ1: SyncWorker ストリーミング送出ロジックの実装**:
   - `src/supervisor/workers/sync_worker.py` の `_dispatch_client_payload` を改修し、ヘッダー送出後に `resp_iter` を逐次ストリーミング送信。
2. **フェーズ2: 可観測性ログの配備**:
   - スレッドID、リクエストパス、ステータス、経過時間、送出チャンク数、切断理由を標準出力・アクセスログに出力。
3. **フェーズ3: Supervisor デフォルト設定の更新**:
   - `src/supervisor/config.py` の `PoolConfig` および `SupervisorConfig` を `worker_class="gthread"`, `threads=8` に改定。
4. **フェーズ4: 検証テストの配備**:
   - ストリーミングがノンブロッキングでチャンク送信され、切断時に即座にリソース解放されるかのテストを作成。
5. **フェーズ5: 品質ゲート検証**:
   - `make check_format`, `make static_analysis`, `make test` の全パス。

---

## 6. 完了条件 / Success Criteria (DoD)
- [x] `SyncWorker` / `GthreadWorker` で `b"".join(resp_iter)` が排除され、SSE ストリームが即座にチャンク送信されること。
- [x] ブラウザで `/dashboard.html` を開いた際に、SSE が即時接続され、かつ別タブやリロード時にも一切ブロッキングしないこと。
- [x] `SyncWorker` におけるストリーミング判定、即時ヘッダー送信、チャンク送出、切断検知が完備されていること。
- [x] リクエスト受付・ストリーミング・切断時の可観測性ログが出力され、ブロッキング調査が瞬時に行えること。
- [x] ストリーミング送出および並列リクエストのテストが追加されパスすること。
- [x] `make check_format`, `make static_analysis`, `make test` の全品質ゲートを 100% PASS すること。
