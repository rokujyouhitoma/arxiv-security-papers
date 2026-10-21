---
ID: 588
種別: Bug
優先度: High
ステータス: Closed
---

# [BUG/FIX] 論理積構文 (and) の脱糖漏れによる LIR 未束縛変数例外 (Unbound variable in LIR: and) の解消 (ID: 588)

## 1. 概要 / Summary
`./test.sh` および `./test_c.sh` を実行した際、論理積式 `(and)` および `(and #t #t)` において以下のコンパイル・実行時不整合が発生し、テストスイートが停止する不具合を解消する。

1. **`./test.sh` (Step 10: Logical Desugaring)**:
   - `assert "#t" "(and)"` を評価した際、`bin/ulisp-boot` が `#f`（戻り値 47 / `0x2F`）を出力するバイナリを生成し、`[FAIL] (and): expected '#t', but got '#f'` で停止する。
2. **`./test_c.sh` (Step 3: Conditionals & Logic)**:
   - `assert_c "#t" "(and #t #t)"` を評価した際、`and` 構文が脱糖パス（Pass 027 / Pass 030 `desugar-all`）で脱糖されず未束縛関数呼び出し `(and ...)` のまま LIR 生成パス (Pass 130) に到達し、以下の例外で停止する。
   ```text
   *** ERROR: unhandled exception: (#<symbol> "Unbound variable in LIR: and" #<symbol>)
   ```

### 再現手順 / Steps to Reproduce
1. `cd ulisp && ./test.sh` を実行する。
   - `assert "#t" "(and)"` で `actual=#f` となり、`[FAIL] (and): expected '#t', but got '#f'` で停止する。
2. `cd ulisp && ./test_c.sh` を実行する。
   - `assert_c "#t" "(and #t #t)"` で `Unbound variable in LIR: and` 例外が発生し、`[COMPILE FAIL]` で停止する。

### 再現環境 / Environment
- OS / Architecture: Linux x86_64
- 対象ファイル: `ulisp/passes/027_desugar_conditionals.scm`, `ulisp/passes/030_desugar.scm`, `ulisp/bin/ulisp-boot`, `ulisp/test.sh`, `ulisp/test_c.sh`

---

## 2. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [ulisp/passes/027_desugar_conditionals.scm](../../../ulisp/passes/027_desugar_conditionals.scm) (条件脱糖パスにおける `and`, `or`, `cond`, `case` の引数マッチングルール定義)
- [x] [ulisp/passes/030_desugar.scm](../../../ulisp/passes/030_desugar.scm) (統合脱糖パス `desugar-all` における引数0個および可変長 `and` の完全脱糖)
- [x] [ulisp/compiler/nanopass.scm](../../../ulisp/compiler/nanopass.scm) (ルールカスケード展開と Catamorphism 再帰呼出の整合性)
- [x] [ulisp/compiler/nanopass_meta.scm](../../../ulisp/compiler/nanopass_meta.scm) (`nanopass-match-pattern-inner` におけるドット対 `,args` およびエリップシス `,args ...` 双方のサポート検証)
- [x] [ulisp/compiler.scm](../../../ulisp/compiler.scm) (統合コンパイラソースの再生成)
- [x] [ulisp/bin/ulisp-boot](../../../ulisp/bin/ulisp-boot) (3-Stage Bootstrap 固定点検証済み最新シードバイナリの再構築・更新)
- [x] [ulisp/test.sh](../../../ulisp/test.sh) (Step 10 の PASS 確認)
- [x] [ulisp/test_c.sh](../../../ulisp/test_c.sh) (Step 3 の PASS 確認)

---

## 3. 根本原因分析 (RCA) / Root Cause Analysis
本不具合は以下の2つの要因が複合して発生していた:

1. **Nanopass パターンマッチングルールにおける引数パターンの網羅性**:
   - `030_desugar.scm` において、`((and . ,args) (Expr (desugar-and args)))` のドット対構文のみが記載されていた場合、Nanopass のマクロ展開エンジンのバージョンや実行環境（Gauche / ILisp）によって `(and)`（引数0個）および `(and a b ...)`（引数複数個）のマッチング境界で非マッチと判定され、Catamorphism デフォルト処理（通常の関数適用 `(and ...)`）へフォールスルーするケースが存在した。
   - `((and ,args ...) (Expr (desugar-and args)))` および `((and . ,args) (Expr (desugar-and args)))` の双方を定義することで、引数0個（`args = '()`）および複数引数の双方が確実に `(desugar-and args)` へ渡される。
2. **リポジトリ内シードバイナリ (`ulisp/bin/ulisp-boot`) の更新未反映**:
   - `make compiler` は `compiler.scm` を連結生成するのみであり、ネイティブ AOT 実行バイナリ `bin/ulisp-boot` は `bootstrap.sh`（または `make bootstrap_verify`）を実行しない限り再コンパイルされない。
   - 既存の `bin/ulisp-boot` が古いコードベースで固定化されていたため、ソースコードを修正しても `test.sh` や `test_c.sh` が古い `bin/ulisp-boot` を優先起動してしまい不整合が継続していた。
   - 最新の `compiler.scm` を Gauche (`gosh`) で実行した場合は `(and)` が `mov rax, 111`（`#t`）、`(and #t #t)` が `#t` へ正常コンパイルされることが確認されている。

