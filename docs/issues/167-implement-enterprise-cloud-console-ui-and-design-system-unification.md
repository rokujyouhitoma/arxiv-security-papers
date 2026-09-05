---
ID: 167
種別: Feature
優先度: High
ステータス: Open (New)
---

# [FEAT/UIUX] エンタープライズSaaS型統合クラウドコンソール UI およびデザインシステムの統一実装 (ID: 167)

## 1. 概要 / Summary
現在、セマンティック全文検索・トレンド・MCPサンドボックスを提供する **検索ポータル (`site/index.html`)** と、リアルタイム CTI ナレッジグラフ・システムテレメトリ・プロセス監査を提供する **運用ダッシュボード (`site/dashboard.html`)** の 2 つの Web 画面が存在する。
しかし、両画面間でデザイン体系（ダーク・グラスモーフィズム vs スイス調レトロミニマリズム）が著しく乖離しており、セキュリティアナリストが論文検索から CTI グラフ探索・システム監視へと至る一連の調査ワークフローにおいて強い認知的摩擦が生じていた。

本 Issue では、包括設計書 **[DSN-21 (エンタープライズ統合デザインシステム ＆ クラウドコンソール UI 包括設計書)](../designs/DSN-21-enterprise_design_system_and_unified_console.md)** に基づき、**A案（完全統合 Single-Page Portal 化）** を大方針として、Azure / AWS 等のクラウド管理画面風のプロフェッショナルな **エンタープライズ SaaS 型統合コンソール UI** を構築する。

色合いについては、長時間の分析・監視業務において目への負担が少なく落ち着きのある **`dashboard.html` 側の Swiss / Warm Enterprise Palette（アースカラー基調: `#f4efe6`, `#ebe5d8`, `#2b2b2b`, `#3d5a80` 等）** をベースにテーラリングして全面統一する。

---

## 2. トレーサビリティ / Traceability
- **ユーザー要求**:
  - 「A案を大方針とし、以下をテーラリングし、実現してほしい。色合い等は自体は、dashboard.html側のほうが落ち着いてるので、一旦そのような方針でお願いしたい。 /create-issue と DSNの更新をお願いします。デザインに関する専用 DSN があってもよい。」
  - 「エンタープライズSaaS向けの管理画面（Azure/AWS等のクラウドコンソール風）のUIを作成してください。」
- **関連設計書**:
  - [DSN-21: エンタープライズ統合デザインシステム ＆ クラウドコンソール UI 包括設計書](../designs/DSN-21-enterprise_design_system_and_unified_console.md)
  - [DSN-09: API Gateway ＆ UI プレゼンテーション包括設計書](../designs/DSN-09-web_gateway_and_presentation.md)
  - [DSN-14: 論文・脅威ナレッジグラフ & エンジニアリングダッシュボード設計書](../designs/DSN-14-graph_engineering_dashboard.md)
  - [DSN-04: 2層検索エンジン & プラットフォーム設計書](../designs/DSN-04-search_engine_and_platform.md)
- **関連 Issue**:
  - Issue 166: /dashboard tab=graph における Glassmorphic ツールチップ・操作ガイド基盤の実装
  - Issue 164: /dashboard tab=graph におけるエッジ確信度＆推論ルール絞り込みフィルタとエビデンス表示
  - Issue 138: /dashboard 専用 Knowledge & CTI Graph 画面（`tab=graph`）の独立実装

---

## 3. 要求仕様詳細 / Detailed Requirements

### 【全体レイアウト】
- **固定グローバルヘッダー**: 画面最上部に固定（高さ 48px）
- **左サイドナビゲーションバー**: 幅固定（約 240〜280px、デフォルト 260px）、折りたたみ可能
- **メインコンテンツエリア**: 画面右側に配置されるスクロール可能なメインステージ（2ペイン構成）

### 【1. グローバルヘッダー】
- **左端**: プロダクト名／テナント名（例: `arXiv Security Intelligence | Enterprise Portal (cs.CR)`）
- **中央**: 幅広のグローバル検索バー（プレースホルダー: `論文ID、攻撃手法、脆弱性、キーワードをグローバル検索 (Ctrl+K)...`）
- **右端**: ユーティリティアイコン群（🔔 通知センター、⚙️ ポータル設定、❓ ガイド/ヘルプ、🟢 システム正常稼働バッジ）

### 【2. 左サイドバー（ナビゲーション）】
- **折りたたみ可能なアコーディオン階層メニュー**:
  - ▾ **探索・分析 (Analytics)**: 🔍 セマンティック RAG 検索、📊 トレンド & サマリー、🕸️ CTI ナレッジ網
  - ▾ **脅威インテリジェンス (Intelligence)**: 🛡️ ATT&CK / CWE マトリクス、⚡ リサーチギャップ、📜 推論ルール (EIROM)
  - ▾ **システム運用 (Operations)**: 📈 プロセス監視 & テレメトリ、🔌 MCP ツールサンドボックス、📑 システム監査ログ
- **選択中アイテムの視覚フィードバック**:
  - 左端にアクティブを示すアクセントカラーの縦棒（`3px solid var(--console-accent-navy)`）を表示

