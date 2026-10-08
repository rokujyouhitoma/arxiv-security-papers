---
ID: 498
種別: Refactoring
優先度: High
ステータス: Open (New)
---

# [REFACTOR] Implement Explicit Closure Conversion Nanopass for ULisp (ID: 498)

## 1. 概要 / Summary
現在、ULisp のクロージャ生成、自由変数キャプチャ、および相互再帰バックパッチの処理は、`ulisp/passes/04_codegen.scm` のコード生成ルーチン（`compile-lambda-named`, `compile-letrec`）の内部で x86-64 アセンブリの出力と密結合した状態で実行されている。

本 Issue では、Chez Scheme 等の正統派セルフホスティング Scheme コンパイラの設計に基づき、**「クロージャ変換（Closure Conversion / Lambda Lifting）パス」**を S式 $\to$ S式の独立した Nanopass として実装・分離する。
ネストした `lambda` をすべてトップレベルのフラットな手続き定義に持ち上げ、明示的な環境引数（`%env`）と環境タプル参照（`%closure-ref`）に変換することで、コード生成器（Codegen）を単なる「フラットな関数の直截なアセンブリ化」へと極限まで単純化する。

---

## 2. トレーサビリティ / Traceability
- **DSN-33**: §3.6 (第一級関数とフラットクロージャ), §4 (フェーズ別コンパイラ設計), §6.1 (セルフホスティングパイプライン)
- **DSN-31**: §3.2 (Backend B: ULisp AOT Native Backend)
- **先行 Issue**: #496 (Modularize ULisp Passes), #497 (Serial Nanopass Pipeline)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [ulisp/passes/02_analysis.scm](file:///workspace/arxiv-security-papers/ulisp/passes/02_analysis.scm) または新設パス `03_closure_conversion.scm`: 明示的クロージャ変換 S式パスの実装
- [ ] [ulisp/passes/04_codegen.scm](file:///workspace/arxiv-security-papers/ulisp/passes/04_codegen.scm): 泥臭いクロージャ生成コードを全廃し、フラットな手続き呼び出し・生成のみに純化
- [ ] [ulisp/passes/05_driver.scm](file:///workspace/arxiv-security-papers/ulisp/passes/05_driver.scm): クロージャ変換パスをパイプラインに直列結合
- [ ] [ulisp/Makefile](file:///workspace/arxiv-security-papers/ulisp/Makefile): パス依存関係の更新
- [ ] [ulisp/bootstrap.sh](file:///workspace/arxiv-security-papers/ulisp/bootstrap.sh): 3段階セルフホスティング不動点検証
- [ ] [ulisp/test.sh](file:///workspace/arxiv-security-papers/ulisp/test.sh): 全テスト 100% PASS 保証
- [ ] [tests/ilisp/test_ulisp_codegen.py](file:///workspace/arxiv-security-papers/tests/ilisp/test_ulisp_codegen.py): ILisp AOT バックエンド統合テスト 100% PASS 保証
- [ ] [docs/issues/README.md](file:///workspace/arxiv-security-papers/docs/issues/README.md): Issue 台帳の更新

---

## 4. 実装方針 / Implementation Plan
Target Branch: `refactor/498-implement-ulisp-closure-conversion-nanopass`

1. **クロージャ変換仕様の策定**:
   - 自由変数を捕捉する `(lambda (x) (+ a x))` を、環境タプルを引数に取るトップレベル関数 `(%lambda_N (%env x) (+ (%closure-ref %env 1) x))` と、クロージャ生成式 `(%make-closure %lambda_N a)` に S 式変換する。
2. **相互再帰 (`letrec`) の平坦化**:
   - `letrec` 束縛をダミー環境付きクロージャ割り当てと、環境セルへの破壊的代入によるバックパッチに S 式レベルで正規化する。
3. **コード生成器の純化**:
   - `04_codegen.scm` 内の `*lambdas*` 遅延リストや環境追跡の複雑な特殊分岐を全廃し、トップレベル関数の単純なアセンブリ化へ移行する。
4. **検証と品質ゲート**:
   - 全単体テストおよび bit-for-bit 不動点セルフホスティングの成立を確認する。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] クロージャ変換が S式 $\to$ S式の独立したパスとして実装されていること。
- [ ] `04_codegen.scm` がクロージャ解析を行わず、フラットな手続きのみをコード生成すること。
- [ ] `ulisp/test.sh` の全テストが 100% PASS すること。
- [ ] `ulisp/bootstrap.sh` の不動点検証（`diff stage2.s stage3.s == 0`）が成立すること。
- [ ] `tests/ilisp/test_ulisp_codegen.py` が全件 PASS すること。
- [ ] すべての品質ゲート（`make check_format`, `make static_analysis`）を通過すること。
