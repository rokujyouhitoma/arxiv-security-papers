---
ID: 323
種別: Bug
優先度: High
ステータス: Closed (Completed)
完了日: 2026-09-18
---

# [BUG/SEC] settings.py に基づく Active Database Scope 一覧の動的生成と spider_execution_db 表示の実装 (ID: 323)

## 1. 概要 / Summary
「🗄️ データベース & ストレージ統合管理」コンソール（`#/database` タブ）の「🗄️Active Database Scope:」セレクターおよび上部ピルボタン群において、`src/settings.py` の `DATABASES` に新たに追加された `spider_execution_db` が表示されない不具合を根本解決する。

現在、Web コンソール画面（`site/index.html`）および Web Gateway 内部（`src/web/gateway/handlers.py` の `_introspect_database_metrics`）において、データベース名（`arxiv_security_db`, `cti_catalog_db`, `analytics_db`, `graph_db`）が固定値（ハードコード）として定義されている。そのため、`src/settings.py` の `DATABASES` 定義にデータベースが増減しても UI や API が自動追従できない状態となっている。

本改修では、`src/settings.py` を単一の信頼できる情報源（Single Source of Truth: SSOT）として位置づけ、設定の増減に動的かつ自動的に追従して Active Database Scope 一覧（ドロップダウンおよびピルボタン）を生成・表示・切替できるようにする。

### 再現手順 / Steps to Reproduce
1. `src/settings.py` の `DATABASES` に `spider_execution_db` が定義されていることを確認する。
2. Web コンソール (`/dashboard.html` または `/index.html#/database`) を開く。
3. 「🗄️Active Database Scope:」ドロップダウンまたはピルボタングループを確認する。
4. `spider_execution_db` が存在せず、旧来の4つのデータベースのみが表示されている。

### 再現環境 / Environment
- OS / Env: Linux (Ubuntu 24.04 LTS / x86_64)
- Target Files: `src/settings.py`, `src/spider/daemon/storage.py`, `src/web/gateway/handlers.py`, `site/index.html`, `site/app.js`

---

## 2. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [src/settings.py](../../src/settings.py) (`DATABASES` 定義に `DISPLAY_NAME`, `SHORT_LABEL`, `ICON`, `CATEGORY` メタデータを付与し、`get_database_scopes()` および動的イントロスペクションの SSOT とする)
- [x] [src/spider/daemon/storage.py](../../src/spider/daemon/storage.py) (`SpiderExecutionStorage.get_introspection_metadata(workspace_dir)` クラスメソッドを追加し、`spider_execution.vdb` の行数、サイズ、テーブル情報を標準化)
- [x] [src/web/gateway/handlers.py](../../src/web/gateway/handlers.py) (`_introspect_database_metrics` において `settings.DATABASES` を動的に走査・統合し、未定義DBに対するジェネリックVDB/ファイルフォールバックも備えて全スコープを返却)
- [x] [site/index.html](../../site/index.html) (`selectDbScope` および `databaseSelectorPills` の初期マークアップを整理し、動的レンダリング用コンテナとして適正化)
- [x] [site/app.js](../../site/app.js) (`updateDatabaseMetrics` / `renderDatabaseTab` において API から受信した `databases` / `database_names` に基づきドロップダウンとピルボタンを動的再構築し、イベントデリゲーションで操作性を担保)
- [x] [tests/web/test_database_real_introspection.py](../../tests/web/test_database_real_introspection.py) (`spider_execution_db` を含む動的スコープイントロスペクション検証テストの追加)

---

## 3. 根本原因分析 (RCA) / Root Cause Analysis
1. **API レベルのハードコード (Gateway Static Binding)**:
   `src/web/gateway/handlers.py` の `_introspect_database_metrics()` 内で、`databases` 辞書および `database_names` リストに `arxiv_security_db`, `cti_catalog_db`, `analytics_db`, `graph_db` の4つのみが明示的に列挙されており、`settings.DATABASES` からの動的走査・結合が行われていなかった。そのため、Issue 321 で `settings.DATABASES` に追加された `spider_execution_db` が API レスポンスに含まれていなかった。
2. **フロントエンド UI の静的マークアップ (Frontend Static Binding)**:
   `site/index.html` 内の `<select id="selectDbScope">` および `<div id="databaseSelectorPills">` に4つの固定要素がハードコードされており、JavaScript 側（`site/app.js`）で API レスポンスに応じた動的 DOM 再構築（Reconciliation）を行うロジックが存在しなかった。
