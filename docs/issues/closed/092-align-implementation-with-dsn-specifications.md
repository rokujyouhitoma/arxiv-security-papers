---
ID: 092
種別: Feature
優先度: High
ステータス: Closed (Completed)
完了日: 2026-08-28
---

# [FEAT] DSN 包括的設計仕様に基づくシステム実装の見直しと機能強化 (ID: 092)

## 1. 概要 / Summary
最新の包括的アーキテクチャ設計書群（[DSN-01](../designs/DSN-01-high_level_design.md), [DSN-03](../designs/DSN-03-pipeline_architecture.md), [DSN-07](../designs/DSN-07-security_guard_and_rbac.md), [DSN-08](../designs/DSN-08-mcp_strategic_ecosystem.md), [DSN-16](../designs/DSN-16-nextgen_security_knowledge_platform_proposal.md) 等）で策定された仕様に基づき、システム実装（`src/` 配下）の機能・セキュリティ・脅威インテリジェンス連携を見直し、不足機能の追加と堅牢化を実施する。

---

## 2. トレーサビリティ / Traceability
- 関連設計書:
  - [DSN-01: 全体高位アーキテクチャ設計書](../designs/DSN-01-high_level_design.md)
  - [DSN-03: ETL データパイプライン包括設計書](../designs/DSN-03-pipeline_architecture.md)
  - [DSN-07: 共通セキュリティ基盤・AST ガード & RBAC エンジン設計書](../designs/DSN-07-security_guard_and_rbac.md)
  - [DSN-08: Model Context Protocol (MCP) 戦略的エコシステム設計書](../designs/DSN-08-mcp_strategic_ecosystem.md)
  - [DSN-16: 次世代セキュリティ・ナレッジプラットフォーム包括的設計提言書](../designs/DSN-16-nextgen_security_knowledge_platform_proposal.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [src/security/sandbox/ast_guard.py](../../src/security/sandbox/ast_guard.py) (PEP 594 遮断)
- [x] [src/security/validation/input.py](../../src/security/validation/input.py) (プロンプト隔離・検知)
- [x] [src/security/taxonomy/mitre.py](../../src/security/taxonomy/mitre.py) (Caldera/Sigma生成)
- [x] [src/security/taxonomy/__init__.py](../../src/security/taxonomy/__init__.py) (エクスポート更新)
- [x] [src/mcp/threat_defense_server.py](../../src/mcp/threat_defense_server.py) (ハンドラー登録)
- [x] [src/pipeline/transformer/tagger.py](../../src/pipeline/transformer/tagger.py) (数理モデルタグ付け)
- [x] [tests/security/test_ast_sandbox.py](../../tests/security/test_ast_sandbox.py) (単体テスト)
- [x] [tests/security/test_taxonomy.py](../../tests/security/test_taxonomy.py) (単体テスト)
- [x] [tests/mcp/test_mcp_server.py](../../tests/mcp/test_mcp_server.py) (MCPテスト)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/092-align-implementation-with-dsn-specifications`

1. **セキュリティ基盤・防御シールド強化 (`src/security/`)**:
   - `ast_guard.py`: PEP 594 レガシーモジュール統廃合（`cgi`, `pipes`, `crypt`, `asyncore`, `distutils`, `chunk` 等）の明示的遮断リスト追加
   - `input.py`: 間接的プロンプトインジェクション検知パターン追加および `<untrusted_paper_content>` 隔離ラッパー関数実装
   - `mitre.py`: Caldera 攻撃エミュレーション用プレイブック (YAML) 生成 (`generate_caldera_ability`) および SIEM Sigma ルール生成ドラフト (`generate_sigma_rule`) の実装
2. **MCP エコシステム強化 (`src/mcp/`)**:
   - `threat_defense_server.py`: `generate_caldera_playbook` および `generate_sigma_rule` ツールハンドラーを `TOOL_HANDLERS` に登録し、入出力スキーマ検証を実装
3. **トランスフォーマー層強化 (`src/pipeline/transformer/`)**:
   - `tagger.py`: DSN-03 数理モデル（$\text{ThreatScore}(T)$）に基づく重み付き脅威タグ付け（タイトル・アブストラクト重み 2.0、本文重み 1.0）
4. **テストスイート拡充 & 品質ゲート検証**:
   - `tests/security/test_ast_sandbox.py` に PEP 594 遮断テストを追加
   - `tests/security/test_taxonomy.py` に Caldera / Sigma 生成テストを追加
   - `tests/mcp/test_mcp_server.py` に新ツールの呼び出しテストを追加
   - `make check_format`, `make static_analysis`, `make test` を実行して 100% PASS を保証

---

## 5. 完了条件 / Success Criteria (DoD)
- [x] `ast_guard.py` で PEP 594 統廃合モジュールが確実に遮断されること
- [x] `input.py` でプロンプトインジェクション検知と `<untrusted_paper_content>` カプセル化が機能すること
- [x] `mitre.py` および `threat_defense_server.py` で Caldera プレイブックと Sigma ルールが正常に生成・提供されること
- [x] `tagger.py` で DSN-03 数理モデルに基づくタグ付けが行われること
- [x] 全テストおよび `make check_format`, `make static_analysis`, `make test` が 100% PASS すること

