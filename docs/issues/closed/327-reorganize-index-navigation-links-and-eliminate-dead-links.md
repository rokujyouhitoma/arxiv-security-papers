---
ID: 327
種別: Refactor
優先度: Medium
ステータス: Closed (Resolved)
担当エージェント: UI/UX & Documentation Designer, Application Specialist (APS), Software Quality Assurance Specialist
ターゲットブランチ: refactor/327-reorganize-index-navigation-links
---

# [REFACTOR/UX] Webコンソール ナビゲーションリンクの統廃合および死にリンク・循環リダイレクトの根絶 (ID: 327)

## 1. 概要 / Summary

Enterprise Cloud Console（`site/index.html`）のサイドバーナビゲーション（Accordion Groups 1〜3）およびシステム情報バナーに存在する各種リンクを精査した結果、以下の重大な課題が判明した：

1. **死にリンク（未解釈パラメータ）の残存**:
   - `navTelemetry` (`/dashboard.html?tab=telemetry`): `dashboard.html` 側には現在 `telemetry` タブが存在せず、単にグラフ画面が開くだけのデッドリンク（`site/index.html#/system` にテレメトリ画面が集約された後の残骸）。
   - `navMatrix` (`/dashboard.html?tab=graph&view=matrix`) および `navRules` (`/dashboard.html?tab=graph&view=rules`): `dashboard.html` 側に `view` パラメータを解釈・ハンドリングするロジックが存在せず、単にデフォルトのナレッジグラフ画面が開くだけで機能的に重複。
2. **無意味な循環リダイレクトと重複動線**:
   - `navLogs` (`/dashboard.html?tab=supervisor`): クリックすると `dashboard.html` のルーティングフォールバックによって即座に `index.html#/supervisor` へリダイレクトバックされる（同一サイドバー内の `navSupervisor` と完全重複し、無駄なHTTP通信と画面チラつきを発生）。
   - `systemInfoBanner` 内の「更新ログを確認 ↗」も同様に `/dashboard.html?tab=supervisor` へリンクしており、不要な画面リロードとリダイレクトループを誘発。
3. **リサーチギャップ探索の動線未連携**:
   - `navGaps` (`/dashboard.html?tab=graph&view=gaps`) は `view=gaps` が無視されているが、`dashboard.html` には既に `runPresetQuery('gaps')`（未研究・未対策脅威のハイライト機能）が実装されている。URLクエリパラメータ（`?q=gaps`）を起動時に解釈・実行するように改修することで、即座に実用的なディープリンク機能を提供できる。

本改修では、全14項目のナビゲーションを機能実態に即してスリム化（10項目へ統廃合）し、死にリンクおよび循環リダイレクトを完全排除するとともに、SPA内部タブと外部専用画面（CTI Graph Engine）への連携動線を最適化する。

---

## 2. 現状課題と根本原因分析 (RCA) / Background & Root Cause Analysis

### 課題の根本原因
1. **コンソール統合（Issue 169 / Issue 171）後のリンク残存**:
   - 以前は `dashboard.html` 側に複数タブ（`product`, `system`, `telemetry`, `supervisor`）が存在していたが、モダンな Enterprise Cloud Console（`site/index.html`）への統合に伴い `dashboard.html` は CTI ナレッジグラフ専用画面（`viewGraph`）に特化された。
   - その際、`dashboard.html` 側ではポート済みタブへのリクエストを `index.html` にリダイレクトバックするフォールバック（`switchDashboardTab`）を導入したが、`site/index.html` 側のサイドバーリンクおよび情報バナー内のリンクが古いまま放置されていた。
2. **URLディープリンク解析ロジックの不足**:
   - `site/dashboard.html` の `initTabFromUrl()` は `tab` パラメータまたは Hash のみ解釈しており、検索・プリセットクエリパラメータ（`q`）を拾って `window.openGraphWithQuery()` または `window.executeGraphQuery()` を呼び出す連携が欠落していた。

---

## 3. セキュリティ脅威分析と対策 (Threat Modeling & Security Mitigations)

URLパラメータ `?q=...` を受け入れ、自動的にグラフクエリを実行するディープリンク機能を追加するにあたり、以下の脅威モデルを検証した：

