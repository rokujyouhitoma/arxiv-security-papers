---
ID: 022
種別: Security / Hardening
優先度: High
ステータス: Closed (Completed)
---

# [SEC/HARDENING] DSN-11準拠: ASTセキュリティガードの多層堅牢化とパストラバーサル防御の実装 (ID: 022)

## 1. 概要 / Summary
設計書 [DSN-11](../../designs/DSN-11-repository-security-and-threat-defense.md) および最新の Python 脆弱性研究（SAGA, PickleFuzzer, Corvus）に基づくセキュリティ監査により発見された潜在的課題に対処し、**AST セキュリティガードの多層堅牢化** および **MCP サーバー境界防御（パストラバーサル防御 & 遅延ロード）** を完遂しました。

---

## 2. トレーサビリティ / Traceability
- **設計規約**: [AGENTS.md](../../../.agents/AGENTS.md) (Information Security Specialist / Systems Auditor)
- **設計書**: [DSN-11-repository-security-and-threat-defense.md](../../designs/DSN-11-repository-security-and-threat-defense.md)
- **関連Issue**: [021-search-engine-evaluation-framework.md](closed/021-search-engine-evaluation-framework.md), [019-observability-mcp-server-for-ai-coding-agents.md](closed/019-observability-mcp-server-for-ai-coding-agents.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [src/observability_mcp_server.py](../../../src/observability_mcp_server.py) (AST 多層堅牢化: 禁止モジュール、リフレクション、Dunder属性、ファイル書込遮断)
- [x] [src/mcp_server.py](../../../src/mcp_server.py) (os.path.commonpath による厳格なパストラバーサル防御 & VectorEngine 遅延ローダー化)
- [x] [tests/test_security_hardening.py](../../../tests/test_security_hardening.py) (5大セキュリティテスト 100% PASS)
- [x] [docs/issues/README.md](../README.md)
- [x] [docs/designs/DSN-11-repository-security-and-threat-defense.md](../../designs/DSN-11-repository-security-and-threat-defense.md)

---

## 4. 実装成果 / Implementation Results
Target Branch: `sec/022-security-guard-hardening`

1. **AST セキュリティガードの多層堅牢化 (`observability_mcp_server.py`)**:
   - `BLOCKED_MODULES`: `ctypes`, `posix`, `resource`, `signal`, `pickle`, `shelve`, `marshal`, `importlib`, `_thread` などの低レベル・デシリアライゼーションモジュールを完全ブロック。
   - `BLOCKED_CALLS` / `BLOCKED_BUILTIN_FUNCS`: `eval`, `exec`, `compile`, `__import__`, `getattr`, `setattr`, `globals`, `locals`, `vars`, `chmod`, `chown` 等の動的リフレクション呼び出しを事前遮断。
   - `BLOCKED_DUNDER_NAMES`: `__builtins__`, `__dict__`, `__class__`, `__subclasses__` などの難読化アクセスターゲットを AST 走査で遮断。
   - `open()` の安全モード限定: `w`, `a`, `x`, `+` などの破壊的ファイル書き込みモードをプロファイリング中にブロック。
2. **MCP パストラバーサル防御 & パフォーマンス強化 (`mcp_server.py`)**:
   - `is_safe_workspace_path`: `os.path.commonpath` による厳格な親ディレクトリ検証を導入。
   - `VectorEngine` のシングルトン遅延ローダー化（`get_vector_engine()`）により、モジュールインポート時の不要な 328MB ロードを回避し、テスト・ツール初期化を高速化。

---

## 5. 完了条件 / Success Criteria (DoD)
- [x] リフレクション・Pickle・Ctypes・ファイル破壊ペイロードの 100% 遮断実証
- [x] 単体テスト (`tests/test_security_hardening.py`) 5/5 passed (100% PASS)
- [x] 全 57 ソースファイルの `mypy` 静的型解析 0 エラー
- [x] コアテストスイート全 17 件 100% PASS (0.27s)
