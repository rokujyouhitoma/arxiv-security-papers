---
ID: 401
種別: Feature
優先度: Medium
ステータス: Closed
---

# [FEAT/ENH] Web コンソールにおけるスパイダー巡回状態（チェックポイント）の可視化および再開・破棄制御UIの実装 (ID: 401)

## 1. 概要 / Summary

Issue 397 において、低レイヤーのクローラーエンジン（`StateStorage`）、デーモン（`SpiderDaemonWorker`）、透過クライアント（`SpiderDaemonClient`）、および Web Gateway に「スパイダーの中断時巡回状態（Frontier & Bloom Filter）永続化と自動再開（Resume）」基盤が導入された。

しかしながら、現行の Web コンソール（`site/index.html`, `site/app.js`）および `/api/spiders/status` においては、各スパイダー（arXiv, CWE, KEV-CVE, NVD, IACR 等）のチェックポイント存在有無や保留中リクエスト数などの巡回状態がエンドポイントから返却されておらず、UI 上にも「再開可能な中断データが存在するか」「通常実行とチェックポイント再開のどちらを行うか」をオペレーターが視覚的に把握・制御する手段が存在しない。

本 Issue では、Web Gateway API に各スパイダーのチェックポイントメタデータ（存在有無、更新日時、保留中URL件数等）の取得および個別チェックポイント破棄（クリア）エンドポイントを追加し、Web コンソールのスパイダー管理カード（`spiderTab`）において中断状態のバッジ表示、ワンクリックでの「チェックポイントから再開（Resume）」実行、および「チェックポイント破棄（初期化）」操作を可能とする。

---

## 2. トレーサビリティ / Traceability

- **関連 Issue**:
  - [Issue 397 (Closed): 中断スパイダーの巡回状態（Frontier）保存・デーモンによる自動再開（Resume）機能の実装](closed/397-spider-frontier-state-persistence-and-daemon-resume.md)
  - [Issue 393 (Closed): スパイダー手動トリガーのUI即時フィードバック実装および実行ログ台帳カラム整合性の修正](closed/393-fix-spider-manual-trigger-feedback-and-storage-mapping.md)
  - [Issue 395 (Closed): スパイダー実行の排他制御（Mutex）および二重起動防止の実装](closed/395-spider-execution-concurrency-control-and-mutex.md)
  - [Issue 396 (Closed): 停止・異常終了した孤立スパイダージョブの定期検知および状態修復の実装](closed/396-spider-stale-job-reconciliation-and-watchdog.md)
- **アーキテクチャ規約**:
  - Antigravity IDE & 2.0 Web Gateway ガバナンス規約
  - Pure Vanilla JS (フレームワーク非依存・JSDoc 型契約・Closure Compiler 適合)
  - ゼロ外部依存・アトミックファイル操作・Xenon CC <= 3 (Rank A)・Mypy Strict 適合

---

## 3. ガバナンス・専門エージェント多角的レビュー / Multi-Perspective Review

### Project Manager (PM)
- **優先度判断**: Medium（運用可観測性と操作性の完成）。Issue 397 で実装されたフロンティア永続化機構をエンドユーザー・オペレーターが Web UI 上で直感的に監視・制御できるようにし、システム全体の運用性を高める。
- **目標**: チェックポイントの可視化と制御（再開・破棄）を Web コンソールに統合し、手動操作時にも自動再開とクリーン開始を明示的に選択可能とする。

### Systems Architect
- **データフロー設計**: 
  - `StateStorage.get_checkpoint_info` を導入し、ファイル I/O と JSON パースを低層ストレージモジュールに集約。
  - Web Gateway（`handlers.py`）は `StateStorage` から正規化されたメタデータ（辞書）を取得して `/api/spiders/status` レスポンスに注入する。
  - フロントエンドは既存の `loadSpiderStatus` ポーリング周期（3秒）で自動更新され、状態遷移がシームレスに同期される。

### Information Security Specialist
- **CWE-22 (Path Traversal) 防御**:
  - `POST /api/spiders/checkpoint/clear` や状態取得において、クライアントから渡される `spider_name` パラメータを英数字・ハイフン・アンダースコア（`^[a-zA-Z0-9_-]+$`）に厳格バリデーションする。
  - パス解決時、正規化された絶対パス（`os.path.realpath`）が許可された既定ディレクトリ（`outputs/spider/checkpoints/`）配下に存在することを強制検証し、任意のファイル削除・読取を完全に遮断する。
- **CWE-732 (不適切なパーミッション) 防止**:
  - チェックポイント操作は読み取りと安全削除（`os.remove`）に限定し、外部への任意のデータ書き込みを発生させない。

### Software Development (SWD)
- **低オーバーヘッドなメタデータ取得**:
  - `get_checkpoint_info` では、巨大な JSON の全パースを回避するため、ファイル存在確認（`os.path.isfile`）およびサイズ・mtime 取得を先行。
  - 保留リクエスト件数や Bloom 件数は、JSON のメタデータ（`pending_count`, `bloom_count`）のみを読み取るか、安全な try-except でロードして返却。
