# [FEAT] 新興脅威（Slopsquatting, EOP モデル汚染, 多コミット型改ざん）に対応した Semgrep / セキュアパッチ合成エンジンの拡充 (ID: 083)

| 項目 | 内容 |
| :--- | :--- |
| **ID** | 083 |
| **種別** | Feature |
| **優先度** | High |
| **ステータス** | Closed (Resolved) |
| **起票日** | 2026-08-27 |
| **完了日** | 2026-08-27 |
| **担当ロール** | Information Security Specialist (SC) / Systems Architect (SA) |
| **対象ブランチ** | `feat/083-threat-defense-slopsquatting-and-eop-expansion` |

---

## 1. 概要 / Summary
最新のセキュリティ論文で明らかになった新興攻撃ベクトル（LLM パッケージ幻覚悪用「Slopsquatting」、例外指向プログラミング「EOP モデル汚染 / Pickle 不整合」、および CI スナップショット回避「多コミット型脆弱性」）に対応するため、`src/security/taxonomy/` および `src/mcp/threat_defense_server.py` の防御ルール合成エンジンを大幅に拡張する。

---

## 2. 影響範囲と関連ファイル / Scope and Affected Files
- `src/security/taxonomy/cwe.py` (新興 CWE / 攻撃パターン定義)
- `src/security/taxonomy/mitre.py` (MITRE ATT&CK v15 テクニック更新)
- `src/mcp/threat_defense_server.py` (Semgrep ルール / パッチ合成ハンドラ)
- `src/mcp/tech_radar_server.py` (脅威予測エンジン)
- `tests/security/test_taxonomy.py` (単体テスト)
- `tests/mcp/test_mcp_strategic_ecosystem.py` (MCP テスト)

---

## 3. 要件定義と脅威モデル / Requirements & Threat Model
- **機能要件**:
  - `CWE-1357` (依存関係パッケージ名混同・Slopsquatting 防御ルール)
  - `CWE-502` / `CWE-693` (Pickle VM 命令不整合および SafeTensors 強制変換パッチ)
  - `T1195.001` (サプライチェーン多コミット整合性検証)
  - `generate_semgrep_rule` で上記新脅威の CI YAML を即座に生成可能にする。
- **セキュリティ要件**:
  - 生成されるパッチコードに構文エラーや二次的脆弱性（CWE-94 等）が混入しないこと。

---

## 4. 実装方針 / Implementation Plan
1. **`src/security/taxonomy/cwe.py`**:
   - `CWE_DEFENSE_MAP` に Slopsquatting (CWE-1357), EOP Serialization (CWE-502), Multi-Commit Evasion (CWE-1104) を追加。
2. **`src/mcp/threat_defense_server.py`**:
   - `handle_synthesize_secure_patch` に SafeTensors 置換および依存関係 allow-list 生成ロジックを追加。
3. **`tests/`**:
   - 新規 CWE に対する Semgrep ルール生成およびパッチ合成テストを追加。

---

## 5. 完了条件 / Success Criteria (DoD)
- [x] Slopsquatting および EOP モデル汚染の Semgrep ルールが正常に合成されること。
- [x] `check_threat_coverage` で新興脅威への防御スコアが正確に算出されること。
- [x] `tests/security/` および `tests/mcp/` が 100% PASS すること。
- [x] `make check` をクリアすること。
