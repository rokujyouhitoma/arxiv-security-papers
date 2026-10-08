---
ID: 500
種別: Feature
優先度: Medium
ステータス: Open (New)
---

# [FEAT] Implement Metacircular Macro Expander for ULisp (ID: 500)

## 1. 概要 / Summary
現在、ULisp の構文脱糖は `ulisp/passes/01_desugar.scm` 内でハードコードされた固定的な手続き（`desugar-cond` 等）に依存している。

本 Issue では、Scheme が持つ「コードとデータの同一性（ホモアイコニシティ）」とメタサーキュラー評価の利点を活かし、ホスト Scheme 環境上で実行される**「本格的なマクロ展開器（Macro Expander）」**を実装する。
`defmacro` または `syntax-rules` 形式のマクロ定義を可能にし、言語仕様の拡張をコンパイラ内部のコード変更なしにユーザー定義 Scheme プログラムから行える柔軟な拡張性を確立する。

---

## 2. トレーサビリティ / Traceability
- **DSN-33**: §3.1 (Scheme コア構文), §6.1 (セルフホスティングパイプライン)
- **DSN-31**: §3.1 (ILisp マクロ展開機構との連携)
- **先行 Issue**: #497 (Serial Nanopass Pipeline)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] `ulisp/passes/` (新設パス `00b_macro_expander.scm`)
- [ ] [ulisp/passes/01_desugar.scm](file:///workspace/arxiv-security-papers/ulisp/passes/01_desugar.scm): マクロ展開器との統合
- [ ] [ulisp/passes/05_driver.scm](file:///workspace/arxiv-security-papers/ulisp/passes/05_driver.scm): パイプライン先頭への配置
- [ ] [ulisp/Makefile](file:///workspace/arxiv-security-papers/ulisp/Makefile): パス依存関係の更新
- [ ] [ulisp/bootstrap.sh](file:///workspace/arxiv-security-papers/ulisp/bootstrap.sh): セルフホスティング不動点検証
- [ ] [ulisp/test.sh](file:///workspace/arxiv-security-papers/ulisp/test.sh): 既存テストスイート 100% PASS 保証
- [ ] [docs/issues/README.md](file:///workspace/arxiv-security-papers/docs/issues/README.md): Issue 台帳の更新

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/500-implement-ulisp-metacircular-macro-expander`

1. **マクロ定義構文の設計**:
   - `(define-macro (name . params) body)` による手続き的マクロ展開環境の構築。
2. **コンパイル時メタサーキュラー評価器の実装**:
   - マクロ展開器がコンパイル時にマクロ本体式を評価し、展開後の S 式を返す仕組みの実装。
3. **Core Scheme パスへの統合**:
   - マクロ展開後の S 式を Pass 1 (`desugar-all`) へ受け渡す直列結合。
4. **検証と品質ゲート**:
   - 全単体テストおよび bit-for-bit 不動点セルフホスティングの成立を確認する。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] ユーザー定義マクロがコンパイル時に正しく展開されること。
- [ ] `ulisp/test.sh` の全テストが 100% PASS すること。
- [ ] `ulisp/bootstrap.sh` の不動点検証（`diff stage2.s stage3.s == 0`）が成立すること。
- [ ] すべての品質ゲート（`make check_format`, `make static_analysis`）を通過すること。