- **純粋 Python / ゼロ外部依存**:
  - 新たなライブラリを追加せず、標準ライブラリ（`os`, `json`, `re`, `datetime`）のみで完結。

### Application Specialist (APS) & UI/UX Designer
- **直感的な UI/UX レイアウト**:
  - 各スパイダーカード内に、チェックポイントが存在する場合のみブルー系のハイライト領域（`checkpointContainer_<key>`）を表示。
  - 「💾 中断チェックポイント: X件保留中 (YYYY-MM-DD HH:MM)」のインフォメーション。
  - ボタングループとして「⏯️ 中断から再開」ボタンと「🗑️ チェックポイント破棄」ボタンを配置。
  - チェックポイントが存在しない平常時は通常通りの「⚡ 今すぐ実行 (新規開始)」のみを表示し、UI の簡潔さを維持。

### Software Quality Assurance Specialist (QA)
- **品質ゲート要件**:
  - 新設する全 Python 関数において循環的複雑度 CC <= 3 (Xenon Rank A) を維持。
  - `mypy --strict` 型検査 0 エラー。
  - Web サーバー結合テスト（`tests/web/test_web_server.py`）およびフロントエンド契約テスト（`tests/web/test_js_syntax_and_contracts.py`）の 100% PASS。

---

## 4. 脅威分析とセキュリティ要件 (Threat Model & Security Requirements)

1. **脅威シナリオ**:
   - **CWE-22 (Path Traversal)**: 悪意あるユーザーまたは壊れたクライアントが `spider_name` に `../../database/papers_catalog.json` や `/etc/passwd` を指定して `POST /api/spiders/checkpoint/clear` を呼び出した場合、意図しない重要データが削除される。
   - **CWE-400 (Uncontrolled Resource Consumption)**: 破損した巨大なチェックポイントファイルが置かれた場合にステータス API のレスポンスが極端に遅延する。
2. **セキュリティ要件**:
   - `spider_name` は `^[a-zA-Z0-9_-]{1,64}$` の正規表現に完全一致することを検証し、不一致の場合は HTTP 400 Bad Request を即時返却する。
   - `_resolve_checkpoint_file` において `os.path.abspath` および `os.path.realpath` を用いて、対象ファイルが `outputs/spider/checkpoints/` ディレクトリ配下に収まっていることをアサート検証する。
   - チェックポイントファイル読み取り時のタイムアウトおよび JSON デコード例外を安全に捕捉し、破損時は HTTP 500 を出さず `{ "has_checkpoint": False, "corrupted": True }` を返却する。

---

## 5. 影響範囲と関連ファイル / Scope and Affected Files

- [x] [src/spider/distributed/state_storage.py](../../src/spider/distributed/state_storage.py) (`get_checkpoint_info` メタデータ参照ヘルパーの追加、パス解決のディレクトリトラバーサル防御強化)
- [x] [src/web/gateway/handlers.py](../../src/web/gateway/handlers.py) (`handle_spider_status` での `checkpoint` 情報結合、および `handle_spider_checkpoint_clear` エンドポイントの実装)
- [x] [src/web/gateway/app.py](../../src/web/gateway/app.py) (`POST /api/spiders/checkpoint/clear` ルーティングの追加)
- [x] [site/index.html](../../site/index.html) (`spiderTab` 内のスパイダーカードへのチェックポイント表示領域、再開ボタン、破棄ボタンの追加)
- [x] [site/app.js](../../site/app.js) (`loadSpiderStatus` でのチェックポイントメタデータ反映、`triggerSpider(spiderName, triggerBtn, resume)` 拡張、`clearSpiderCheckpoint` 実装)
- [x] [tests/web/test_web_server.py](../../tests/web/test_web_server.py) (チェックポイント情報取得およびクリア API の結合テスト、パストラバーサル遮断テスト)
- [x] [tests/web/test_js_syntax_and_contracts.py](../../tests/web/test_js_syntax_and_contracts.py) (フロントエンド構文・ID バインディング整合性検証)
- [x] [docs/issues/README.md](README.md) (Issue 台帳の進捗更新)

---

## 6. 実装方針 / Implementation Plan

Target Branch: `feat/401-spider-checkpoint-visualization-and-web-resume-control`

### ステップ 1: StateStorage メタデータ抽出とパス解決の堅牢化
- [src/spider/distributed/state_storage.py](../../src/spider/distributed/state_storage.py):
  - `_resolve_checkpoint_file(target: str, base_dir: str) -> str`:
    - `target` のファイル名サニタイズ（`os.path.basename`）を徹底し、ディレクトリトラバーサル文字列を無害化。
    - 解決された絶対パスが `os.path.abspath(base_dir)` 配下にあることを確認。
  - `get_checkpoint_info(spider_name: str, base_dir: str = "outputs/spider/checkpoints") -> Dict[str, Any]`:
    - ファイルが存在しない場合は `{"has_checkpoint": False}` を返却。
    - ファイルが存在する場合、サイズ、最終更新日時（mtime の ISO 8601 文字列）、`pending_count`、`bloom_count` を含むメタデータ辞書を生成して返却。
    - Xenon CC <= 3 を厳格に順守。

