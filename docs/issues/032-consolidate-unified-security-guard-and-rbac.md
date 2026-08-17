---
ID: 032
種別: Feature / Security
優先度: Medium
ステータス: Open (New)
---

# [FEAT/ENH] 共通セキュリティ＆コンプライアンス基盤（`src/security/`）の独立集約 (ID: 032)

## 1. 概要 / Summary

現在、AST 静的解析ガード（`src/mcp/security_guard.py`）、SQL 3層 RBAC 権限制御（`src/database/sql/security.py`）、Web パストラバーサル防御（`src/web/web_server.py`）、および MITRE ATT&CK / STRIDE 脅威分類ロジックが各パッケージに分散しています。

本 Issue では、これらを **`src/security/`** に一元化し、システム全体のセキュリティポリシーにおける単一信頼源（SSOT: Single Source of Truth）を確立します。

```
src/security/
├── __init__.py
├── sandbox/          # AST 静的解析ガード、危険関数・リフレクション遮断
├── rbac/             # 統合 RBAC ロール・権限判定 (Database / Web / MCP 共通)
├── taxonomy/         # MITRE ATT&CK, STRIDE, CWE 辞書・脅威モデリング
└── validation/       # パストラバーサル防止、ワークスペース境界検証、入力サニタイズ
```

---

## 2. トレーサビリティ / Traceability

- 関連資料:
  - [DSN-11-mcp-security-hardening.md](../designs/DSN-11-mcp-security-hardening.md)
  - [AGENTS.md](../../.agents/AGENTS.md) (情報セキュリティ専門家・システム監査人ガイドライン)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files

- [ ] `src/security/sandbox/` (AST ガードロジックの抽出)
- [ ] `src/security/rbac/` (Database, MCP, Web 共通のロール・アクセスポリシー)
- [ ] `src/security/taxonomy/` (MITRE ATT&CK, STRIDE, CWE 辞書)
- [ ] `src/security/validation/` (安全なファイルパス境界判定・サニタイズ)
- [ ] [src/mcp/security_guard.py](../../src/mcp/security_guard.py) (リファクタリング)
- [ ] [src/database/sql/security.py](../../src/database/sql/security.py) (リファクタリング)
- [ ] [src/web/web_server.py](../../src/web/web_server.py) (リファクタリング)
- [ ] `tests/security/` (新規セキュリティテストスイート)

---

## 4. 実装方針 / Implementation Plan

Target Branch: `feat/032-consolidate-unified-security-framework`

1. **`src/security/` パッケージの新設**:
   - `sandbox`, `rbac`, `taxonomy`, `validation` の 4 つのサブモジュールを定義。
2. **AST ガードとパストラバーサルの集約**:
   - MCP および Web サーバーで重複していた安全パス検証ロジック（`is_safe_workspace_path`）と AST サンドボックス判定を `src/security/` に統合。
3. **統一 RBAC エンジンの構築**:
   - Database SQL 操作だけでなく、MCP ツール呼び出し（`admin` のみ実行可能なデバッグツール等）や Web API エンドポイントにも適用可能な共通 RBAC デコレータ / 判定クラスを提供。
4. **テストスイートの集約**:
   - `tests/security/` を新設し、OWASP Top 10 やパストラバーサル、悪意あるコード実行に対する防御テストを一元的に管理。

---

## 5. 完了条件 / Success Criteria (DoD)

- [ ] `src/security/` に AST ガード、共通 RBAC、パストラバーサル検証、MITRE 辞書が集約されていること
- [ ] `src/mcp/`, `src/database/`, `src/web/` から `src/security/` の共通モジュールがインポート・利用されていること
- [ ] `tests/security/` 下に網羅的なセキュリティ回帰テストが構築され、100% PASS すること
- [ ] `make test`, `make static_analysis` がエラー 0 件で通過すること