| 脅威シナリオ (Threat Scenario) | リスク評価 | 対策と実装方針 (Mitigation) |
| :--- | :--- | :--- |
| **DOM-based XSS (CWE-79)**: 悪意あるスクリプトを含むクエリ文字列（例: `?q=<script>...`）を埋め込んだURLを踏ませる攻撃 | High (防止必須) | `site/dashboard.html` では `input.value = query`（DOMプロパティ代入）を使用し、`innerHTML` や `eval` によるDOM挿入を行わない。APIリクエスト時は `encodeURIComponent(query)` でクエリパラメータを確実にエスケープする。 |
| **パラメータ改ざん / クエリインジェクション (CWE-89/94)**: バックエンドグラフDSLパーサーへの不正入力 | Low | バックエンド（`/api/graph/query`）は純粋 PEG パーサー（DSN-25）により厳格にパースされ、構文エラー時は安全にエラーレスポンスを返す。クライアント側でも `activeGraphQuery` による状態排他制御を実施。 |
| **オープンリダイレクト (CWE-601)**: 循環リダイレクト悪用による外部ドメイン転送 | None | すべての遷移先は相対パス（`#/supervisor`, `/dashboard.html`）に限定され、外部リダイレクトロジックは存在しない。 |

---

## 4. 影響範囲と関連ファイル / Scope and Affected Files

- [x] [site/index.html](../../site/index.html):
  - サイドバーナビゲーション（Accordion Groups 1〜3）の統廃合（`navTelemetry`, `navLogs`, `navMatrix`, `navRules` の完全削除）
  - `navGaps` のリンク先を `/dashboard.html?q=gaps` に更新
  - `systemInfoBanner` のリンク先を内部SPA遷移（`#/supervisor`）に更新し、「↗」表記を削除
- [x] [site/dashboard.html](../../site/dashboard.html):
  - `initTabFromUrl()` にて `params.get('q')` を取得し、`window.openGraphWithQuery(qParam.trim())` を安全に呼び出すハンドラを追加
  - `openGraphWithQuery` において `executeGraphQuery(query)` へ引数を確実に受け渡すよう堅牢化
- [x] [tests/web/test_enterprise_console_ui.py](../../tests/web/test_enterprise_console_ui.py):
  - `test_enterprise_console_html_structure()` を更新: 統廃合後のナビゲーション構成（10項目）を検証し、削除された4項目（`navTelemetry`, `navLogs`, `navMatrix`, `navRules`）が存在しないことを検証
  - `navGaps` のリンク先が `/dashboard.html?q=gaps` であることの検証を追加
  - `systemInfoBanner` のリンク先が `#/supervisor` であることの検証を追加
  - 新規テスト `test_dashboard_url_query_param_support()` を追加: `dashboard.html` 内で `params.get('q')` がパースされ `openGraphWithQuery` に連携されていることを検証

---

## 5. 詳細実装方針 / Detailed Implementation Plan

Target Branch: `refactor/327-reorganize-index-navigation-links`

### Step 1: `site/index.html` のナビゲーション統廃合
1. **Accordion Group 1: 探索・分析 (Analytics)**:
   - `navSearch` (`#/search`): セマンティック RAG 検索 (維持)
   - `navTrends` (`#/trends`): トレンド & サマリー (維持)
   - `navProduct` (`#/product`): プロダクト分析 & ROI (維持)
   - `navGraph` (`/dashboard.html?tab=graph` -> `/dashboard.html`): CTI ナレッジグラフ ↗ (クエリパラメータ省略形にシンプル化)
2. **Accordion Group 2: 脅威インテリジェンス (Intelligence)**:
   - `navMatrix` (`view=matrix`): **削除**（グラフ画面内の標準機能として内包済み）
   - `navGaps`: リンク先を `/dashboard.html?q=gaps` に変更し、表示名を「⚡ リサーチギャップ探索 ↗」に更新
   - `navRules` (`view=rules`): **削除**（グラフ画面内の推論エッジフィルタとして内包済み）
3. **Accordion Group 3: システム運用 & 監査 (Operations)**:
   - `navSystem` (`#/system`): システム観測 & パイプライン (維持)
   - `navDatabase` (`#/database`): データベース & ストレージ (維持)
   - `navSupervisor` (`#/supervisor`): プロセス監視 (Supervisor Top) (維持)
   - `navSpider` (`#/spiders`): スパイダー自律実行 & 監視 (維持)
   - `navMcp` (`#/mcp`): MCP ツールサンドボックス (維持)
   - `navTelemetry` (`/dashboard.html?tab=telemetry`): **削除**（死にリンク排除、`#/system` に統合済み）
   - `navLogs` (`/dashboard.html?tab=supervisor`): **削除**（`#/supervisor` への重複・循環リダイレクト排除）
4. **システム情報バナー (`systemInfoBanner`) の動線改善**:
   - `<a href="/dashboard.html?tab=supervisor" class="banner-link">更新ログを確認 ↗</a>` を `<a href="#/supervisor" class="banner-link" data-tab="supervisorTab">更新ログを確認</a>` に修正し、同一ページ内の高速SPA遷移を実現。

