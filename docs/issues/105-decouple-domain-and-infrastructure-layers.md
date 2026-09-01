---
ID: 105
種別: Feature
優先度: High
ステータス: Open (In Progress)
---

# [FEAT/ENH] ドメイン層（セキュリティ論文等）と再利用可能基盤層（DB・Crawler・Search・Graph等）の明確なレイヤー・パッケージ分離 (ID: 105)

## 1. 概要 / Summary
当プロジェクトは元々「arXiv セキュリティ論文の収集・解析」を主目的として開始され、その過程でデータベース基盤（`src/database`）、クローラー・スパイダー基盤（`src/spider`）、検索エンジン基盤（`src/search`）、グラフデータベース・知識グラフ基盤（`src/graph`）、ワークフローエンジン（`src/workflow`）、プロセススーパーバイザー（`src/supervisor`）、オブザーバビリティ（`src/observability`）などの高度な再利用可能基盤が開発・蓄積されてきた。

しかし現状、汎用基盤パッケージの中にセキュリティ論文固有のスキーマやハードコードされたビジネスロジック（ドメイン知識）が混在・密結合している箇所が存在する（例: `src/spider/spiders/` への arXiv クローラーの直配置、`src/search/client.py` における `get_paper` / `related_papers` ハードコード、`src/database/sql/executor.py` における固定DB名など）。

今後、対象ドメインの迅速な横展開（暗号学、AI Safety / Red Teaming、ハードウェアセキュリティ、他学術・技術インテリジェンス領域など）を可能にし、同時に各基盤コンポーネントを独立した高品質ライブラリ（ゼロ外部依存・Rank A 堅牢基盤）として再利用・単体進化可能とするため、**ドメイン層（Domain / Plugins）** と **汎用基盤層（Infrastructure / Core Platforms）** の境界を厳格に線引きし、クリーンアーキテクチャおよびプラグイン型 SPI（Service Provider Interface）に基づくパッケージ再編を実施する。

---

## 2. トレーサビリティ / Traceability
- 全体高位アーキテクチャ設計書 (`docs/designs/DSN-01_overall_architecture.md`)
- パッケージ設計原則 (`docs/designs/DSN-14_package_architecture.md`, クリーンアーキテクチャ・DDD)
- `.agents/AGENTS.md` (Systems Architect, PM, Database Specialist, IT Strategist, Systems Auditor)
- `.agents/skills/refine-existing-feature/SKILL.md`
- `.agents/skills/verify-quality-gates/SKILL.md`

---

## 3. 脅威モデルおよび境界セキュリティ分析 / Threat Modeling & Boundary Security
ドメイン層と基盤層をプラグイン／SPI 形式で分離するにあたり、以下のセキュリティ境界と脅威ベクトルを考慮し防御機構を組み込む：
1. **動的プラグインロード時のコード実行リスク (CWE-470: Unsafe Reflection / Injection)**:
   - 信頼されたドメインレジストリ（`DomainRegistry` / 明示的 SPI 登録）を介してのみプラグインを解決し、任意の未検証モジュールの動的 `eval`/`exec` や不正パストラバーサルロードを遮断。
2. **ドメイン拡張からの基盤汚染 (CWE-20: Improper Input Validation)**:
   - 基盤層（Search, Spider, Graph, DB）は汎用インターフェース（`Document`, `CrawlRequest`, `GraphNode`, `GraphEdge`）に対して厳格な型検証・スキーマバリデーションを実施し、不正ドメインペイロードによるクラッシュやインジェクションを防止。
3. **リソース枯渇・DoS 攻撃 (CWE-400)**:
   - 各ドメインクローラー・パイプラインが基盤リソース（DBコネクションプール、検索スレッド、ファイル記述子）を不当に独占しないよう、ワークフローエンジン（`src/workflow`）のバックプレッシャーおよびサーキットブレーカー制御を適用。

---

## 4. 影響範囲と関連ファイル / Scope and Affected Files

### A. 汎用基盤層 (Infrastructure / Platform / Core) - ドメイン非依存・純粋化
- **`src/database/`**:
  - 純粋なリレーショナル・ベクトル・列指向・分散DBエンジン。
  - `src/database/sql/executor.py`: 固定DB名（`arxiv_security_db` 等）の排除、動的設定化。
- **`src/spider/`**:
  - 汎用分散Webクローラー・スパイダー基盤。
  - `src/spider/spiders/arxiv_spider.py`、`advisory_spider.py` をドメイン層へ移管。
  - `src/spider/registry.py`（新規）: スパイダー登録・ディスパッチ SPI を提供。
- **`src/search/`**:
  - 汎用ハイブリッド・ファセット・ベクトル検索基盤。
  - `src/search/client.py`, `src/search/server/service.py`: `get_paper` 等のドメイン固定コマンドを汎用 `get_document` / `get_related` に抽象化し、ドメイン固有別名をアダプター化。
- **`src/graph/`**:
  - 汎用プロパティグラフストレージ・GraphRAG エンジン。
- **`src/workflow/`**:
  - 汎用ストリーミング DAG・Saga 分散トランザクションエンジン。
- **`src/supervisor/`**:
  - 汎用 Pre-Fork プロセススーパーバイザー。
