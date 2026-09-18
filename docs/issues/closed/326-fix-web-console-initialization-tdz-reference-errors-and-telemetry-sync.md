---
ID: 326
種別: Bug
優先度: High
ステータス: Closed (Resolved)
---

# [BUG/SEC] Webコンソール初期化時におけるTDZ参照エラーの解消およびテレメトリ・検索パイプライン堅牢化 (ID: 326)

## 1. 概要 / Summary

Webダッシュボード（`site/app.js`）の初期表示時において、JavaScript の Temporal Dead Zone (TDZ) に起因する複数の `ReferenceError`（`loadMoreContainer`、`currentOffset`、`spiderPollingInterval`）が発生し、ページ初期化処理やテレメトリ取得、検索実行が途中で停止する不具合が発生した。

併せて、以下の連鎖的障害を調査・特定し、包括的に解消・堅牢化した。
1. `drawWalkChart()` における空履歴配列へのアクセス例外 (`TypeError: Cannot read properties of undefined (reading 'toFixed')`) によるテレメトリ同期中断
2. Issue 325 (設定関数集約) に伴う Supervisor ワーカー側での `settings.get_all_configured_databases` インポートエラー (HTTP 500) と、それに起因するデータベース台帳の読込停止 (`Loading database tables telemetry...` のまま固まる現象)
3. 検索カテゴリフィルタ (`category=pentest` 等) 指定時に `FacetedIndex` のカテゴリ判定が空集合となり 0 件になる現象

### 再現手順 / Steps to Reproduce
1. Webコンソール (`http://localhost:8000/`) にアクセスする。
2. ブラウザの開発者ツール (Console) を開く。
3. `Uncaught (in promise) ReferenceError: Cannot access 'loadMoreContainer' before initialization` や `Cannot access 'currentOffset' before initialization` が発生し、検索結果およびテレメトリの描画が停止する。
4. データベース管理タブに遷移しても「Loading database tables telemetry...」のまま更新されない。
5. 「ペンテスト」の推奨カテゴリタグをクリックしても検索結果が 0 件となる。

### 再現環境 / Environment
- OS / Env: Linux (WSL2 / Ubuntu), Python 3.12, Modern Web Browsers (Chrome / Edge / Firefox)
- Target Files: `site/app.js`, `src/settings.py`, `src/search/ingestion/faceted_index.py`, `src/web/gateway/handlers.py`

---

## 2. 影響範囲と関連ファイル / Scope and Affected Files

- [x] [site/app.js](../../site/app.js): 変数ホイスティング・TDZ解消、DOM要素参照の一元化、`drawWalkChart` の配列境界防御、テレメトリ同期トリガー改善
- [x] [src/settings.py](../../src/settings.py): PEP 562 `__getattr__` による `core.settings` 委譲フォールバックの実装（Supervisor等の下位互換性確保）
- [x] [src/search/ingestion/faceted_index.py](../../src/search/ingestion/faceted_index.py): `CATEGORY_ALIASES` 定義とエイリアス候補解決によるドメインカテゴリ検索の修復
- [x] [src/web/gateway/handlers.py](../../src/web/gateway/handlers.py): カテゴリのみ指定時の `effective_query` フォールバック
- [x] [src/search/client.py](../../src/search/client.py): 検索クライアントにおけるクエリフォールバック対応
- [x] [src/search/server/service.py](../../src/search/server/service.py): 検索サービス層におけるクエリフォールバック対応
- [x] [tests/search/test_vector_engine.py](../../tests/search/test_vector_engine.py): カテゴリエイリアス検索の単体テスト追加
- [x] [tests/test_settings_timezone.py](../../tests/test_settings_timezone.py): `settings.__getattr__` 下位互換アクセスの単体テスト追加

---

## 3. 根本原因分析 (RCA) / Root Cause Analysis

1. **Temporal Dead Zone (TDZ) による参照エラー**:
   - `site/app.js` は `document.addEventListener('DOMContentLoaded', () => { ... })` 内に単一のブロックスコープとして定義されている。
   - `function` 宣言（`performSearch`, `stopSpiderAutoPolling` 等）はスコープ先頭にホイスティングされるが、`let` / `const` で定義された共有状態変数（`spiderPollingInterval`, `currentOffset`, `currentLimit`, `loadMoreContainer` 等）は定義行に到達するまで TDZ 状態となる。
   - スクリプト起動時に `handleRoute()` → `switchToTab()` → `stopSpiderAutoPolling()` や、初期検索の `performSearch()` がファイル中盤で呼び出された際、後方に記述されていた変数が参照され `ReferenceError` でクラッシュしていた。

