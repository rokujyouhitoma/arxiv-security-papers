---
ID: 105
種別: Feature
優先度: High
ステータス: Closed
---

# [FEAT/ENH] ドメイン層（セキュリティ論文等）と再利用可能基盤層（DB・Crawler・Search・Graph等）の明確なレイヤー・パッケージ分離 (ID: 105)

## 1. 概要 / Summary
当プロジェクトは元々「arXiv セキュリティ論文の収集・解析」を主目的として開始され、その過程でデータベース基盤（`src/database`）、クローラー・スパイダー基盤（`src/spider`）、検索エンジン基盤（`src/search`）、グラフデータベース・知識グラフ基盤（`src/graph`）、ワークフローエンジン（`src/workflow`）、プロセススーパーバイザー（`src/supervisor`）、オブザーバビリティ（`src/observability`）などの高度な再利用可能基盤が開発・蓄積されてきた。

第1段階の `src/domain/` パッケージおよび `SpiderRegistry` / `DomainRegistry` SPI の新設に続き、第2段階として各基盤層内部（`src/spider/`, `src/database/`, `src/search/`, `src/observability/`）に残存していたセキュリティ論文固有のコード（固定DB名、ドメインスパイダー直配置、固定User-Agent、内部`paper`キー命名など）を完全に汎用化し、ドメイン層（`src/domain/security/`）への完全集約・分離を完遂した。

---

## 2. トレーサビリティ / Traceability
- 全体高位アーキテクチャ設計書 (`docs/designs/DSN-01_overall_architecture.md`)
- パッケージ設計原則 (`docs/designs/DSN-14_package_architecture.md`, クリーンアーキテクチャ・DDD)
- `.agents/AGENTS.md` (Systems Architect, PM, Database Specialist, IT Strategist, Systems Auditor)
- `.agents/skills/refine-existing-feature/SKILL.md`
- `.agents/skills/verify-quality-gates/SKILL.md`

---

## 3. 残存箇所の完全解消タスク

### A. `src/spider/` (クローラー基盤層)
- [x] スパイダー実体（`ArxivSpider`, `IacrSpider`, `AdvisorySpider`）を `src/domain/security/spiders/` に完全移管。`src/spider/spiders/` からは後方互換用エイリアスとして re-export。
- [x] `src/spider/runner.py` の固定インポートを撤廃し、`SpiderRegistry` から動的ディスパッチに変更。
- [x] デフォルト User-Agent（`ArXivSecuritySpider/1.0`）を汎用名 `GenericSpiderBot/1.0` に変更。

### B. `src/database/` (DB基盤層)
- [x] `src/database/sql/executor.py` (L928) の `arxiv_security_db` ハードコードを動的データベース名（`default_db` / `main`）に汎用化。
- [x] `src/database/__init__.py` の docstring を汎用分散DBエンジン記述に更新。

### C. `src/search/` (検索基盤層)
- [x] `src/search/server/service.py` の内部ハンドラーを `_handle_get_document` / `get_document` に統一し、返却キーを汎用化（`get_paper` は後方互換対応）。
- [x] `src/search/ranking/` の変数・型注釈・docstring を汎用 `Document` / `Entity` に整理。

### D. `src/observability/` (オブザーバビリティ基盤層)
- [x] `src/observability/` 内のデフォルト `service_name` / `instrumentation_name`（`arxiv-security-papers`）を汎用デフォルト（`app-service`）に変更し、環境変数 `OTEL_SERVICE_NAME` でドメイン側から注入可能にする。

---

## 4. 完了条件 / Success Criteria (DoD)
- [x] 基盤層（`src/database`, `src/spider`, `src/search`, `src/graph`, `src/workflow`, `src/supervisor`, `src/observability`）からドメイン固有のハードコード（`arxiv_security_db`, `ArXivSecuritySpider`, ドメインクローラー直配置）が完全に排除されていること。
- [x] `make check_format`、`make py_compile`、`make static_analysis` (Xenon 100% Rank A) が 100% PASS すること。
- [x] 全ユニットテスト・統合テスト（全 580 件）が 100% PASS すること。


