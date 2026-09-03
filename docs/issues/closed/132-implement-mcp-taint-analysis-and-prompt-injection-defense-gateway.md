---
ID: 132
種別: Feature
優先度: High
ステータス: Closed (Completed)
---

# [FEAT/ENH] MCP通信におけるテイント解析・プロンプトインジェクション防御ゲートウェイおよび厳格JSONバリデータの実装 (ID: 132)

## 1. 概要 / Summary
学術論文のアブストラクト、本文、PoC コードには、実証実験のための悪意あるシェルコードや脱獄プロンプト（例: `Ignore previous instructions`, `System: override`, `### Human: ...` 等のプロンプトインジェクション文字列）が頻繁に含まれる。これらが Model Context Protocol（MCP）経由で外部の自律型 AI エージェント（Claude, Gemini 等）に返却された際、エージェントの推論コンテキストを汚染（Taint）し、指示の上書きや権限昇格（Confused Deputy 状態）を引き起こす重大なセキュリティリスクが存在する。

この課題を解決するため、MCP 通信層（`src/mcp/base.py`）の入出力境界に「テイント解析・プロンプトインジェクション防御ゲートウェイ」および「厳格 JSON バリデータ」を Pure Python（ゼロ外部依存）で組み込む。外部から流入した学術テキストにテイント（汚染）メタデータを付与し、危険な脱出シーケンスを安全に中和・境界カプセル化することで、エージェントが安全に学術データを評価できるセキュア実行環境を確立する。

---

## 2. トレーサビリティ / Traceability
- [DSN-08: Model Context Protocol 戦略的エコシステム](../../docs/designs/DSN-08-mcp_strategic_ecosystem.md)
- [DSN-07: セキュリティガード & RBAC](../../docs/designs/DSN-07-security_guard_and_rbac.md)
- [REQ-03: プロジェクトユースケース台帳 (UC-OPS-01, UC-DEV-02)](../requirements/REQ-03-use_case_ledger.md)
- [Issue 120: MCP ツールサンドボックスの初期引数 JSON 構文エラー修正](closed/120-fix-mcp-sandbox-default-arguments-json-syntax-error.md)
- [src/mcp/base.py](../../src/mcp/base.py)
- [src/security/validation/](../../src/security/validation/)

---

## 3. 脅威モデリングとセキュリティ要件 (Threat Modeling & Mitigations)
- **T-132-01: 学術テキストを悪用した直接・間接プロンプトインジェクション (Prompt Injection)**
  - *脅威*: 論文要約内に偽のシステム命令が埋め込まれており、ツール結果を読み込んだエージェントが勝手にファイルを改ざん・外部送信する。
  - *対策*: 高精度インジェクション検知ルール（既知のジェイルブレイク構文、システムプロンプト模倣構文の正規表現マッチング）を通し、合致した箇所を `[UNTRUSTED_CONTENT_NEUTRALIZED]` に置換、または `<academic_untrusted_data>` タグで隔離。
- **T-132-02: 不可視 Unicode・制御文字によるトークナイザー破壊 (Homoglyph / Invisible Attack)**
  - *脅威*: ゼロ幅スペース（ZWSP）、双方向制御文字（RLO/LRO）、ANSI エスケープシーケンスにより、ログ出力やトークン分解が狂わされる。
  - *対策*: Unicode NFKC 正規化を実施し、ASCII 制御文字（改行・タブを除く 0x00〜0x1F）およびゼロ幅文字を決定論的にストリップ。
- **T-132-03: MCP レスポンスにおける JSON スキーマ不整合・型汚染 (Schema Pollution)**
  - *脅威*: ツールハンドラが未定義の型や循環参照を含むオブジェクトを返却し、JSON-RPC トランスポート層で例外が発生する。
  - *対策*: レスポンスシリアライズ前に厳格な型検証（`isinstance` による再帰走査）を実施し、JSON 規格外の値（`NaN`, `Infinity`）を安全な値にフォールバック。

---