2. **Canvas 描画時の空配列未チェック**:
   - 初期ロード直後は `walkHistory` が `[]` であり、`walkHistory[walkHistory.length - 1]` は `undefined` となる。
   - `undefined.toFixed(1)` の呼び出しで `TypeError` が発生し、`syncConsoleTelemetry()` の非同期処理が途中で中断されていたため、KPIカードやバナー時刻の同期が止まっていた。

3. **設定関数集約による外部プロセスのインポート破損**:
   - Issue 325 において `settings.py` のメタデータ関数群（`get_all_configured_databases` 等）を `core.settings` へ移譲した際、別プロセスで常駐起動していた Supervisor のバックグラウンドワーカーが古い `from settings import get_all_configured_databases` を参照したまま `ImportError` で 500 エラーを返し、`/api/graph/mesh` が落ちていた。

4. **FacetedIndex のカテゴリ排他フィルタ不整合**:
   - `FacetedIndex._add_single_tag` は `cs.*` 形式のタグのみを `categories` に格納し、日本語のドメインタグは `domains` や `tags` に格納していた。
   - UIの推奨タグが送信する `category=pentest` に対し、`self.categories.get("pentest")` が常に空集合となり、AND絞り込みで全件ヒットが除外されて 0 件になっていた。

---

## 4. 暫定対処と恒久対策 / Workaround & Permanent Fix

* **暫定対処 (Workaround)**:
  - ブラウザのリロードまたはキャッシュクリアのみではスクリプト構造上の TDZ は解消されないため、コードレベルでの変数のスコープ先頭移動が必須。
* **恒久対策 (Permanent Fix)**:
  1. `site/app.js` の `DOMContentLoaded` 最上部に、全共有状態変数および DOM 要素セレクタ（`loadMoreContainer`, `pageSizeSelect` 等）を宣言・初期化する統一構造へ再編。
  2. `drawWalkChart` に `if (!walkHistory || walkHistory.length === 0) return;` の安全ガードを追加。
  3. `src/settings.py` に PEP 562 `__getattr__` を追加し、`core.settings` から動的委譲することで未再起動プロセスや互換インポートを 100% 透過的に解決。
  4. `src/search/ingestion/faceted_index.py` に `CATEGORY_ALIASES` を導入し、カテゴリ指定のエイリアス（`pentest`, `malware`, `autonomous`, `llm`）を適切にドメインタグと紐付けて候補集合を返すように改修。

---

## 5. 実装方針 / Implementation Plan

Target Branch: `fix/326-web-console-initialization-tdz-and-telemetry-sync`

1. **Frontend ホイスティング整合性**:
   - `site/app.js` の先頭（1〜35行目）に `DOMContentLoaded` で利用される全状態変数・DOM要素を配置。
   - 途中に残存していた重複した `const loadMoreContainer` や `let currentOffset` を完全排除。
2. **描画・例外ハンドリングの強化**:
   - `drawWalkChart()` の境界値防御。
   - `renderDatabaseTab()` における初回データ自動取得（`syncConsoleTelemetry()`）の確約。
3. **バックエンド互換性と検索ルーティング**:
   - `src/settings.py` の `__getattr__` 委譲。
   - `CATEGORY_ALIASES` によるファセット検索候補解決。
4. **テスト検証**:
   - 単体テスト（`tests/search/test_vector_engine.py`, `tests/test_settings_timezone.py`）の実行。
   - エンドポイント疎通確認（`/api/stats`, `/api/search`, `/api/graph/mesh`）。

---

## 6. 完了条件 / Success Criteria (DoD)

- [x] `site/app.js` 読み込み時に TDZ に起因する `ReferenceError`（`loadMoreContainer`, `currentOffset`, `spiderPollingInterval`）が 0 件であること。
- [x] `drawWalkChart` で `TypeError` が発生せず、テレメトリ同期（`syncConsoleTelemetry`）が正常完了すること。
- [x] `/api/graph/mesh` が HTTP 200 を返し、Database Tables テーブルに3つのDBテーブル情報（レコード数・容量）が表示されること。
- [x] 「ペンテスト」検索時に 0 件にならず、該当論文（ATOBench、RapidPen等）が正常にカード表示されること。
- [x] 各種単体テストが PASS すること。