- **`src/observability/`**:
  - 汎用 OpenTelemetry / OpenInference 分散トレーシング基盤。

### B. ドメイン層 (Domain / Business Logic / Plugins)
- **`src/domain/` (または `src/domains/security_papers/`)**:
  - **`models/`**: Google OKF v0.2 Paper、Metadata、Threat Taxonomy (MITRE ATT&CK, NIST SP 800, CWE/CVE)
  - **`spiders/`**: `ArxivSecuritySpider`, `IacrAdvisorySpider` (基盤 `BaseSpider` を実装)
  - **`extractors/`**: `SecurityPDFExtractor`, `BilingualSecurityAnalyzer`, `ThreatModelTagger`
  - **`ontology/`**: SKO (Security Knowledge Ontology) マッピングルール
  - **`intelligence/`**: PIR 3-Horizon 管理、Hypothesis Engine、Credibility Engine、Synthesizer
  - **`mcp/`**: `PapersMCPServer`, `TechRadarMCPServer`, `ThreatDefenseMCPServer`
- **`src/pipeline/`**:
  - セキュリティ論文ドメインと各種基盤エンジンを結合・オーケストレーションする ETL パイプライン。

### C. テスト構造と CLI / ツール群
- **`tests/`**:
  - `tests/unit/`: 基盤コンポーネントの単体テスト（ドメイン非依存）
  - `tests/domain/`: セキュリティ論文ドメインのモデル・抽出・クローラーテスト
  - `tests/integration/`: エンドツーエンド統合シナリオテスト
- **`Makefile`**:
  - 新規パッケージ構成に対応したテスト・静的解析ターゲットの調整。

---

## 5. 実装方針 / Implementation Plan
Target Branch: `feat/105-decouple-domain-and-infrastructure-layers`

### Phase 1: SPI（Service Provider Interface）基盤の設計と登録機構の整備
1. `src/spider/registry.py` を整備し、外部ドメインが自作スパイダーを登録・実行できるプラグイン構造を導入。
2. `src/search/` の API を汎用 `Document` ベースに統一し、ドメイン依存のコマンド命名（`paper`）を汎用エンティティモデル（`document` / `entity`）へリファクタリング。
3. `src/database/` 内の固定文字列やドメイン依存の痕跡を完全に除去。

### Phase 2: ドメインパッケージ構造の確立とセキュリティ論文ロジックの集約
1. `src/domain/`（または `src/domains/security_papers/`）パッケージを新設。
2. 以下のモジュール群をドメイン層へ集約・移行：
   - スパイダー: `src/spider/spiders/` → `src/domain/security_papers/spiders/`
   - オントロジー・スキーマ: `src/ontology/` → `src/domain/security_papers/ontology/`
   - インテリジェンス・PIR: `src/intelligence/` → `src/domain/security_papers/intelligence/`
   - 論文変換・要約・OKF: `src/pipeline/transformer/` → `src/domain/security_papers/transformers/`
   - 特化 MCP: `src/mcp/` のドメインツール群をドメイン層のファサードとして整理。
3. 基盤層へのインポートは「ドメイン層 → 基盤層」の一方向のみとし、基盤層からドメイン層への逆インポート（循環依存）を完全に禁止。

### Phase 3: パイプライン・CLI・上位レイヤーの統合
1. `src/pipeline/arxiv_okf_fetcher.py` および `src/intelligence/cli.py` が新ドメインパッケージおよび基盤 SPI を利用して透過的に動作するよう配線。
2. 後方互換性エイリアスを配置し、既存のコマンド（`make run`, `make pipeline`, `make rag_query` 等）の実行互換性を維持。

### Phase 4: 品質ゲート・テストスイートの全面検証
1. `make format` (isort, black, flake8) を実行し、コードスタイルを適合。
2. `make static_analysis` (xenon Grade A, radon CC <= 5, mypy --strict, py_compile) を実行し、全モジュールの品質基準をクリア。
3. `make test` / `pytest` を実行し、全単体・統合テストが 100% PASS することを確認。

---

## 6. 完了条件 / Success Criteria (DoD)
- [ ] **依存の単方向性 (DIP / Clean Architecture)**:
  - 汎用基盤層（`database`, `spider`, `search`, `graph`, `workflow`, `supervisor`, `observability`）からドメイン固有パッケージ（`domain/`）への逆参照・インポートが 0 件であること。
- [ ] **ドメインの完全分離と凝集**:
  - arXiv セキュリティ論文固有のクローラー、オントロジー、OKF 変換、PIR・仮説検証ロジックが `src/domain/` 配下に整然と集約されていること。
- [ ] **プラガブル SPI の確立**:
  - 新規ドメイン（例: `crypto_currency`, `ai_safety`）を追加する際、基盤層のコードを変更することなく、プラグイン登録のみでクローラー・検索・グラフ・分析パイプラインを拡張可能であること。
- [ ] **品質ゲート 100% 達成**:
  - `make check_format` (isort, black, flake8) がエラー 0 件で通過すること。
  - `make static_analysis` (Xenon 100% Rank A, Radon CC $\le 5$, mypy, py_compile) が 100% PASS すること。
  - 全ユニットテストおよび E2E シナリオテストが 100% PASS すること。