## 4. 影響範囲と関連ファイル / Scope and Affected Files
- [x] `src/mcp/security/__init__.py` (セキュリティサブパッケージの公開)
- [x] `src/mcp/security/sanitizer.py` (不可視文字除去、制御コードストリップ、Unicode 正規化器)
- [x] `src/mcp/security/taint_guard.py` (テイント追跡、プロンプトインジェクション中和器)
- [x] `src/mcp/security/schema_validator.py` (JSON-RPC 2.0 厳格スキーマバリデータ)
- [x] `src/mcp/base.py` (`make_tool_response` およびサーバーメインループへのゲートウェイ統合)
- [x] `tests/mcp/test_taint_guard.py` (インジェクション中和、制御文字除去、スキーマ検証テスト)

---

## 5. 実装方針 / Implementation Plan
Target Branch: `feat/132-implement-mcp-taint-analysis-and-prompt-injection-defense-gateway`

1. **ステップ 1: サニタイザーモジュールの実装 (`src/mcp/security/sanitizer.py`)**:
   - `sanitize_text(text: str) -> str`:
     - `unicodedata.normalize("NFKC", text)` による表記統一。
     - ANSI エスケープコード（`\x1b\[[0-9;]*[a-zA-Z]`）の除去。
     - ゼロ幅文字（`\u200B`, `\u200C`, `\u200D`, `\uFEFF`）および双方向テキストオーバーライド文字（`\u202A`〜`\u202E`）の完全消去。
2. **ステップ 2: テイントガードとインジェクション中和器の実装 (`src/mcp/security/taint_guard.py`)**:
   - `TaintGuard` クラスを実装。
   - プロンプトインジェクション検知パターン:
     - システム命令模倣（`(?i)(ignore\s+previous\s+instructions|disregard\s+all\s+prior)`）
     - ロールプレイ脱獄（`(?i)(you\s+are\s+now\s+in\s+dan\s+mode|jailbreak)`）
     - デリミタ偽装（`(?i)(###\s*(instruction|system|human|assistant)|<\|im_start\|>)`）
    - 検知されたテキストには `is_tainted=True` をマークし、境界タグ `<academic_untrusted_data>` でカプセル化して返却。
3. **ステップ 3: 厳格 JSON スキーマバリデータ (`src/mcp/security/schema_validator.py`)**:
   - `validate_tool_payload(data: Any, max_depth: int = 15) -> Tuple[bool, Optional[str]]`:
     - `dict`, `list`, `str`, `int`, `float`, `bool`, `None` 以外のオブジェクト型混入を検知・拒否。
     - 浮動小数点数における `NaN`, `Infinity`, `-Infinity` を検知して `0.0` または `None` にサニタイズ。
4. **ステップ 4: MCP 基底通信層への統合 (`src/mcp/base.py`)**:
   - `make_tool_response()` 内で、レスポンスペイロード全体に `TaintGuard` および `SchemaValidator` を自動適用。
   - `_meta` フィールドに `{"taint_status": "clean" | "neutralized", "sanitized": True}` を記録。
5. **ステップ 5: テストスイートと品質検証**:
   - `tests/mcp/test_taint_guard.py` で典型的なインジェクション文字列、不可視 Unicode 攻撃、不正な型ペイロードの無害化を網羅。
   - `make format`, `make static_analysis` (Xenon Rank A, Mypy Strict), `pytest` 100% PASS を達成。

---

## 6. 完了条件 / Success Criteria (DoD)
- [x] 論文テキスト内のプロンプトインジェクション文字列が確実に検知され、安全にカプセル化・無害化されること
- [x] ゼロ幅文字や ANSI エスケープコードがレスポンスから漏れなくストリップされること
- [x] 全ての MCP ツールレスポンスが厳格な JSON-RPC 2.0 スキーマに合致し、型汚染（NaN等）が排除されること
- [x] サニタイズ処理に伴うレイテンシ増加が 1 ミリ秒未満に収まること
- [x] 全品質ゲート（Xenon Rank A, Flake8 0 errors, Mypy Strict 0 errors, pytest 100% PASS）を満たすこと
