---
ID: 499
種別: Feature
優先度: Medium
ステータス: Open (New)
---

# [FEAT] Implement ANF Normalization and CP0 Constant Folding Optimizer for ULisp (ID: 499)

## 1. 概要 / Summary
現在、ULisp のコード生成器（`ulisp/passes/04_codegen.scm`）は、深くネストした式（例: `(+ (* x 10) (- y 2))`）を直接走査しながら、スタックポインタオフセット `si` を手動で計算してレジスタ退避を行っている。

本 Issue では、すべての計算の中間結果を明示的な一時変数に束縛する**「A-Normal Form（ANF / 3番地コード形式）正規化 Nanopass」**を導入する。
さらに、ANF 表現上で動作する Chez Scheme 準拠の**「CP0 最適化パス（定数畳み込み Constant Folding、自明な条件分岐簡約、不要式削除 Dead Code Elimination）」**を実装し、コンパイラのスタック管理単純化と生成バイナリの実行性能向上を両立させる。

---

## 2. トレーサビリティ / Traceability
- **DSN-33**: §3 (言語機能と低レイヤコード生成仕様), §4 (フェーズ別コンパイラ設計)
- **DSN-31**: §3.2 (Backend B: ULisp AOT Native Backend)
- **先行 Issue**: #497 (Serial Nanopass Pipeline), #498 (Closure Conversion Nanopass)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] `ulisp/passes/` (新設パス `02b_anf.scm` および `02c_cp0.scm`)
- [ ] [ulisp/passes/04_codegen.scm](file:///workspace/arxiv-security-papers/ulisp/passes/04_codegen.scm): ANF 前提によるスタック割り当ての単純化
- [ ] [ulisp/passes/05_driver.scm](file:///workspace/arxiv-security-papers/ulisp/passes/05_driver.scm): パイプライン結合
- [ ] [ulisp/Makefile](file:///workspace/arxiv-security-papers/ulisp/Makefile): ビルド依存関係の同期
- [ ] [ulisp/bootstrap.sh](file:///workspace/arxiv-security-papers/ulisp/bootstrap.sh): セルフホスティング不動点検証
- [ ] [ulisp/test.sh](file:///workspace/arxiv-security-papers/ulisp/test.sh): 既存テストスイート 100% PASS 保証
- [ ] [tests/ilisp/test_ulisp_codegen.py](file:///workspace/arxiv-security-papers/tests/ilisp/test_ulisp_codegen.py): ILisp AOT 連携テスト 100% PASS 保証
- [ ] [docs/issues/README.md](file:///workspace/arxiv-security-papers/docs/issues/README.md): Issue 台帳の更新

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/499-implement-ulisp-anf-and-cp0-optimization`

1. **ANF 正規化パス (`normalize-term`) の実装**:
   - 複合式を平坦化し、関数の引数がすべて即値または変数である形（`let` 式の連鎖）に変換する。
2. **CP0 最適化パスの実装**:
   - 定数同士の二項演算（`(+ 1 2)` $\to$ `3`）のコンパイル時評価。
   - 自明な条件分岐（`(if #t a b)` $\to$ `a`、`(if #f a b)` $\to$ `b`）の剪定。
   - 副作用のない未使用変数の削除。
3. **検証と品質ゲート**:
   - 全単体テストおよび bit-for-bit 不動点セルフホスティングの成立を確認する。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] ANF 変換パスが独立した S式変換として動作すること。
- [ ] CP0 による定数畳み込みと不要分岐削除が正常に機能すること。
- [ ] `ulisp/test.sh` の全テストが 100% PASS すること。
- [ ] `ulisp/bootstrap.sh` の不動点検証（`diff stage2.s stage3.s == 0`）が成立すること。
- [ ] すべての品質ゲート（`make check_format`, `make static_analysis`）を通過すること。
