---
ID: 131
種別: Feature
優先度: Medium
ステータス: Open (New)
---

# [FEAT/ENH] 学術知見からの動的防御シグネチャ（Semgrep / Sigma / YARA）自動生成とインメモリAST構文テスターの実装 (ID: 131)

## 1. 概要 / Summary
論文内で特定された脆弱な実装パターンや不適切な API 呼び出しに対し、検知ルール（Semgrep、YARA、Sigma ルール）を自動生成するシグネチャジェネレータを MCP ツールとして実装する。
生成されたルールは、Python 標準ライブラリの `ast` モジュール等を用いたインメモリ構文検証器によって構文エラーや過剰なバックトラックの有無を即座にテストし、構文的正当性と最小限のテストケース通過が保証されたルールのみを返却して低品質シグネチャの混入を防止する。

---

## 2. トレーサビリティ / Traceability
- [DSN-08: Model Context Protocol 戦略的エコシステム](../../docs/designs/DSN-08-mcp_strategic_ecosystem.md)
- [src/mcp/threat_defense_server.py](../../src/mcp/threat_defense_server.py)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] `src/mcp/tools/signature_generator.py`
- [ ] `src/mcp/tools/ast_rule_validator.py`
- [ ] `src/mcp/threat_defense_server.py`
- [ ] `tests/mcp/test_signature_generator.py`

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/131-implement-dynamic-semgrep-sigma-rule-generator-and-ast-validator`
1. 論文テキスト内の脆弱コードパターンからのルール骨格生成。
2. `ast` モジュールによる Python/YAML/ルール構文解析とバリデーション。
3. 過剰正規表現バックトラックの検知と安全性検証。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] Semgrep / Sigma / YARA ルールが自動合成され、AST 構文検証を通過すること
- [ ] 構文エラーや安全でない正規表現を含むルールが弾かれること
- [ ] 全品質ゲート（Xenon Rank A, Flake8, Mypy Strict, pytest）を 100% パスすること
