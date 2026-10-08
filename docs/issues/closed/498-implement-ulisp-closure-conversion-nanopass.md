---
ID: 498
種別: Refactoring
優先度: High
ステータス: Closed
---

# [REFACTOR] Implement Explicit Closure Conversion Nanopass for ULisp (ID: 498)

## 1. 概要 / Summary
現在、ULisp のクロージャ生成、自由変数キャプチャ、および相互再帰バックパッチの処理は、`ulisp/passes/04_codegen.scm` のコード生成ルーチン（`compile-lambda-named`, `compile-letrec`）の内部で x86-64 アセンブリの出力と密結合した状態で実行されていた。

本 Issue では、Chez Scheme 等の正統派セルフホスティング Scheme コンパイラの設計に基づき、**「クロージャ変換（Closure Conversion / Lambda Lifting）パス」**を S式 $\to$ S式の独立した Nanopass として実装・分離した。
ネストした `lambda` をすべてトップレベルのフラットな手続き定義に持ち上げ、明示的な環境引数（`%env`）と環境タプル参照（`%closure-ref`）に変換することで、コード生成器（Codegen）を単なる「フラットな関数の直截なアセンブリ化」へと極限まで単純化した。

---

## 2. トレーサビリティ / Traceability
- **DSN-33**: §2.1 (Tagged Pointer / ヒープオブジェクト仕様), §3.6 (第一級関数とフラットクロージャ), §4 (フェーズ別コンパイラ設計), §6.1 (セルフホスティングパイプライン)
- **DSN-31**: §3.2 (Backend B: ULisp AOT Native Backend)
- **先行 Issue**: #496 (Modularize ULisp Passes), #497 (Serial Nanopass Pipeline)

---

## 3. セキュリティ & 脅威分析 / Security Analysis & Threat Model
1. **環境外参照・シンボル衝突リスク (Symbol Collisions)**:
   - Lambda Lifting で生成されるトップレベル関数名（`%lambda_N`）がユーザー定義シンボルと衝突し、意図せぬ関数置換が発生する脅威。
   - **対策**: `%` プレフィックスと単調増加カウンタによる決定論的かつ一意な予約シンボル空間の完全分離。
2. **境界外メモリアクセス (Out-of-Bounds Closure Access)**:
   - 環境参照（`%closure-ref`）のインデックスがクロージャヒープ割り当てサイズを超過し、ヒープ破壊・任意コード実行につながる脅威。
   - **対策**: 自由変数リストの完全順序付けおよび静的インデックス境界検査の徹底。
3. **未束縛変数の安全な拒絶 (Unbound Variable Protection)**:
   - キャプチャ漏れの変数が存在した場合に無効な環境ポインタを生成する脅威。
   - **対策**: クロージャ変換パス段階での静的未定義変数検出およびコンパイル時エラー発火。

---

