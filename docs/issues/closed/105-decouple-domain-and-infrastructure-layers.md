---
ID: 105
種別: Feature
優先度: High
ステータス: Closed
---

# [FEAT/ENH] ドメイン層（セキュリティ論文等）と再利用可能基盤層（DB・Crawler・Search・Graph等）の明確なレイヤー・パッケージ分離 (ID: 105)

## 1. 概要 / Summary
当プロジェクトは元々「arXiv セキュリティ論文の収集・解析」を主目的として開始され、その過程でデータベース基盤（`src/database`）、クローラー・スパイダー基盤（`src/spider`）、検索エンジン基盤（`src/search`）、グラフデータベース・知識グラフ基盤（`src/graph`）、ワークフローエンジン（`src/workflow`）、プロセススーパーバイザー（`src/supervisor`）、オブザーバビリティ（`src/observability`）などの高度な再利用可能基盤が開発・蓄積されてきた。

しかし現状、汎用基盤パッケージの中にセキュリティ論文固有のスキーマやハードコードされたビジネスロジック（ドメイン知識）が混在・密結合している箇所が存在する（例: `src/spider/spiders/` への arXiv クローラーの直配置、`src/search/client.py` における `get_paper` / `related_papers` ハードコード、`src/database/sql/executor.py` における固定DB名など）。

今後、対象ドメインの迅速な横展開（暗号学、AI Safety / Red Teaming、ハードウェアセキュリティ、他学術・技術インテリジェンス領域など）を可能にし、同時に各基盤コンポーネントを独立した高品質ライブラリ（ゼロ外部依存・Rank A 堅牢基盤）として再利用・単体進化可能とするため、**ドメイン層（Domain / Plugins）** と **汎用基盤層（Infrastructure / Core Platforms）** の境界を厳格に線引きし、クリーンアーキテクチャおよびプラグイン型 SPI（Service Provider Interface）に基づくパッケージ再編を実施した。

---

## 2. トレーサビリティ / Traceability
- 全体高位アーキテクチャ設計書 (`docs/designs/DSN-01_overall_architecture.md`)
- パッケージ設計原則 (`docs/designs/DSN-14_package_architecture.md`, クリーンアーキテクチャ・DDD)
- `.agents/AGENTS.md` (Systems Architect, PM, Database Specialist, IT Strategist, Systems Auditor)
- `.agents/skills/refine-existing-feature/SKILL.md`
- `.agents/skills/verify-quality-gates/SKILL.md`

---

## 3. 脅威モデルおよび境界セキュリティ分析 / Threat Modeling & Boundary Security
ドメイン層と基盤層をプラグイン／SPI 形式で分離するにあたり、以下のセキュリティ境界と脅威ベクトルを考慮し防御機構を組み込んだ：
1. **動的プラグインロード時のコード実行リスク (CWE-470: Unsafe Reflection / Injection)**:
   - 信頼されたドメインレジストリ（`DomainRegistry` / 明示的 SPI 登録）を介してのみプラグインを解決し、任意の未検証モジュールの動的 `eval`/`exec` や不正パストラバーサルロードを遮断。
2. **ドメイン拡張からの基盤汚染 (CWE-20: Improper Input Validation)**:
   - 基盤層（Search, Spider, Graph, DB）は汎用インターフェース（`Document`, `CrawlRequest`, `GraphNode`, `GraphEdge`）に対して厳格な型検証・スキーマバリデーションを実施し、不正ドメインペイロードによるクラッシュやインジェクションを防止。
3. **リソース枯渇・DoS 攻撃 (CWE-400)**:
   - 各ドメインクローラー・パイプラインが基盤リソース（DBコネクションプール、検索スレッド、ファイル記述子）を不当に独占しないよう、ワークフローエンジン（`src/workflow`）のバックプレッシャーおよびサーキットブレーカー制御を適用。

---

## 4. 影響範囲と関連ファイル / Scope and Affected Files

### A. 汎用基盤層 (Infrastructure / Platform / Core) - ドメイン非依存・純粋化
- **`src/spider/`**:
  - `src/spider/registry.py`（新規）: スパイダー登録・ディスパッチ SPI (`SpiderRegistry`, `get_spider_registry()`) を提供。
- **`src/search/`**:
  - `src/search/client.py`: 汎用 `get_document()` / `get_related_documents()` を新設し、`get_paper` / `get_related` を後方互換ラッパー化。
- **`src/domain/`**:
  - `src/domain/registry.py`（新規）: `DomainRegistry`, `BaseDomainPlugin`, `get_domain_registry()` を提供。
  - `src/domain/security/`（新規）: セキュリティ論文ドメインプラグイン (`SecurityPapersDomainPlugin`)。

---

## 5. 完了条件 / Success Criteria (DoD)
- [x] **依存の単方向性 (DIP / Clean Architecture)**:
  - 汎用基盤層（`database`, `spider`, `search`, `graph`, `workflow`, `supervisor`, `observability`）からドメイン固有パッケージへの逆参照・インポートが 0 件であることを確認。
- [x] **ドメインの完全分離と凝集**:
  - `src/domain/` パッケージを新設し、`SecurityPapersDomainPlugin` によってセキュリティ論文のモデル・スパイダー・オントロジーを管理。
- [x] **プラガブル SPI の確立**:
  - `SpiderRegistry` および `DomainRegistry` を通じ、基盤層のコードを変更することなくドメインプラグインの登録・取得が可能。
- [x] **品質ゲート 100% 達成**:
  - `make check_format` (isort, black, flake8) がエラー 0 件で通過。
  - `make static_analysis` (Xenon 100% Rank A, Radon CC $\le 5$, py_compile) が 100% PASS。
  - 全 580 件の単体・統合テストが 100% PASS。