3. **イベントバインドの単一実行制約 (Static Event Binding)**:
   `site/app.js` の初期化時に `document.querySelectorAll('#databaseSelectorPills .filter-pill')` に対して静的に 1 度だけイベントリスナーが登録されていたため、動的にボタンを追加・変更した際にクリックハンドラーが喪失する構造となっていた。

---

## 4. 暫定対処と恒久対策 / Workaround & Permanent Fix
* **暫定対処 (Workaround)**: なし（UI 上から直接 `spider_execution_db` を選択・閲覧できない）。
* **恒久対策 (Permanent Fix)**:
  1. `src/settings.py` の `DATABASES` 定義に UI 表示用メタデータ（`ICON`, `SHORT_LABEL`, `CATEGORY`）を SSOT として定義。
  2. `src/spider/daemon/storage.py` に `get_introspection_metadata` を実装し、`outputs/database/spider_execution.vdb` の実態イントロスペクションを提供。
  3. `src/web/gateway/handlers.py` の `_introspect_database_metrics` において、`settings.DATABASES` を反復処理して全スコープのメタデータを動的収集し、`database_names` および `databases` に集約。
  4. `site/app.js` にて、`database_metrics` 受信時に `selectDbScope` および `#databaseSelectorPills` を動的再構築。親コンテナに対するイベントデリゲーション（Event Delegation）を採用して安全な切替を実現。
  5. Closure Compiler (`make build_js`) および回帰テストを実行し、増減時の自動追従を検証。

---

## 5. 実装方針 / Implementation Plan
Target Branch: `fix/323-dynamically-populate-database-scopes-from-settings`

1. **`src/settings.py` のメタデータ拡充**:
   - `DATABASES` の各定義に `ICON`, `SHORT_LABEL` を付与：
     - `arxiv_security_db`: `ICON: "🗃️"`, `SHORT_LABEL: "Virtual Tables"`
     - `cti_catalog_db`: `ICON: "🛡️"`, `SHORT_LABEL: "ATT&CK & CTI"`
     - `analytics_db`: `ICON: "📊"`, `SHORT_LABEL: "Telemetry & Trends"`
     - `graph_db`: `ICON: "🕸️"`, `SHORT_LABEL: "Knowledge Graph & SKO"`
     - `spider_execution_db`: `ICON: "🕷️"`, `SHORT_LABEL: "Crawler Execution & Status Logs"`
   - `get_database_metadata(db_name)` ヘルパーを追加。

2. **`src/spider/daemon/storage.py` の改修**:
   - `SpiderExecutionStorage.get_introspection_metadata(workspace_dir)` クラスメソッドを実装。
   - `spider_execution.vdb` のファイルサイズ、テーブル構造（`spider_execution_logs`）、総レコード数を算出。

3. **`src/web/gateway/handlers.py` の動的収集化**:
   - `_introspect_database_metrics()` において `settings.DATABASES` を走査。
   - 各 DB キーに対応する専用イントロスペクション関数、あるいはジェネリック VDB イントロスペクションを実行し、`databases` マップを動的構築。
   - `database_names = [k for k in settings.DATABASES if k != "default"]` を返却。

4. **`site/app.js` の動的レンダリング & イベントデリゲーション**:
   - `renderDatabaseSelectorUI(databases, databaseNames, activeDbKey)` 関数を作成。
   - `<select id="selectDbScope">` の `<option>` 要素群を動的更新。
   - `#databaseSelectorPills` のピルボタン群を動的更新。
   - `#databaseSelectorPills` にイベントデリゲーションを導入（動的生成要素にも確実にハンドラーが機能）。

5. **検証**:
   - `tests/web/test_database_real_introspection.py` にテストケースを追加。
   - `make build_js` で `site/app-min.js` をビルド。
   - `make check_format` および `make py_compile` の通過確認。

---

## 6. 完了条件 / Success Criteria (DoD)
- [x] `src/settings.py` の `DATABASES` に定義された全データベース（`spider_execution_db` を含む）が `/api/telemetry` および `database_metrics` に動的反映されること。
- [x] Web コンソールの「🗄️Active Database Scope:」ドロップダウンおよびピルボタンに `spider_execution_db` が表示され、クリック・選択して概要やテーブル情報を正常に閲覧できること。
- [x] 今後 `settings.py` に新しいデータベースが追加／削除された場合でも、コード改修なしで UI と API が自動追従すること。
- [x] `make build_js` による Google Closure Compiler ビルドが成功し、JS エラーが 0 件であること。
- [x] `make check_format`、`make py_compile`、および `pytest tests/web/` が 100% PASS すること。
