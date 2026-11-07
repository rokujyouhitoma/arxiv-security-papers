---
ID: 754
種別: Feature
優先度: High
ステータス: Open (In Progress)
---

# [FEAT/ENH] nanopass-catamorphism-step の HIR 8構文ハードコード撤去と define-language スキーマ駆動再帰走査化 (DSN-33-01 T1.2) (ID: 754)

## 1. 概要 / Summary

[[DSN-33-01] ULisp 階層型パス融合 ＆ DAG 最適化基盤設計書](../designs/DSN-33-01-ulisp_pipeline_pass_nanopass_picopass_dag_architecture.md) の第 8.2 節（課題①・課題③）およびタスク **T1.2** に基づき、[ulisp/compiler/nanopass_meta.scm](../../ulisp/compiler/nanopass_meta.scm) 内の自動再帰走査エンジン `nanopass-catamorphism-step` および文法照合器 `nanopass-production-matches?` から特定言語（HIR / `L_lifted`）のハードコードと暗黙の構文書き換え副作用を完全撤去し、`define-language` の生成規則メタデータに基づく真の**スキーマ駆動カタモルフィズム**へ刷新する。

現在、[ulisp/compiler/nanopass_meta.scm](../../ulisp/compiler/nanopass_meta.scm) には以下の3つの設計上の歪みが存在する：
1. **HIR 8構文のハードコード**: `nanopass-catamorphism-step`（L968-1019）が `lang-in` の `define-language` 定義を参照せず、`quote`, `if`, `begin`, `lambda`, `let`, `letrec`, `set!`, `%program` の8構文だけを `case op` でハードコードしている。そのため LIR（`%block`, `%function`, `%lir-program`）や Backend（`%asm-program`, `%asm-function`, `%section`, `mov` 等）で `define-pass` を使用すると、未マッチの構文が `else` 分岐（汎用関数適用）に落ち、命令タグ記号や終端記号（ラベル名・レジスタ名・仮引数リスト等）自体に対して誤って `call-recurse` が呼ばれてしまう。
2. **カタモルフィズム内の暗黙の脱糖副作用**: `nanopass-catamorphism-step` の `lambda`, `let`, `letrec` 分岐（L978-1001）において、複数式のボディを勝手に `(begin ...)` で包む書き換えが混入しており、[ulisp/frontend/028_desugar_bindings.scm](../../ulisp/frontend/028_desugar_bindings.scm) / [ulisp/frontend/030_desugar.scm](../../ulisp/frontend/030_desugar.scm) の明示的ルールと責務が重複している。
3. **汎用文法チェッカへの `L_lifted` ハードコード混入**: `nanopass-production-matches?`（L396-410）において `(%program ...)` 生成規則が `nanopass-match-subforms` による標準サブフォーム検証をバイパスしており、その帳尻合わせとして `(if (eq? (nanopass-lang-name lang) 'L_lifted) ...)` と `has-unlifted-lambda?` が直接ハードコードされている。

---

## 2. トレーサビリティ / Traceability

- 関連設計書:
  - [[DSN-33-01] ULisp 階層型パス融合 ＆ DAG 最適化基盤設計書](../designs/DSN-33-01-ulisp_pipeline_pass_nanopass_picopass_dag_architecture.md) (第 8.2 節 課題①・課題③, 第 8.4 節, 第 9.2 節 タスク **T1.2**)
