---
ID: 131
種別: Feature
優先度: Medium
ステータス: Closed (Completed)
---

# [FEAT/ENH] 学術知見からの動的防御シグネチャ（Semgrep / Sigma / YARA）自動生成とインメモリAST構文テスターの実装 (ID: 131)

## 1. 概要 / Summary
学術論文内で開示された新規エクスプロイト手法、不安全な API 呼び出しパターン、あるいは難読化シェルコードの特徴から、即座に実運用環境へ投入可能な検知シグネチャ（Semgrep YAML ルール、Sigma ログ検知ルール、YARA メモリ/ファイルシグネチャ）を動的に自動生成するツールを MCP サーバー（`src/mcp/threat_defense_server.py`）上に実装する。

生成されたルールが構文エラーや危険な正規表現爆発（ReDoS: Regular Expression Denial of Service）を含んだまま CI/CD や SIEM に配布される事故を防止するため、Python 標準の `ast` モジュールを活用したインメモリ構文検証器および静的正規表現アナライザーを内蔵し、厳格な構文妥当性検証を通過した安全なルールのみを配信する品質保証ゲートを Pure Python（ゼロ外部依存）で確立する。

---

## 2. トレーサビリティ / Traceability
- [DSN-08: Model Context Protocol 戦略的エコシステム](../../docs/designs/DSN-08-mcp_strategic_ecosystem.md)
- [REQ-03: プロジェクトユースケース台帳 (UC-DEV-02, UC-OPS-01)](../requirements/REQ-03-use_case_ledger.md)
- [Issue 083: 新興脅威に対応した Semgrep / セキュアパッチ合成エンジンの拡充](closed/083-threat-defense-slopsquatting-and-eop-expansion.md)
- [src/mcp/threat_defense_server.py](../../src/mcp/threat_defense_server.py)
- [src/mcp/base.py](../../src/mcp/base.py)

---

## 3. 脅威モデリングとセキュリティ要件 (Threat Modeling & Mitigations)
- **T-131-01: 生成ルール内の正規表現による ReDoS 脆弱性（Catastrophic Backtracking）**
  - *脅威*: 論文中の悪意ある文字列や曖昧なパターンから生成された正規表現に `(a+)+` や `.*.*` のような入れ子量化子が含まれ、SIEM や IDS の検知エンジンを CPU 100% で停止させる。
  - *対策*: 静的正規表現アナライザーを実装し、入れ子量化子やオーバーラップする反復パターンを AST レベルで走査・検知して拒否。
- **T-131-02: 構文不正ルールによる DevSecOps パイプラインの停止**
  - *脅威*: 生成された YAML や YARA ルールのインデント・コロン欠落により、コミット前フックや CI パイプラインが構文エラーでクラッシュする。
  - *対策*: インメモリパーサー（YAML 構文バリデータ、YARA 構文トークナイザー）により、出力前に文法チェックを 100% 実施。
- **T-131-03: ルール検証時の任意コード実行 (Arbitrary Code Execution)**
  - *脅威*: コードパターンをテストする際に `eval()` や `exec()` を用いてしまい、論文中の悪意ある PoC コードが実行される。
  - *対策*: コード実行を一切行わず、Python 標準の `ast.parse()` による静的構文木解析のみを実行（サンドボックス分離・非実行評価）。

---

## 4. 影響範囲と関連ファイル / Scope and Affected Files
- [x] `src/mcp/tools/signature_generator.py` (Semgrep, Sigma, YARA ルール自動合成モジュール)
- [x] `src/mcp/tools/ast_rule_validator.py` (インメモリ AST 構文テスターおよび ReDoS 静的検証器)
- [x] `src/mcp/threat_defense_server.py` (`synthesize_detection_signature` ツール追加)
- [x] `tests/mcp/test_signature_generator.py` (ルール生成、AST バリデーション、ReDoS 阻止テスト)

---

## 5. 実装方針 / Implementation Plan
Target Branch: `feat/131-implement-dynamic-semgrep-sigma-rule-generator-and-ast-validator`

1. **ステップ 1: シグネチャジェネレーターの実装 (`src/mcp/tools/signature_generator.py`)**:
   - `SignatureGenerator` クラスを定義。
   - `generate_semgrep(cwe_id, code_snippet, lang)`:
     - 抽象構文木パターン（例: `pattern: $X.execute(...)`, `pattern-not: ...`）を組み立て、Semgrep 準拠の YAML 文字列を構築。
   - `generate_sigma(title, log_type, field_conditions)`:
     - Windows Event Logs / Syslog / CloudTrail 向けの Sigma YAML ルールを生成（`logsource`, `detection`, `condition`）。
   - `generate_yara(rule_name, strings, condition)`:
     - 16進バイト列（`$hex = { E8 ?? ?? ?? ?? }`）または ASCII/Wide 文字列定義と論理条件（`all of them`, `1 of ($a*)`）を構成。
2. **ステップ 2: インメモリ AST 構文テスターの実装 (`src/mcp/tools/ast_rule_validator.py`)**:
   - `ASTRuleValidator` クラスを実装。
   - Python コードパターンに対する `ast.parse()` による構文木構築検証。構文エラー（SyntaxError）を捕捉して詳細な修正ヒントを付与。
   - YAML 構造の厳格検証（必須キー、インデント整合性）。
   - ReDoS 静的検出: 正規表現文字列を走査し、再帰量化子（例: `\([a-z]+\)\+`）や壊滅的バックトラックパターンを正規表現 AST チェックで遮断。
3. **ステップ 3: MCP サーバーツールへの統合 (`src/mcp/threat_defense_server.py`)**:
   - `TOOLS_MANIFEST` に `synthesize_detection_signature` を追加。
   - 引数: `rule_type` ("semgrep" | "sigma" | "yara"), `target_vulnerability`, `code_or_log_pattern`。
   - ルール生成後、自動的に `ASTRuleValidator` を通過させ、検証ステータス（`is_valid: True`, `ast_checked: True`, `redos_free: True`）を付与して返却。
4. **ステップ 4: テストスイートと品質検証**:
   - `tests/mcp/test_signature_generator.py` で SQLi, RCE, SSRF に対する Semgrep/Sigma/YARA ルールの生成および ReDoS パターンのブロックを網羅。
   - `make format`, `make static_analysis` (Xenon Rank A, Mypy Strict), `pytest` 100% PASS を達成。

---

## 6. 完了条件 / Success Criteria (DoD)
- [x] 論文内の脆弱コードから Semgrep / Sigma / YARA の各シグネチャが外部依存なしに自動生成されること
- [x] 生成された Python 用 Semgrep パターンが `ast.parse()` により構文的に有効と保証されること
- [x] ReDoS の危険がある正規表現パターン（入れ子反復等）を含むルールがバリデータにより確実に弾かれること
- [x] 検証結果と生成ルールが MCP JSON-RPC 2.0 準拠のレスポンスとして正常に返却されること
- [x] 全品質ゲート（Xenon Rank A, Flake8 0 errors, Mypy Strict 0 errors, pytest 100% PASS）を満たすこと