## 4. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [ulisp/passes/03_closure_convert.scm](file:///workspace/arxiv-security-papers/ulisp/passes/03_closure_convert.scm): 新設する明示的クロージャ変換 S式 $\to$ S式 パス
- [x] [ulisp/passes/00_helpers.scm](file:///workspace/arxiv-security-papers/ulisp/passes/00_helpers.scm): `%make-closure`, `%closure-ref`, `%closure-set!` 等のプリミティブ述語追加
- [x] [ulisp/passes/02_analysis.scm](file:///workspace/arxiv-security-papers/ulisp/passes/02_analysis.scm): クロージャ変換で利用する自由変数抽出の連動
- [x] [ulisp/passes/05_codegen.scm](file:///workspace/arxiv-security-papers/ulisp/passes/05_codegen.scm): 複雑なネストクロージャ生成を全廃し、フラットな `%program` / `%function` の単純コード生成へ純化
- [x] [ulisp/passes/06_driver.scm](file:///workspace/arxiv-security-papers/ulisp/passes/06_driver.scm): `forms` $\to$ `rewrite-top-level` $\to$ `desugar-all` $\to$ `closure-convert` $\to$ `codegen` 直列パイプライン結合
- [x] [ulisp/Makefile](file:///workspace/arxiv-security-papers/ulisp/Makefile): パス構成順序と依存関係の更新
- [x] [ulisp/bootstrap.sh](file:///workspace/arxiv-security-papers/ulisp/bootstrap.sh): 3段階セルフホスティング不動点検証
- [x] [ulisp/test.sh](file:///workspace/arxiv-security-papers/ulisp/test.sh): 既存テストスイート 100% PASS 保証
- [x] [tests/ilisp/test_ulisp_codegen.py](file:///workspace/arxiv-security-papers/tests/ilisp/test_ulisp_codegen.py): ILisp AOT バックエンド統合テスト 100% PASS 保証
- [x] [docs/issues/README.md](file:///workspace/arxiv-security-papers/docs/issues/README.md): Issue 台帳の更新

---

## 5. 実装方針 / Implementation Plan
Target Branch: `refactor/498-implement-ulisp-closure-conversion-nanopass`

1. **クロージャ変換中間表現（IR）の仕様策定**:
   - 入力: Pass 1 (`desugar-all`) を通過した Canonical Core Scheme AST。
   - 出力: `(%program (%functions (%function label (%env . params) body) ...) main-expr)` 形式の平坦化プログラム表現。
   - 自由変数 `x` を持つ式:
     - 定義側: `(%function %L_0 (%env arg) (+ (%closure-ref %env 1) arg))`
     - 生成側: `(%make-closure '%L_0 x)`
2. **相互再帰 (`letrec`) の S 式平坦化**:
   - `letrec` 内の相互再帰ラムダ群を、ダミークロージャ生成 $\to$ `%closure-set!` による環境バックパッチの S 式シーケンスへと正規化。
3. **Pass 5 コード生成器の純化**:
   - `05_codegen.scm` 内の `*lambdas*` 遅延リストや環境追跡の特殊ケース（`compile-lambda-named`）を全廃。
   - トップレベルの各 `%function` を一列にコンパイルし、`%make-closure` と `%closure-ref` をプリミティブ演算として直接 x86-64 コード生成。
4. **Pass 6 Driver での直列パイプライン結合**:
   ```scheme
   (let* ((forms (read-all-forms))
          (ast0  (rewrite-top-level forms))
          (ast1  (desugar-all ast0))
          (ast2  (closure-convert ast1)))
     (compile-program ast2))
   ```
5. **検証と品質ゲート**:
   - `cd ulisp && ./test.sh`: Phase 1〜7 テスト 100% PASS。
   - `cd ulisp && ./bootstrap.sh`: Stage 1 $\to$ Stage 2 $\to$ Stage 3 の不動点検証（`diff stage2.s stage3.s == 0`）。
   - `.venv/bin/pytest tests/ilisp/test_ulisp_codegen.py`: ILisp AOT 連携テスト全 18 件 PASS。
   - `make check_format` & `make py_compile`: 静的解析 0 エラー PASS。

---

## 6. 完了条件 / Success Criteria (DoD)
- [x] クロージャ変換が S式 $\to$ S式の独立した Nanopass として `passes/03_closure_convert.scm` に実装されていること。
- [x] `05_codegen.scm` から動的クロージャ解析・`*lambdas*` 遅延リストが完全排除され、フラットな手続きのみをコード生成すること。
- [x] 自由変数アクセスが明示的な `%closure-ref` 経由で行われていること。
- [x] `ulisp/test.sh` の全テスト（高階関数・カリー化・letrec 再帰・TCO 深度テスト含む）が 100% PASS すること。
- [x] `ulisp/bootstrap.sh` の不動点検証（Stage 2 と Stage 3 の bit-for-bit 完全一致）が成立すること。
- [x] `tests/ilisp/test_ulisp_codegen.py` が全 18 件 PASS すること。
- [x] すべての品質ゲート（`make check_format`, `make py_compile`）を通過すること。

---

## 7. 実装・検証完了報告 / Completion Report
- **新設 Nanopass**: `ulisp/passes/03_closure_convert.scm` を実装。ネストされたラムダ式をすべてトップレベルの `(%function label params body)` 定義へとリフト（Lambda Lifting）し、自由変数を `%closure-ref` に変換。
- **Pass 5 (Codegen) の純化**: `*lambdas*` グローバルリストや遅延コンパイルキュー、`compile-lambda-named` / `compile-letrec` を完全削除。`%make-closure`, `%closure-ref`, `%closure-set!` のアセンブリ生成のみを担当するプレーンなコード生成器へ純化。
- **検証実績**:
  - `tests/ilisp/test_ulisp_codegen.py`: 全 18 テスト PASS (17.31s)。
  - `ulisp/bootstrap.sh`: Stage 1 $\to$ Stage 2 $\to$ Stage 3 ブートストラップ完了。Stage 2 と Stage 3 のアセンブリ出力が **完全一致（bit-for-bit identical, diff 0件）** を確認。
  - `ulisp/test.sh`: Phase 1 〜 Phase 7 全テスト PASS。
  - `make check_format && make py_compile`: 正常終了 (exit code 0)。