---

### 3.1 追加判明した真因 (最終 RCA)
- 自前リーダ [ulisp/lib/reader.scm](../../../ulisp/lib/reader.scm) は `,args` を `(unquote args)` ではなく単一シンボルとして読み込んでいた。ランタイムのシンボルは名前を保持せず `symbol->string` が `"?"` を返すため、Nanopass マッチャのカンマ接頭辞判定が Stage 2 以降で常に失敗し、`desugar-all` の全ルール (`and`/`or`/`cond`/`case`/`let*` 等) が不一致となっていた。
- 修正: リーダに `` ` `` / `,` / `,@` を追加し `(quasiquote x)` / `(unquote x)` / `(unquote-splicing x)` として読み込むようにした (Gauche と同一構造)。
- 検証: `BOOTSTRAP_WITH_GOSH=1 ./bootstrap.sh` 固定点 PASS、`bin/ulisp-boot` で `(and)`=`#t`、`(and #t #t)`=`#t`、`./test.sh` と `./test_c.sh` (118 件) 全 PASS。

## 4. 暫定対処と恒久対策 / Workaround & Permanent Fix
* **暫定対処 (Workaround)**: 
  `FORCE_ILISP=1` を指定して Python インタプリタ経由で実行する（ただし実行速度が大幅に低下する）。
* **恒久対策 (Permanent Fix)**: 
  1. `027_desugar_conditionals.scm` および `030_desugar.scm` において、`and`, `or`, `cond`, `case` に対しエリップシス形式 `(,args ...)` とドット対形式 `(. ,args)` の双方を明示的に登録し、いかなるパーサ・マクロ展開器でも脱落しない構造とする。
  2. `make -C ulisp compiler` で `compiler.scm` を再生成。
  3. `BOOTSTRAP_WITH_GOSH=1 ./bootstrap.sh` を実行し、Stage 1 → Stage 2 → Stage 3 の 3-Stage Bootstrap を完遂。Stage 2 と Stage 3 の出力アセンブリが bit-for-bit で完全一致する固定点を検証した上で、`bin/ulisp-boot` を最新バイナリへ更新する。

---

## 5. 詳細実装方針 / Detailed Implementation Plan
Target Branch: `fix/588-fix-and-syntax-desugaring-unbound-variable-in-lir`

1. **脱糖パス定義の補強**:
   - `ulisp/passes/027_desugar_conditionals.scm` および `ulisp/passes/030_desugar.scm` で以下の規則を網羅:
     ```scheme
     ((cond ,clauses ...) (Expr (desugar-cond clauses)))
     ((cond . ,clauses) (Expr (desugar-cond clauses)))
     ((case ,key ,clauses ...) (Expr (desugar-case key clauses)))
     ((case ,key . ,clauses) (Expr (desugar-case key clauses)))
     ((and ,args ...) (Expr (desugar-and args)))
     ((and . ,args) (Expr (desugar-and args)))
     ((or ,args ...) (Expr (desugar-or args)))
     ((or . ,args) (Expr (desugar-or args)))
     ```
2. **統合コンパイラソース生成**:
   - `make -C ulisp compiler` を実行し、`ulisp/compiler.scm` を再構築。
3. **3-Stage Bootstrap 固定点検証とシードバイナリ更新**:
   - `BOOTSTRAP_WITH_GOSH=1 ./bootstrap.sh` を実行。
   - `stage2.s` と `stage3.s` の `diff` 0件を検証。
   - `build/scheme-stage3` を `bin/ulisp-boot` にコピー・配置。
4. **テストスイート検証**:
   - `echo "(and)" | ULISP_QUIET=1 ./bin/ulisp-boot` のアセンブリ実行結果が `#t` であることを確認。
   - `echo "(and #t #t)" | ULISP_QUIET=1 ./bin/ulisp-boot` のアセンブリ実行結果が `#t` であることを確認。
   - `cd ulisp && ./test.sh` を実行し、Step 10 (Logical Desugaring) が PASS することを確認。
   - `cd ulisp && ./test_c.sh` を実行し、Step 3 (Conditionals & Logic) が PASS することを確認。

---

## 6. 完了条件 / Success Criteria (DoD)
- [x] `echo "(and)" | ./ulisp/bin/ulisp-boot` が `#t` を返却し、`Unbound variable in LIR: and` 例外や `#f` 誤判定が発生しないこと
- [x] `echo "(and #t #t)" | ./ulisp/bin/ulisp-boot` が `#t` を返却すること
- [x] `cd ulisp && ./test.sh` の Step 10: Logical Desugaring がすべて PASS すること
- [x] `cd ulisp && ./test_c.sh` の Step 3: Conditionals & Logic がすべて PASS すること
- [x] 3-Stage Bootstrap 固定点検証（Stage 2 と Stage 3 の bit-for-bit 完全一致）が 100% 成功し、`bin/ulisp-boot` が最新化されていること
- [x] すべてのファイル参照およびドキュメントリンクにおいて相対パスのみを使用していること
