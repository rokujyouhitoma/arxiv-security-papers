---
ID: 484
種別: Feature
優先度: High
ステータス: Open (New)
---

# [FEAT] ALisp Phase 3: S-Path 決定論的 AST パッチ (patch)・CAS 置換・マクロ展開逆マッピング自己修復基盤の実装 (ID: 484)

## 1. 概要 / Summary
[DSN-32 第12.4節](../../docs/designs/DSN-32-ailisp_agent_lisp_architecture_specification.md) に基づき、AI エージェントが最小のトークン数で安全かつ決定論的にコードを修正できる自律自己修復基盤（Phase 3）を実装する。
曖昧性のない AST 絶対位置を示す **S-Path** 走査エンジン、LLM の幻覚による誤爆を防ぐ **CAS（Compare-And-Swap）** 置換セマンティクス（`patch`）、マクロ脱糖後の例外からマクロ展開前のオリジナル S 式位置を逆引きする **Source Location Inversion**、および高階 Blame Tracking を統合した S 式構造化診断（`diagnostic`）を提供する。

---

## 2. トレーサビリティ / Traceability
- **関連設計書**:
  - [DSN-32: AILISP (ALisp + ILisp) 次世代AIコーディングエージェント実行環境包括的アーキテクチャ設計書](../../docs/designs/DSN-32-ailisp_agent_lisp_architecture_specification.md) (第 2.3 節, 第 5.3 節, 第 6 章, 第 12.4 節)
  - [DSN-31: ILISP R7RS コアアーキテクチャ包括設計仕様書](../../docs/designs/DSN-31-ilisp_r7rs_intelligence_lisp_architecture_specification.md) (第 2.2 節 Scope Sets マクロ)
- **対象サブシステム**:
  - `alisp/repair/`
  - `alisp/contracts/blame.py`

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [alisp/repair/__init__.py](../../alisp/repair/__init__.py) (自己修復プロトコル公開インターフェース)
- [ ] [alisp/repair/diagnostic.py](../../alisp/repair/diagnostic.py) (S式構造化診断生成器, マクロ展開逆マッピング)
- [ ] [alisp/repair/patch.py](../../alisp/repair/patch.py) (S-Path パーサ, CAS 置換エンジン)
- [ ] [alisp/contracts/blame.py](../../alisp/contracts/blame.py) (高階関数 Blame 帰属判定エンジン)
- [ ] [tests/alisp/test_phase3_repair_and_patch.py](../../tests/alisp/test_phase3_repair_and_patch.py) (単体・統合テスト)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/484-implement-alisp-phase3-spath-patch-and-self-repair`

1. **S-Path 決定論的走査・パーサの実装 (`alisp/repair/patch.py`)**:
   - `(target-path (root 2 3 1))` 等のツリーインデックス指定、およびモジュール/定義シンボルパス指定を受理する走査ロジック。
2. **CAS（Compare-And-Swap）置換エンジンの実装**:
   - `expected-original` と現行 AST ノードの等価性（`equal?`）を検証。
   - 不一致の場合は `CasMismatchError` を送出して改ざん・幻覚を即座にブロック。
   - 一致する場合のみ `replace-with` ノードへのアトミック置換を実行。
3. **マクロ展開逆マッピングの実装 (`alisp/repair/diagnostic.py`)**:
   - `ilisp/syntax.py` の `SyntaxObject` が保持する `syntax-source-location` メタデータを逆引き。
   - 実行時スタックトレースからマクロ展開前のオリジナルソースファイル名、行番号、高レベル S 式を特定して `(diagnostic ...)` S 式を構築。
4. **高階関数 Blame Tracking (`alisp/contracts/blame.py`)**:
   - コールバック呼び出し時の引数違反（実装側 Blame）と戻り値違反（呼び出し側 Blame）を正確に分類。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] 同一シグネチャの関数呼び出しが複数存在するコードにおいて、S-Path により指定されたノードのみが正確に置換されること。
- [ ] `expected-original` が現行コードと不一致の場合、置換が拒絶され CAS エラー診断が返却されること。
- [ ] マクロ脱糖コードの例外発生時、診断 S 式がマクロ展開前のオリジナルソース行番号と式を提示できること。
- [ ] `make format`, `make static_analysis`, `make test` が 100% PASS すること。
