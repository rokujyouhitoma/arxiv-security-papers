---
ID: 739
種別: Bug
優先度: High
ステータス: Closed
---

# [BUG/SEC] ULisp 標準ライブラリ依存順序の整合化および Makefile / テストスクリプトの未束縛識別子エラー修正 (ID: 739)

## 1. 概要 / Summary
Issue #711〜#715 における R7RS 数値塔（`<ratnum>`, `<flonum>`, `<complex>`）導入および Issue #706 の SRFI 193 導入に伴い、`ulisp/lib/string.scm`、`ulisp/lib/printer.scm`、`ulisp/lib/reader.scm` が `ratnum?`、`flonum?`、`compnum?` や数値塔演算手続きを、また `ulisp/lib/posix.scm` が `substring` を参照するようになった。しかし、`ulisp/Makefile` の個別テストターゲット（`test_exceptions`, `test_values`, `test_call_cc`, `test_eqv`, `test_syntax_rules`, `test_let_syntax`, `test_ports`, `test_gc_stress`, `build/ulisp_jit_combined.scm`）や `ulisp/test_c.sh`、`ulisp/test.sh`、`ulisp/stdlib_entry.scm`、`ulisp/entry_core.scm` において、`lib/predicates.scm` / `lib/math.scm` の読み込み順序・包含有無が未更新であったため、`make -C ulisp test` 実行時に `Unbound variable in LIR: ratnum?` や `substring` のコンパイルエラーが発生する問題を修正する。

---

## 2. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [posix.scm](../../../ulisp/lib/posix.scm)
- [x] [string.scm](../../../ulisp/lib/string.scm)
- [x] [Makefile](../../../ulisp/Makefile)
- [x] [test_c.sh](../../../ulisp/test_c.sh)
- [x] [test.sh](../../../ulisp/test.sh)
- [x] [stdlib_entry.scm](../../../ulisp/stdlib_entry.scm)
- [x] [entry_core.scm](../../../ulisp/entry_core.scm)

---

## 3. 再現手順 / Steps to Reproduce
1. `make -C ulisp test_exceptions` または `make -C ulisp test_c` を実行する。
2. `ulisp_fn__pctnumber__gtstring_radix` 内で `Unbound variable in LIR: ratnum?` が発生し、アセンブリまたは C コード生成が異常終了する。

---

## 4. 根本原因分析 (RCA) / Root Cause Analysis
1. `ulisp/lib/string.scm` の `%number->string-radix` が `lib/predicates.scm` で定義された `ratnum?`, `flonum?`, `compnum?` を直接呼び出しているため、`lib/char.scm` と `lib/string.scm` のみを単体インクルードする軽量テスト（`test_c.sh`, `test.sh`, `test_gc_stress` C バックエンド）で未束縛変数エラーとなる。
2. `ulisp/lib/posix.scm` の `%srfi193-strip-scm-ext` / `command-name` / `script-directory` が後続の `lib/string.scm` で定義される `substring` を呼び出しているため、`lib/posix.scm` と `lib/gc.scm` のみをインクルードする `test.sh` Step 26 で未束縛変数エラーとなる。
3. `ulisp/Makefile` の `test_exceptions`〜`test_ports` が `$(ULISP_STD_LIBS)` ではなく旧来の個別ファイル列挙（`lib/predicates.scm` / `lib/math.scm` の欠落または順序逆転）を使用していたため、`lib/printer.scm` / `lib/reader.scm` が要求する数値塔述語・演算が未定義となる。
4. `ulisp/stdlib_entry.scm`、`ulisp/entry_core.scm`、`ulisp/test.sh`、`ulisp/test_c.sh`（`test_stdlib_r7rs.scm`）、および `build/ulisp_jit_combined.scm` でも `lib/predicates.scm` と `lib/math.scm` のインクルード順序・指定が更新されていなかった。

---

## 5. 実装方針 / Implementation Plan
Target Branch: `fix/739-fix-ulisp-stdlib-dependency-order-and-makefile-test-targets`

1. `ulisp/lib/string.scm`: タグ検査ヘルパ `%str-ratnum?`, `%str-flonum?`, `%str-compnum?` を `string.scm` 内部で自己完結定義し、`%number->string-radix` から使用することで、`lib/string.scm` 単体利用時（`lib/predicates.scm` 非包含時）の外部依存を解消する。
2. `ulisp/lib/posix.scm`: `%posix-substring` を内部定義して SRFI 193 ヘルパ内で使用し、`lib/string.scm` 非包含時の前方参照依存を解消する。
3. `ulisp/Makefile`:
   - `test_exceptions`, `test_values`, `test_call_cc`, `test_eqv`, `test_syntax_rules`, `test_let_syntax`, `test_ports` の入力生成に `$(ULISP_STD_LIBS)` を使用するよう統一する。
   - `build/ulisp_jit_combined.scm` の依存リスト先頭に `lib/posix.scm lib/list.scm lib/predicates.scm lib/math.scm` を追加し、`lib/printer.scm` / `lib/reader.scm` の依存を満たす。
4. `ulisp/stdlib_entry.scm` および `ulisp/entry_core.scm`: `(include "lib/predicates.scm")` と `(include "lib/math.scm")` を `(include "lib/list.scm")` の直後へ移動し、`ULISP_STD_LIBS` の順序と一致させる。
5. `ulisp/test.sh` および `ulisp/test_c.sh`:
   - `ulisp/test.sh` のフルライブラリ include 行で `lib/predicates.scm` と `lib/math.scm` を `lib/char.scm` の前へ配置する。
   - `ulisp/test_c.sh` の `test_stdlib_r7rs.scm` 実行時に `lib/predicates.scm` を `lib/equality.scm` / `lib/math.scm` の前に追加する。

---

## 6. 完了条件 / Success Criteria (DoD)
- [x] `make -C ulisp test_exceptions test_values test_call_cc test_eqv test_syntax_rules test_let_syntax test_ports` がすべて PASS すること。
- [x] `make -C ulisp test_gc_stress test_c test_aot test_jit` がすべて PASS すること。
- [x] `make -C ulisp test` が最後までエラーなく完走し PASS すること。

