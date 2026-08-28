---
ID: 105
種別: Feature
優先度: High
ステータス: Open (New)
---

# [FEAT/ENH] ドメイン層（セキュリティ論文等）と再利用可能基盤層（DB・Crawler・Search・Graph等）の明確なレイヤー・パッケージ分離 (ID: 105)

## 1. 概要 / Summary
当プロジェクトは元々「arXiv セキュリティ論文の収集・解析」に注力して開始され、その過程でデータベース基盤（`src/database`）、クローラー・スパイダー基盤（`src/spider`）、検索エンジン基盤（`src/search`）、グラフデータベース・知識グラフ基盤（`src/graph`）、ワークフローエンジン（`src/workflow`）、プロセススーパーバイザー（`src/supervisor`）、オブザーバビリティ（`src/observability`）などの高度な再利用可能基盤が整理・実装されてきた。

しかし現在、基盤パッケージの中にセキュリティ論文固有のスキーマやビジネスロジック（ドメイン知識）が混在・結合している箇所が存在する。今後、対象ドメインの拡充（暗号、AI安全性、ハードウェアセキュリティ、他学術・技術領域など）や基盤自体の独立した再利用・品質向上（研ぎ澄まし）を可能にするため、ドメイン層（Domain）と汎用基盤層（Infrastructure / Core Platforms）の境界とインターフェースを厳格に線引きし、パッケージ・レイヤー構成を明確に分離・再編する。

---

## 2. トレーサビリティ / Traceability
- 全体高位アーキテクチャ設計書 (`docs/designs/DSN-01_overall_architecture.md`)
- パッケージ設計原則 (`docs/designs/DSN-14_package_architecture.md`, クリーンアーキテクチャ・DDD)
- `.agents/AGENTS.md` (Systems Architect, PM, Database Specialist, IT Strategist)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] `src/` 配下のパッケージ構造
  - **再利用可能基盤層 (Infrastructure / Platform / Core)**:
    - `src/database/` (純粋なストレージ・SQL・トランザクション・分散DB)
    - `src/spider/` (汎用分散クローラー基盤)
    - `src/search/` (汎用ハイブリッド・ベクトル検索基盤)
    - `src/graph/` (汎用プロパティグラフストレージ・Cypherクエリ・GraphRAG基盤)
    - `src/workflow/` (汎用ストリーミング DAG・ワークフローエンジン)
    - `src/supervisor/` (汎用プロセススーパーバイザー)
    - `src/observability/` (分散トレーシング・メトリクス)
  - **ドメイン層 (Domain / Applications / Plugins)**:
    - `src/domain/` (または `src/domains/security_papers/` 等、arXivセキュリティ論文固有のスキーマ、OKF変換、要約抽出、オントロジー、PIR定義)
    - `src/pipeline/` (ドメインと基盤を繋ぐETLパイプライン)
- [ ] `tests/` 配下のテスト構造（基盤単体テストとドメイン統合テストの分離）
- [ ] `Makefile` および各種 CLI エントリポイント

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/105-decouple-domain-and-infrastructure-layers`

1. **アーキテクチャ境界とレイヤー定義の設計**:
   - 基盤層（Infrastructure/Platform）からドメイン依存（arXiv/セキュリティ論文固有ロジック）を完全に排除し、抽象インターフェース・依存性逆転（DIP）を適用。
   - ドメイン層（`src/domains/` 等）にセキュリティ論文特有のデータモデル、プロンプト、変換ロジック、脅威オントロジーを集約。
2. **基盤モジュールの純粋化・抽象化**:
   - `src/database`、`src/spider`、`src/search`、`src/graph` 等が特定ドメインに依存せず、任意のドメインスキーマ・アダプター・ノード/エッジ定義を受け入れられるプラグイン構造へ整理。
3. **ドメインパッケージの独立配置**:
   - arXiv セキュリティ論文ドメインを明確な独立サブパッケージとして再編。
   - 新規ドメイン追加時のプラガブルな拡張ポイント（SPI: Service Provider Interface）を確立。
4. **テスト・品質ゲートの検証**:
   - `make check_format`、`make static_analysis`、`make test` を実行し、循環依存のないレイヤー構造を保証。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] 汎用基盤層（DB, Spider, Search, Graph, Workflow, Supervisor等）からドメイン固有のハードコード依存が完全に排除されていること。
- [ ] ドメイン固有ロジック（セキュリティ論文パイプライン・モデル等）が明確なドメインレイヤー・パッケージとして分離されていること。
- [ ] 新規ドメインをプラグイン形式で追加可能なアーキテクチャ設計・インターフェースが確立されていること。
- [ ] 全ユニットテストおよび静的解析（`make verify_quality` / `make check`）が 100% PASS すること。
