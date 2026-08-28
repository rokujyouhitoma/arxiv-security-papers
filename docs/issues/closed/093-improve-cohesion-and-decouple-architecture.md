---
ID: 093
種別: Refactor
優先度: High
ステータス: Closed (Completed)
完了日: 2026-08-28
---

# [REFACTOR] システム全体の凝集度・モジュール強度向上および結合度低減に向けたリファクタリング (ID: 093)

## 1. 概要 / Summary
6層モジュールアーキテクチャ（[DSN-01](../designs/DSN-01-high_level_design.md) / [DSN-16](../designs/DSN-16-nextgen_security_knowledge_platform_proposal.md)）に基づき、各層・パッケージ内の機能的凝集度（Functional Cohesion）を高め、層間・モジュール間の結合度（Coupling）を最小化する包括的リファクタリングを実施した。

具象クラスへの直接的な密結合を `typing.Protocol` によるインターフェース分離（Interface Segregation）へ移行し、共通レスポンス構造の標準化およびプラグマティックな依存性注入（Dependency Injection）を導入した。

---

## 2. トレーサビリティ / Traceability
- 関連設計書:
  - [DSN-01: 全体高位アーキテクチャ設計書 (6層モジュール構造)](../designs/DSN-01-high_level_design.md)
  - [DSN-02: 全体低位アーキテクチャ設計書 (共通規約 & プロトコル)](../designs/DSN-02-low_level_design.md)
  - [DSN-08: Model Context Protocol (MCP) 戦略的エコシステム設計書](../designs/DSN-08-mcp_strategic_ecosystem.md)
  - [DSN-11: 閉ループ・ドメインインテリジェンス & 汎用ワークフロー包括設計書](../designs/DSN-11-intelligence_orchestration_engine.md)
  - [DSN-16: 次世代セキュリティ・ナレッジプラットフォーム包括的設計提言書](../designs/DSN-16-nextgen_security_knowledge_platform_proposal.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [src/intelligence/contracts.py](../../src/intelligence/contracts.py) (ドメインコンポーネント Protocol 定義)
- [x] [src/intelligence/engine.py](../../src/intelligence/engine.py) (プロトコル準拠 DI 対応)
- [x] [src/pipeline/transformer/tagger.py](../../src/pipeline/transformer/tagger.py) (タクソノミー抽出器の抽象化・DI)
- [x] [src/mcp/base.py](../../src/mcp/base.py) (共通レスポンス生成・テレメトリ凝集化)
- [x] [src/mcp/__init__.py](../../src/mcp/__init__.py) (共通レスポンスヘルパー公開)
- [x] [tests/intelligence/test_engine_e2e.py](../../tests/intelligence/test_engine_e2e.py) (プロトコル DI 検証)
- [x] [tests/mcp/test_mcp_base_coverage.py](../../tests/mcp/test_mcp_base_coverage.py) (MCP 共通基盤検証)
- [x] [tests/pipeline/test_transformer.py](../../tests/pipeline/test_transformer.py) (タグ付け DI 検証)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `refactor/093-improve-cohesion-and-decouple-architecture`

1. **ドメイン契約の抽象化・プロトコル分離 (`src/intelligence/contracts.py`)**:
   - `IntelligencePhaseProtocol`, `PIRManagerProtocol`, `CredibilityEngineProtocol`, `SynthesizerProtocol` 等の `@runtime_checkable` Protocol を定義し、各サブシステムの具象クラスへの密結合を排除。
2. **インテリジェンスエンジンの疎結合化 (`src/intelligence/engine.py`)**:
   - `IntelligenceEngine` のコンストラクタで各フェーズコーディネーターおよび PIR/信憑性/シンセサイザーのインスタンスを注入可能（DI）にし、モックテストやテーマ別差し替えを容易化。
3. **トランスフォーマー層とタクソノミー層の結合度低減 (`src/pipeline/transformer/tagger.py`)**:
   - `extract_mitre_and_stride` にオプショナルのカスタム抽出コールバック（`TaxonomyExtractorProtocol`）を受け取れるようにし、純粋なドメイン非依存データフローを確立。
4. **MCP サーバー群の凝集度向上 (`src/mcp/base.py` & 各サーバー)**:
   - `make_tool_response(data, error=None, meta=None)` ヘルパーを提供し、全 4 大 MCP サーバーの JSON-RPC レスポンス形式とテレメトリ記録を一元化。
5. **テストスイート拡充 & トリプル品質ゲート検証**:
   - プロトコル適合性テスト・DI テストを追加し、`make check` (`make check_format`, `make static_analysis`, `make test`) の 100% PASS を保証。

---

## 5. 完了条件 / Success Criteria (DoD)
- [x] `src/intelligence/contracts.py` で主要コンポーネントが `Protocol` 契約として定義されていること
- [x] `IntelligenceEngine` がプロトコル準拠の DI 構造を受け入れ可能であること
- [x] `src/mcp/base.py` で共通レスポンス構造が標準化され、各 MCP サーバーで利用されていること
- [x] `tagger.py` が疎結合にタクソノミー抽出器を受け入れ可能であること
- [x] 全テストおよび `make check_format`, `make static_analysis`, `make test` が 100% PASS すること