- 依存関係:
  - 先行 Issue: [Issue #753 (T1.1: 言語定義ファイルの統廃合と extends 連鎖の確立)](closed/753-consolidate-define-language-files-and-establish-extends-chain.md)
  - 後続 Issue: [Issue #755 (T1.3: 未変更部分木の構造共有と重複 Trace 整理)](755-implement-catamorphism-structural-sharing-and-unify-trace-hooks.md), [Issue #764 (T4.3: Verifier の attopass 化)](764-migrate-verifier-to-attopass-and-eliminate-triple-traversal.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files

- [ ] [ulisp/compiler/nanopass_meta.scm](../../ulisp/compiler/nanopass_meta.scm)
  - `nanopass-production-matches?` から `(%program ...)` 特例バイパスと `'L_lifted` / `has-unlifted-lambda?` ハードコードを撤去し、`nanopass-match-subforms` によるスキーマ駆動サブフォーム検証へ一本化する。
  - `define-language` の生成規則（productions）と照合して非終端記号位置のみを再帰変換・解析する `nanopass-find-matching-production` / `nanopass-schema-reconstruct-subforms` / `nanopass-schema-reconstruct-subpattern` を新設し、`nanopass-catamorphism-step` をスキーマ駆動化する。
- [ ] [ulisp/frontend/028_desugar_bindings.scm](../../ulisp/frontend/028_desugar_bindings.scm)
  - `lambda`, `let`（標準および名前付き）, `letrec` の空ボディ・複数式ボディ正規化が `nanopass-catamorphism-step` の暗黙変換に依存せず明示的ルールで完結することを確認・補完する。
- [ ] [ulisp/frontend/030_desugar.scm](../../ulisp/frontend/030_desugar.scm)
  - `028_desugar_bindings.scm` と同様に `lambda`, `let`, `letrec` の空ボディ（`((lambda ,params) ...)` 等）および複数式ボディ正規化ルールを確認・補完する。
- [ ] [ulisp/compiler/verifier.scm](../../ulisp/compiler/verifier.scm)
  - `verify-closure-ast` 等と `nanopass-ast-valid?` の連携が `'L_lifted` スキーマ検証（`FunctionDecl` および `(- (lambda (x ...) e ...))`）と完全整合することを確認する。
- [ ] [ulisp/docs/spec_nanopass.md](../../ulisp/docs/spec_nanopass.md)
  - スキーマ駆動カタモルフィズム走査仕様を反映する。
- [ ] [ulisp/tests/test_nanopass_framework.scm](../../ulisp/tests/test_nanopass_framework.scm)
  - `L_src` / `L_core` / `L_anf` / `L_lifted` / `L_lir_canonical` / `L_asm_x86` / `L_asm_aarch64` の各構文に対するスキーマ駆動カタモルフィズム走査テスト、および複数式ボディ非改変テストを追加する。

---

## 4. 実装方針 / Implementation Plan

Target Branch: `refactor/754-schema-driven-catamorphism`

1. **`nanopass-production-matches?` からの `'L_lifted` 分岐および `has-unlifted-lambda?` の撤去 ([ulisp/compiler/nanopass_meta.scm](../../ulisp/compiler/nanopass_meta.scm))**:
   - 現在 `nanopass-production-matches?`（L396-410）にある `((eq? head '%program) ...)` 特例分岐を削除し、他のキーワード先頭生成規則と同様に `(nanopass-match-subforms (cdr prod) (cdr expr) lang curr-nt)` でサブフォーム検証を行う。
   - これにより：
     - `L_cst` / `L_src` / `L_core` / `L_anf` の `(%program (d ...) e)` は各 `d` を `Def`、末尾 `e` を `Expr` としてスキーマ検証する。
     - `L_lifted` の `(%program (fn ...) e)` は各 `fn` を `FunctionDecl`（`(%function x (x ...) e)`）、末尾 `e` を `Expr` としてスキーマ検証し、`L_lifted` の `removed-prods` に `'lambda` が登録されているため、関数本体またはメイン式内の未リフト `lambda` がスキーマ検証自体で自動的に拒否される。
   - 不要となった `has-unlifted-lambda?` ヘルパーを削除する。

2. **`define-language` スキーマ駆動カタモルフィズム走査エンジンの実装 ([ulisp/compiler/nanopass_meta.scm](../../ulisp/compiler/nanopass_meta.scm))**:
   - 指定された言語 `lang`（`nanopass-lookup-language` で取得）と非終端記号 `nt-name`（未指定または対象外構文の場合は言語内の全非終端記号を探索）から、入力ノード `ir` にマッチする生成規則 `prod` を特定する `nanopass-find-matching-production` を実装する。
   - マッチした生成規則 `prod` の構造に沿って部分木を再帰変換する `nanopass-schema-transform-node` / `nanopass-schema-transform-subforms` / `nanopass-schema-transform-subpattern` を実装する：
     - `(quote datum)` または `'quote` 先頭規則: クォート内部データ `datum` は走査せず `ir` をそのまま返す。
     - メタ変数 `sym` の分類 (`nanopass-classify-meta-var sym lang`):
       - `'terminal` またはリテラルキーワード（`#f`）: 終端記号（変数名・ラベル名・レジスタ名・定数・オフセット等）なので再帰せずそのまま保持する。
       - `'nonterminal`: 非終端記号位置なので `call-recurse` を適用する。
     - 省略記号パターン `(pat ...)`: 対応するリスト要素それぞれに対して `nanopass-schema-transform-subpattern` を適用する（例: `(let ((x e1) ...) e ...)` では各束縛ペアの `x` を保持し `e1` のみに `call-recurse` を適用し、ボディ `e ...` の各要素に `call-recurse` を適用する。`(%block lbl (x ...) inst ...)` では `lbl` と `(x ...)` を保持し、各 `inst` のみに `call-recurse` を適用する）。
     - 関数適用パターン `(e0 e1 ...)` / `(a0 a ...)`: 先頭 `e0` と各引数 `e1 ...` が非終端記号メタ変数であるためそれぞれに `call-recurse`（終端記号 `a` の場合はそのまま保持）を適用する。
   - 純粋解析モード（`lang-out = '*`）においても、スキーマ生成規則が判明する場合は非終端記号サブフォームのみに対してアキュムレータを引き回す `nanopass-schema-analyze-node` を適用し、終端記号（ラベルやパラメータリスト等）への不要な再帰呼び出しを防止する。
   - 登録済み言語が見つからない場合、またはテスト等でスキーマ外の自由形式 S 式が渡された場合のフォールバックとして、副作用のない汎用 S 式再帰（`quote` 保護＋構造保存再帰）を提供する。

3. **暗黙の複数式ボディ `(begin ...)` 正規化副作用の撤去と Pass 028 / Pass 030 の確認 ([ulisp/frontend/028_desugar_bindings.scm](../../ulisp/frontend/028_desugar_bindings.scm), [ulisp/frontend/030_desugar.scm](../../ulisp/frontend/030_desugar.scm))**:
   - `nanopass-catamorphism-step` から `lambda`, `let`, `letrec` のボディを暗黙に `(begin ...)` で包む処理を削除し、生成規則 `(lambda (x ...) e ...)` 等のとおり各ボディ式 `e` を個別に再帰変換してリスト構造を保存する。
   - [ulisp/frontend/028_desugar_bindings.scm](../../ulisp/frontend/028_desugar_bindings.scm) および [ulisp/frontend/030_desugar.scm](../../ulisp/frontend/030_desugar.scm) において、複数式ボディ（`((lambda ,params ,b1 ,b2 . ,rest) ...)` 等）に加え、空ボディ（`((lambda ,params) ...)`、`((let ,bindings) ...)`、`((letrec ,bindings) ...)`）が渡された場合も `(begin)` へ明示的に正規化されるようルールを補完する。

4. **単体テストの拡充 ([ulisp/tests/test_nanopass_framework.scm](../../ulisp/tests/test_nanopass_framework.scm))**:
   - `L_src` / `L_core` の `lambda` / `let` / `letrec` に対して無関係なパスを実行した際、複数式ボディが勝手に `(begin ...)` に書き換えられず各ボディ式がスキーマ通りに走査されることを検証する。
   - `L_lifted`（`%program`, `%function`）、`L_lir_canonical`（`%lir-program`, `%function`, `%block`, `%mov`, `%add`）、`L_asm_x86`（`%asm-program`, `%asm-function`, `%asm-block`, `mov`）、`L_asm_aarch64` に対して `define-pass` を定義し、ボイラープレート規則を書かなくてもスキーマ駆動カタモルフィズムが末端の命令・式まで正確に走査し、かつラベル名・レジスタ名・パラメータリスト等の終端記号を破壊しないことを検証する。
   - `nanopass-production-matches?` 内に `'L_lifted` や `has-unlifted-lambda?` のハードコードが存在しない状態で、`L_lifted` のスキーマ検証（正常な `%function` の受理と未リフト `lambda` の拒否）が 100% 動作することを検証する。

---

## 5. 完了条件 / Success Criteria (DoD)

- [ ] `nanopass-catamorphism-step` から HIR 8構文（`quote`, `if`, `begin`, `lambda`, `let`, `letrec`, `set!`, `%program`）のハードコード `case` 分岐および暗黙の `(begin ...)` ボディ正規化副作用が撤去され、`define-language` の生成規則メタデータに基づくスキーマ駆動再帰走査が実装されていること。
- [ ] `nanopass-catamorphism-step` が `L_src` / `L_core` だけでなく、`L_anf`, `L_lifted`, `L_lir_canonical`, `L_asm_x86`, `L_asm_aarch64` の構文（`%function`, `%block`, `%lir-program`, `%asm-program` 等）に対しても、`define-language` のスキーマ定義に従って正確に非終端記号の子ノードのみを再帰走査できること。
- [ ] `nanopass-production-matches?` 内に特定言語名（`'L_lifted`）のハードコード分岐や `has-unlifted-lambda?` が存在しないこと。
- [ ] [ulisp/tests/test_nanopass_framework.scm](../../ulisp/tests/test_nanopass_framework.scm) に LIR / Backend / Lifted 言語定義を用いたスキーマ駆動カタモルフィズム走査テストを追加し、既存の全パス単体テスト・結合テストとともに全件 PASS すること。
- [ ] 3大品質ゲート（`make format`, `make static_analysis`, `make test`）および絶対パスリンク 0 件チェックをすべて PASS すること。