### Step 2: `site/dashboard.html` のディープリンク・クエリパラメータハンドラ強化
1. `initTabFromUrl()` を以下のように改修:
   ```javascript
   function initTabFromUrl() {
     try {
       const params = new URLSearchParams(window.location.search);
       const tabParam = params.get('tab') || window.location.hash.replace('#', '');
       if (tabParam && tabParam !== 'graph') {
         window.switchDashboardTab(tabParam, false);
       }
       const qParam = params.get('q');
       if (qParam && typeof window.openGraphWithQuery === 'function') {
         window.openGraphWithQuery(qParam.trim());
       }
     } catch (e) { }
   }
   ```
2. `window.openGraphWithQuery` の引数受け渡し確認:
   - `executeGraphQuery(query)` を明示的に引数渡しして即時実行可能にする。

### Step 3: 単体・UIテストコードの更新と新規アサーションの追加
1. `tests/web/test_enterprise_console_ui.py`:
   - `test_enterprise_console_html_structure()` 内のアサーションを改修。
   - 削除対象 ID（`navTelemetry`, `navLogs`, `navMatrix`, `navRules`）が `site/index.html` に含まれないことを `assert 'id="navTelemetry"' not in content` 等で厳格に担保。
   - 残存対象 ID（`navSearch`, `navTrends`, `navProduct`, `navGraph`, `navGaps`, `navSystem`, `navDatabase`, `navSupervisor`, `navSpider`, `navMcp`）がすべて存在することを検証。
   - `navGaps` のリンクが `/dashboard.html?q=gaps` であることを検証。
   - `systemInfoBanner` のリンクが `#/supervisor` であることの検証を追加。
   - 新規テスト `test_dashboard_url_query_param_support()` を追加し、`dashboard.html` のクエリパラメータ解釈ロジックの存在を検証。

### Step 4: 静的解析・品質ゲートの検証
- `make check_format`
- `make static_analysis` (flake8, mypy, xenon)
- `.venv/bin/pytest tests/web/test_enterprise_console_ui.py`
- `.venv/bin/pytest tests/`

---

## 6. テスト計画と検証シナリオ / Test Plan & Verification Scenarios

### 自動テスト (Automated Verification)
1. `.venv/bin/pytest tests/web/test_enterprise_console_ui.py`:
   - ナビゲーションリンク構成、削除済み死にリンクの不在確認、クエリパラメータ連携の単体テストがすべて PASS すること。
2. `make static_analysis`:
   - flake8, mypy, xenon 等の静的解析がすべてエラー 0 件で通過すること。

### 手動・ブラウザ検証 (Manual Verification)
1. **サイドバー各リンクの動作確認**:
   - `site/index.html` を開き、Accordion Group 1〜3 のリンクを展開・クリックして、指定のSPAタブまたは `/dashboard.html` へ正確に遷移することを確認。
   - `navGaps`（⚡ リサーチギャップ探索 ↗）をクリックし、ブラウザで `/dashboard.html?q=gaps` が開き、検索バーに `gaps` が入力され自動実行されることを確認。
2. **システム情報バナーリンクの動作確認**:
   - 「更新ログを確認」リンクをクリックした際、ページ再読み込みが発生せず、SPA内部で `#/supervisor`（Supervisor Top タブ）へ瞬時に切り替わることを確認。
3. **循環リダイレクト・死にリンクの根脱確認**:
   - 開発者ツール (Network / Console タブ) で無駄な 302/リダイレクトや 404/エラーが発生しないことを確認。

---

## 7. 完了条件 / Success Criteria (DoD)

- [x] `site/index.html` のサイドバーから `/dashboard.html?tab=telemetry`（死にリンク）が完全削除されていること。
- [x] `site/index.html` のサイドバーから `/dashboard.html?tab=supervisor`（循環リダイレクト）が完全削除されていること。
- [x] `site/index.html` のサイドバーから `view=matrix` および `view=rules`（未解釈パラメータ重複リンク）が完全削除されていること。
- [x] `site/index.html` のサイドバー項目が 10 項目に整理され、Accordion Group 1〜3 の分類が明確であること。
- [x] `systemInfoBanner` 内の更新ログリンクが `#/supervisor`（内部SPA遷移）に修正されていること。
- [x] `site/dashboard.html` が URL パラメータ `?q=...` を解釈し、起動時に `openGraphWithQuery` を通じてグラフクエリを安全に自動実行できること。
- [x] `tests/web/test_enterprise_console_ui.py` のテストケースが更新され、新旧仕様の整合性が自動検証されていること。
- [x] `make check_format`、`make static_analysis`、および関連テストが 100% PASS すること。
