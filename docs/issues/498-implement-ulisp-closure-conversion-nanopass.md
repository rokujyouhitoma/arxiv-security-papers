---
ID: 498
種別: Refactoring
優先度: High
ステータス: Open (In Progress)
---

# [REFACTOR] Implement Explicit Closure Conversion Nanopass for ULisp (ID: 498)

## 1. 概要 / Summary
現在、ULisp のクロージャ生成、自由変数キャプチャ、および相互再帰バックパッチの処理は、`ulisp/passes/04_codegen.scm` のコード生成ルーチン（`compile-lambda-named`, `compile-letrec`）の内部で x86-64 アセンブリの出力と密結合した状態で実行されている。

本 Issue では、Chez Scheme 等の正統派セルフホスティング Scheme コンパイラの設計に基づき、**「クロージャ変換（Closure Conversion / Lambda Lifting）パス」**を S式 $\to$ S式の独立した Nanopass として実装・分離する。
ネストした `lambda` をすべてトップレベルのフラットな手続き定義に持ち上げ、明示的な環境引数（`%env`）と環境タプル参照（`%closure-ref`）に変換することで、コード生成器（Codegen）を単なる「フラットな関数の直截なアセンブリ化」へと極限まで単純化する。

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
- [ ] [ulisp/passes/03_closure_convert.scm](file:///workspace/arxiv-security-papers/ulisp/passes/03_closure_convert.scm): 新設する明示的クロージャ変換 S式 $\to$ S式 パス
- [ ] [ulisp/passes/00_helpers.scm](file:///workspace/arxiv-security-papers/ulisp/passes/00_helpers.scm): `%make-closure`, `%closure-ref`, `%closure-set!` 等のプリミティブ述語追加
- [ ] [ulisp/passes/02_analysis.scm](file:///workspace/arxiv-security-papers/ulisp/passes/02_analysis.scm): クロージャ変換で利用する自由変数抽出の連動
- [ ] [ulisp/passes/04_codegen.scm](file:///workspace/arxiv-security-papers/ulisp/passes/04_codegen.scm): 複雑なネストクロージャ生成を全廃し、フラットな `%program` / `%function` の単純コード生成へ純化
- [ ] [ulisp/passes/05_driver.scm](file:///workspace/arxiv-security-papers/ulisp/passes/05_driver.scm): `forms` $\to$ `rewrite-top-level` $\to$ `desugar-all` $\to$ `closure-convert` $\to$ `codegen` 直列パイプライン結合
- [ ] [ulisp/Makefile](file:///workspace/arxiv-security-papers/ulisp/Makefile): パス構成順序と依存関係の更新
- [ ] [ulisp/bootstrap.sh](file:///workspace/arxiv-security-papers/ulisp/bootstrap.sh): 3段階セルフホスティング不動点検証
- [ ] [ulisp/test.sh](file:///workspace/arxiv-security-papers/ulisp/test.sh): 既存テストスイート 100% PASS 保証
- [ ] [tests/ilisp/test_ulisp_codegen.py](file:///workspace/arxiv-security-papers/tests/ilisp/test_ulisp_codegen.py): ILisp AOT バックエンド統合テスト 100% PASS 保証
- [ ] [docs/issues/README.md](file:///workspace/arxiv-security-papers/docs/issues/README.md): Issue 台帳の更新

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
3. **Pass 4 コード生成器の純化**:
   - `04_codegen.scm` 内の `*lambdas*` 遅延リストや環境追跡の特殊ケース（`compile-lambda-named`）を全廃。
   - トップレベルの各 `%function` を一列にコンパイルし、`%make-closure` と `%closure-ref` をプリミティブ演算として直接 x86-64 コード生成。
4. **Pass 5 Driver での直列パイプライン結合**:
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
   - `make check_format` & `make static_analysis`: 静的解析 0 エラー PASS。

---

## 6. 完了条件 / Success Criteria (DoD)
- [ ] クロージャ変換が S式 $\to$ S式の独立した Nanopass として `passes/` に実装されていること。
- [ ] `04_codegen.scm` から動的クロージャ解析・`*lambdas*` 遅延リストが完全排除され、フラットな手続きのみをコード生成すること。
- [ ] 自由変数アクセスが明示的な `%closure-ref` 経由で行われていること。
- [ ] `ulisp/test.sh` の全テスト（高階関数・カリー化・letrec 再帰・TCO 深度テスト含む）が 100% PASS すること。
- [ ] `ulisp/bootstrap.sh` の不動点検証（Stage 2 と Stage 3 の bit-for-bit 完全一致）が成立すること。
- [ ] `tests/ilisp/test_ulisp_codegen.py` が全 18 件 PASS すること。
- [ ] すべての品質ゲート（`make check_format`, `make static_analysis`）を通過すること。
