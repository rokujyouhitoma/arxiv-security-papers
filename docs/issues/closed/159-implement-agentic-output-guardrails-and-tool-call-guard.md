# Issue 159: Implement Agentic & LLM Output Guardrails and Tool Call Guard

## 1. 概要 (Overview)
`DSN-07` Rev 2.1 (Section 4.5 & 4.6) に基づき、LLM/自律エージェントの出力を検証・サニタイズするガードレール機構（`src/security/guardrails/output_guard.py`）および、エージェントによる外部ツール呼び出し（Tool Invocation）の不正・破壊的実行を遮断するツールガード（`src/security/guardrails/tool_call_guard.py`）を実装する。

## 2. 目的・背景 (Motivation & Background)
- Antigravity IDE や Supervisor 内で稼働する LLM / Agent が間接プロンプトインジェクション（Indirect Prompt Injection）に感染し、システムプロンプトの漏洩、悪意ある命令の実行、PII/機密情報の出力を行わないよう出力ガードレール（DLP & Safety Guard）を配備する。
- エージェントのツール呼び出し引数にシェルメタ文字（`;`, `&&`, `|`, `$()`, バッククォート）やディレクトリトラバーサル（`../`）が含まれる場合、または Read-Only 実行モード時に破壊的ツール（`write_to_file`, `delete_` 等）が呼び出された場合に事前検知・ブロックするポリシー検証器を構築する。

## 3. 実装要件 (Requirements)
1. **LLM 出力ガードレール (`src/security/guardrails/output_guard.py`)**:
   - `detect_prompt_injection(text: str) -> List[str]`: プロンプトインジェクション・ジェイルブレイク構文検知
   - `mask_pii_and_secrets(text: str) -> str`: メールアドレス、IPv4アドレス、電話番号、クレジットカード番号、APIシークレットの DLP マスキング
   - `validate_output_safety(text: str, max_chars: int = 50000) -> Tuple[bool, List[str], str]`: 文字長制限、インジェクション検知、DLPサニタイズ
2. **ツール呼び出しガード (`src/security/guardrails/tool_call_guard.py`)**:
   - `ToolCallGuard`:
     - `validate_tool_call(tool_name: str, arguments: Dict[str, Any], allowed_tools: Optional[Set[str]] = None, read_only: bool = False) -> Tuple[bool, Optional[str]]`
     - 危険引数検知: シェルメタ文字（`;`, `&&`, `||`, `|`, `` ` ``, `$()`）およびパストラバーサル（`../`, `~/`）
     - Read-Only 権限強制: 書き込み・破壊的操作ツールの遮断
     - `sanitize_tool_arguments(arguments: Dict[str, Any]) -> Dict[str, Any]`
3. **品質・制約要件**:
   - Python 標準ライブラリ (`re`, `json`, `typing`, `dataclasses`, `enum`) のみ使用。
   - Xenon 循環的複雑度 $\le 5$ (Rank A 必須)。
   - Mypy `--strict` 準拠。
   - 外部依存ゼロ。

## 4. 対象ファイル (Target Files)
- `src/security/guardrails/__init__.py`: 新規作成
- `src/security/guardrails/output_guard.py`: 新規作成
- `src/security/guardrails/tool_call_guard.py`: 新規作成
- `src/security/__init__.py`: エクスポート追加
- `tests/security/test_guardrails.py`: 単体テスト新規作成

## 5. 完了定義 (Definition of Done)
- [x] `validate_output_safety` がプロンプトインジェクションと機密・個人情報を正確に検知・マスクできること
- [x] `ToolCallGuard` が危険なシェル引数、パストラバーサル、Read-Only時の書き込みツールを確実に遮断すること
- [x] 単体テスト `tests/security/test_guardrails.py` が 100% PASS すること
- [x] `make check_format` および `make static_analysis` が PASS すること
