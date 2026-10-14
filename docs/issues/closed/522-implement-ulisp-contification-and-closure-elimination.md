---
ID: 522
種別: Feature
優先度: High
ステータス: Closed (Resolved)
---

# [FEAT/ENH] ドミネータ解析に基づくコンティフィケーション (Contification) と局所クロージャ割当完全消去の実装 (ID: 522)

## 1. 概要 / Summary
コーネル大学 CS 6120 (Lesson 5 & SSA) で扱われるドミネータ解析理論を応用し、Scheme の局所手続きをインライン制御フローへと還元する「コンティフィケーション（Contification）」パスを ULisp に実装する。
`letrec` や局所 `lambda` で定義された手続きのうち、すべての呼び出し箇所（Call sites）が共通の基本ブロックによって支配（Dominate）されているものを特定し、独立した関数フレームおよびフラットクロージャオブジェクトのヒープ生成を完全に消去する。呼び出しは同一関数内のローカルジャンプ（`jmp`）へと変換され、ヒープアロケーション・GC プレッシャーおよび間接呼び出しオーバーヘッドをゼロ化する。

---

## 2. トレーサビリティ / Traceability
- **関連設計書**:
  - [DSN-33: ULISP 包括設計仕様書 (第8.4節 Contification)](../../designs/DSN-33-ulisp_underlying_x86_native_aot_compiler_architecture_specification.md)
- **関連先行 Issue**:
  - Issue #491: ULisp Phase 5: 手続き呼び出し・末尾呼び出し最適化 (TCO)・第一級関数とフラットクロージャの実装
  - Issue #498: ULisp コンパイラへの明示的クロージャ変換 (Closure Conversion) Nanopass の実装

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [ulisp/passes/04c_contify.scm](../../../ulisp/passes/04c_contify.scm) (新規作成: コンティフィケーション最適化パス)
- [x] [ulisp/passes/02_analysis.scm](../../../ulisp/passes/02_analysis.scm) (局所呼び出し箇所およびコールグラフ追跡の拡充)
- [x] [ulisp/passes/05_closure_convert.scm](../../../ulisp/passes/05_closure_convert.scm) (コンティファイ済み関数のクロージャ変換バイパス)
- [x] [ulisp/passes/06_lir.scm](../../../ulisp/passes/06_lir.scm) (ローカル継続呼び出し `%cont-call` / `%cont-jump` の LIR 生成)
- [x] [ulisp/passes/08_driver.scm](../../../ulisp/passes/08_driver.scm) (パイプラインへの Pass 04c 統合)
- [x] [ulisp/Makefile](../../../ulisp/Makefile) (PASSES_LIB への 04c_contify.scm 追加および test_contify ターゲット整備)
- [x] [ulisp/tests/passes/test_contify.scm](../../../ulisp/tests/passes/test_contify.scm) (新規作成: コンティフィケーション単体テスト)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/522-ulisp-contification-and-closure-elimination`

1. **エスケープ解析とコールサイト収集 (Pass 02 & Pass 04c)**:
   - 対象: `letrec` および局所 `let` にバインドされた関数シンボル $f$。
   - 解析:
     - $f$ が call site の演算子位置以外（引数や返り値、データ構造内）に出現するか（エスケープ判定）。
     - エスケープしない場合、すべての呼出位置（Call sites）を収集。
   - ドミネータ判定 (Common Dominator / Continuation Context):
     - $f$ への呼出が同一スコープ内または特定の支配コンテキストからのみ発生し、相互再帰外への不正流出がない場合、コンティファイ可能（Contifiable）と判定。
     - 特に単一呼び出し元ループ（自己末尾再帰ループなど）は無条件に支配成立。

2. **中間表現の還元形式 (`%cont-fun`, `%cont-call`)**:
   - `letrec` で定義されたコンティファイ可能関数を `(%cont-fun f params body in-expr)` または特殊タグ付き構造に還元。
   - 呼出箇所 `(f a1 ... ak)` を `(%cont-call f a1 ... ak)` に置換。

3. **クロージャ変換パス (Pass 05) のバイパス**:
   - `05_closure_convert.scm` において、`%cont-fun` は独立した `%function` へのリフトおよび `%make-closure` の生成を完全に抑止。
   - レキシカル環境の自由変数は、親関数の環境参照をそのまま直通共有（親のスタック/レジスタ上に局所配置）。

4. **低レベル IR (Pass 06 LIR) での直接ジャンプ化**:
   - `%cont-call` に対し、間接関数呼出（`%call-closure` や `%jump %rdx`）ではなく、引数をローカルスタック位置に再配置して直接ジャンプ `(%jump-label label)` またはローカルラベルへの制御移行を生成。

5. **パイプライン統合 (Pass 08 & Makefile)**:
   - `passes/04c_contify.scm` を `04b_annotator.scm` または `05b_rtyper.scm` 直後に配置。
   - `test_contify.scm` で、クロージャ生成回数が 0 であること、生成アセンブリが `jmp` であることを検証。

---

## 5. 完了条件 / Success Criteria (DoD)
- [x] 局所ヘルパー関数および `letrec` ループにおいて、フラットクロージャのヒープ割り当て（`%make-closure` / バンプアロケーション）が 0 件に消去されること。
- [x] 間接関数呼び出し（`call [rax + offset]`）が直接ローカルジャンプ（`jmp`）に置き換わること。
- [x] 新規単体テスト `tests/passes/test_contify.scm` を作成し、全テストケースが PASS すること。
- [x] 既存の 140 件の Nanopass 単体テストおよび `bash ulisp/test.sh` が 100% 成功すること。
- [x] 3 段階ブートストラップの決定論的不動点（`diff stage2.s stage3.s == 0`）が 100% 成立すること。
- [x] `docs/issues/README.md` および本 Issue ドキュメントが最新状態に同期されること。

---

## 6. 実装完了サマリー / Completion Summary
1. **Pass 04c (Contification Nanopass)**:
   - `ulisp/passes/04c_contify.scm` を実装。`letrec` で定義された単一自己再帰ループ等の局所関数を特定し、`%cont-fun` / `%cont-call` に還元。
   - 複数手続きが定義されたトップレベル `letrec` や相互再帰環境の相互参照を壊さない安全ガードを確立。
2. **Pass 05 (Closure Conversion)**:
   - `%cont-fun` は独立関数 `%function` へのリフトおよび `%make-closure` の生成を完全抑止。親関数のレキシカル環境を共有。
3. **Pass 06 (LIR Generation)**:
   - `%cont-fun` をローカルラベル `entry-lbl` と `exit-lbl` に展開。
   - `%cont-call` を引数のスタック一時退避・再配置・直接ジャンプ（`%jump entry-lbl`）に変換。間接呼出し・クロージャ呼出しをゼロ化。
4. **Pass 05b (S-RTyper 連携)**:
   - `rtyper-binop` に比較演算子 `(= < <= > >=)` を追加し、生整数と整数リテラルの比較時に自動アンボックスするよう最適化。
5. **テスト & ブートストラップ検証**:
   - `test_contify.scm`（全19項目） PASS。
   - `test_passes.scm`（全140項目） PASS。
   - `test.sh`（Step 1〜27 全件 + 3段階ブートストラップ `diff stage2.s stage3.s == 0`）完全 100% PASS。