### ステップ 2: Web Gateway API の拡張
- [src/web/gateway/handlers.py](../../src/web/gateway/handlers.py):
  - `handle_spider_status`:
    - `storage.get_status_summary()` の各スパイダー情報に対して `StateStorage.get_checkpoint_info(key)` の辞書をマージ（`"checkpoint": checkpoint_info`）。
  - `handle_spider_checkpoint_clear(environ, start_response)`:
    - リクエスト JSON から `spider_name` を取得。
    - 入力値バリデーション（空チェック、正規表現 `^[a-zA-Z0-9_-]+$`）。不正時は 400 Bad Request。
    - `StateStorage.clear_checkpoint(spider_name)` を実行。
    - 成功時は `{"status": "ok", "cleared": True, "spider_name": spider_name}` を 200 で返却。
- [src/web/gateway/app.py](../../src/web/gateway/app.py):
  - `POST /api/spiders/checkpoint/clear` のルーティングを追加。

### ステップ 3: Web コンソール UI / HTML の拡充
- [site/index.html](../../site/index.html):
  - 各スパイダーカード（`arxiv`, `cwe`, `kev_cve`）のメトリクス下に、チェックポイント表示エリア（`containerSpiderCheckpoint_<key>`）を追加。
  - ボタングループに「再開実行（`btn-resume-spider`）」および「破棄（`btn-clear-spider-checkpoint`）」を追加（初期スタイルは `display: none`）。

### ステップ 4: フロントエンド JavaScript (`site/app.js`) の連動
- [site/app.js](../../site/app.js):
  - `loadSpiderStatus()`:
    - レスポンス内の `info.checkpoint` を評価。
    - `has_checkpoint` が True の場合:
      - チェックポイント領域を表示し、保留件数（例: `342 件保留中`）と保存日時を表示。
      - 再開ボタン（`btn-resume-spider`）および破棄ボタン（`btn-clear-spider-checkpoint`）を表示。
    - False の場合:
      - チェックポイント領域と再開・破棄ボタンを非表示化。
  - `triggerSpider(spiderName, triggerBtn, resume = false)`:
    - 引数 `resume` をサポートし、API リクエスト `{ spider_name: spiderName, resume: Boolean(resume) }` を送信。
    - トースト通知に「チェックポイントから再開中...」を表示。
  - `clearSpiderCheckpoint(spiderName, clearBtn)`:
    - 確認または即座に `/api/spiders/checkpoint/clear` を呼び出し、トースト通知を表示後に `loadSpiderStatus()` を即時トリガー。
  - イベントリスナー登録:
    - `.btn-resume-spider` および `.btn-clear-spider-checkpoint` のクリックハンドラを追加。

### ステップ 5: テストと品質ゲートの検証
- [tests/web/test_web_server.py](../../tests/web/test_web_server.py):
  - `GET /api/spiders/status` で `checkpoint` フィールドが正しく返却されるテスト。
  - `POST /api/spiders/checkpoint/clear` の正常系および不正な `spider_name`（パストラバーサル攻撃）に対する 400 エラーテスト。
- [tests/spider/test_spider_distributed_and_runner.py](../../tests/spider/test_spider_distributed_and_runner.py):
  - `StateStorage.get_checkpoint_info` の単体テスト。
- `make check_format`
- `make static_analysis` (Xenon Rank A, Mypy Strict)
- `tests/web/` の回帰テスト 100% PASS を確認。

---

## 7. 完了条件 / Success Criteria (DoD)

- [x] `StateStorage.get_checkpoint_info` により、安全かつ軽量にチェックポイントのサイズ・更新日時・保留件数が取得できること。
- [x] `StateStorage._resolve_checkpoint_file` においてディレクトリトラバーサル攻撃が確実に遮断されること。
- [x] `GET /api/spiders/status` のレスポンスに各スパイダーの `checkpoint` メタデータが注入されること。
- [x] `POST /api/spiders/checkpoint/clear` により、特定スパイダーのチェックポイントファイルが安全に削除でき、不正入力時に 400 を返却すること。
- [x] Web コンソール上でチェックポイントが存在する場合に視覚的バッジ/情報が表示され、オペレーターが「再開」または「破棄」を選択して実行できること。
- [x] 全ての新規・変更関数の循環的複雑度が CC <= 3 (Xenon Rank A) かつ `mypy --strict` (型エラー 0 件) に適合すること。
- [x] `tests/web/` を含む関連テストおよび静的解析（`make static_analysis`）が 100% PASS すること。