### 【3. メインコンテンツエリア (標準 5 大コンポーネント)】
1. **ページヘッダー**:
   - ページタイトル（`<h1>`）＋ 概要説明 ＋ 右上ボタングループ（`🔄 更新`, `⬇️ エクスポート`, `❓ ガイド` 等）
2. **インフォメーションバナー**:
   - 薄い背景色のアラート/お知らせコールアウト（`ℹ️` アイコン ＋ リンク付きメッセージ ＋ 左端アクセントカラーバー）
3. **KPIサマリーカード（統計メトリクス）**:
   - 左端にカラーバー（Blue/Green/Amber/Coral）の付いたメトリクスカード（ラベル ＋ 大フォント数値 ＋ 補足指標）を横並びグリッド配置
4. **検索＆フィルタリングバー**:
   - キーワード検索ボックス ＋ ドロップダウン/ピル型フィルター（カテゴリ、確信度、プロバイダー種別、トグルスイッチ）を 1 行にインライン配置
5. **データリスト／テーブル**:
   - リソース一覧表示（左端ステータスカラーバー、リソースアイコン、タイトル＋サブテキスト、属性列バッジ、右端三点リーダーアクションメニュー `⋮`）

---

## 4. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [docs/designs/DSN-21-enterprise_design_system_and_unified_console.md](../designs/DSN-21-enterprise_design_system_and_unified_console.md):
  - クラウドコンソール仕様・デザインシステム包括設計書（作成済み）
- [ ] [site/index.html](file:///workspace/arxiv-security-papers/site/index.html):
  - エンタープライズ SaaS クラウドコンソールレイアウトへの再構築（固定ヘッダー、左サイドバー、メインコンテンツ 5大コンポーネント）
- [ ] [site/style.css](file:///workspace/arxiv-security-papers/site/style.css):
  - Swiss / Warm Enterprise Palette のトークン定義、2ペインレイアウト、5大コンポーネント用スタイルの統合
- [ ] [site/app.js](file:///workspace/arxiv-security-papers/site/app.js):
  - アコーディオン開閉、サイドバー折りたたみ、ハッシュルーティング、グローバル検索連動
- [ ] [tests/web/test_dashboard_html.py](file:///workspace/arxiv-security-papers/tests/web/test_dashboard_html.py) / [tests/web/test_web_server.py](file:///workspace/arxiv-security-papers/tests/web/test_web_server.py):
  - コンソールシェル構造、グローバルヘッダー、サイドバー、5大コンポーネントのテスト追加

---

## 5. 実装方針 / Implementation Plan
Target Branch: `feat/167-enterprise-cloud-console-ui`

1. **フェーズ1: 共通 CSS トークン & 2ペインシェルの構築**:
   - `site/style.css` に `DSN-21` で規定した Swiss / Warm Enterprise Palette 変数群（`--console-bg-canvas`, `--console-accent-navy` 等）を配置。
   - 固定ヘッダー（48px）、左サイドバー（260px）、メインスクロールエリアの Flexbox / Grid レイアウトを実装。
2. **フェーズ2: ナビゲーション & アコーディオンインタラクション**:
   - 左サイドバーのアコーディオンメニュー、アクティブ縦棒インジケーター、折りたたみトグルを実装。
   - ハッシュルーティング (`#/search`, `#/trends`, `#/graph`, `#/telemetry`, `#/mcp`) によるスムーズなビュー切替。
3. **フェーズ3: メインコンテンツ標準 5 大コンポーネントの実装**:
   - ページヘッダー、インフォメーションバナー、左カラーバー付き KPI サマリーカード、インライン検索フィルタバー、リソースリストテーブル（三点リーダー付き）をコンポーネント化。
4. **フェーズ4: 検索画面とダッシュボード画面のコンポーネント結合**:
   - 検索・トレンド・MCP サンドボックスの各機能を新コンソール内で完全動作するように統合。
5. **フェーズ5: 品質ゲート検証**:
   - `make check_format`, `make static_analysis`, `make test` の完全合格。

---

## 6. 完了条件 / Success Criteria (DoD)
- [ ] 固定グローバルヘッダー（プロダクト/テナント名、幅広検索バー、ユーティリティアイコン）が実装されていること。
- [ ] 左サイドバー（幅 240〜280px）にアコーディオン階層メニューと選択中アクティブ縦棒インジケーターが配置されていること。
- [ ] メインエリアに標準 5 大コンポーネント（H1ヘッダー、インフォバナー、カラーバー付きKPIカード、インラインフィルタバー、リソースリストテーブル）が配置されていること。
- [ ] 色合いが `dashboard.html` 側の落ち着いたスイス調アースカラー（`#f4efe6`, `#ebe5d8`, `#2b2b2b`, `#3d5a80` 等）で美しくテーラリングされていること。
- [ ] 外部ライブラリ（Tailwind, React等）を追加せず、Vanilla CSS と Pure JavaScript のみで高速・セキュア（Zero-XSS）に構築されていること。
- [ ] `tests/web/` に統合コンソールの DOM 構造・レイアウト検証テストが追加されパスすること。
- [ ] `make check_format`, `make static_analysis`, `make test` の全品質ゲートを 100% PASS すること。
