---
ID: 492
種別: Feature
優先度: High
ステータス: Closed (Completed)
---

# [FEAT/ENH] ULisp Phase 6: 自前パーサ (read)・最小 I/O・ポートプリミティブおよび構文脱糖 (cond, let*) の実装 (ID: 492)

## 1. 概要 / Summary

[DSN-33: ULISP (Underlying LISP) x86-64 ネイティブ AOT コンパイラ包括設計仕様書](../../docs/designs/DSN-33-ulisp_underlying_x86_native_aot_compiler_architecture_specification.md) に基づき、ULisp の Phase 6（Step 21〜24: 最小 I/O プリミティブ・文字/ポート・手書き再帰下降 S式リーダー `read`・構文脱糖マクロ `cond`, `let*`, `define`）を実装する。

これまでの Phase 1〜5 により、ネイティブ x86-64 において整数・即値・二項演算・分岐・ヒープペア/リスト・クロージャ/第一級関数・TCO が完成した。
Phase 6 では、コンパイラが外部の Scheme 処理系（ホスト Scheme）の `(read)` に依存せず、自身のネイティブ実行コードだけでソースコード（S式文字列）を直接読み取って AST を構築できるようにするための自己完結型リーダー基盤を確立する。

---

## 2. トレーサビリティ / Traceability

- 関連設計書:
  - [DSN-33: ULISP (Underlying LISP) x86-64 ネイティブ AOT コンパイラ包括設計仕様書](../../docs/designs/DSN-33-ulisp_underlying_x86_native_aot_compiler_architecture_specification.md) (第 3.7 節 手書き再帰下降 S式リーダー (`read`) とシステムコール I/O, 第 4 章 Phase 6, 第 5 章 セルフホスティング検証)
  - [DSN-31: ILISP (Intelligence LISP) R7RS コアアーキテクチャ包括設計仕様書](../../docs/designs/DSN-31-ilisp_r7rs_intelligence_lisp_architecture_specification.md) (第 2.2 節 S式パーサ / リーダー)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files

- [x] [ulisp/runtime.c](../../ulisp/runtime.c) (I/O プリミティブ `ulisp_read_char`, `ulisp_write_char`, `ulisp_peek_char` の C ランタイム連携)
- [x] [ulisp/compiler.scm](../../ulisp/compiler.scm) (Step 21: I/O プリミティブ追加、Step 22: 自前 `read` リーダー関数群、Step 23: 構文脱糖 `cond`, `let*`, 暗黙の `begin` 複数本体式、相互再帰バックパッチ)
- [x] [ulisp/test.sh](../../ulisp/test.sh) (Phase 6 テストスイートの追加: 文字 I/O、トークナイズ、数値/リストの `read`、`cond` / `let*` 構文テスト)
- [x] [ulisp/README.md](../../ulisp/README.md) (ロードマップ進捗状況表の更新)
- [x] [docs/issues/README.md](../../docs/issues/README.md) (Issue 台帳更新)

---

## 4. 実装方針 / Implementation Plan

Target Branch: `feat/492-implement-ulisp-phase6-reader-io-and-desugar`

1. **最小 I/O プリミティブ (Step 21)**:
   - `read-char`: 標準入力から1文字読み取り、Fixnum（文字コード）または EOF オブジェクト（`0x4F`）を RAX に返す。
   - `peek-char`: 1文字先読み（`ungetc` バッファリング）。
   - `write-char`: RAX に入った文字（Fixnum）を標準出力へ出力。
   - `eof-object?`: RAX が EOF 値（`0x4F`）か判定する述語。
   - C ライブラリ呼び出し時のスタックフレーム保護（`sub rsp, frame_shift`）を徹底。
2. **手書き再帰下降 S式リーダー (`read`) (Step 22)**:
   - 空白文字（`#\space`, `#\newline`, `#\tab`, `#\return`）および行コメント（`; ... \n`）のスキップ。
   - アトムの読み取り:
     - 整数（Fixnum）: `[0-9]+`
     - 真偽値: `#t`, `#f`
     - 文字リテラル: `#\a`, `#\space`, `#\newline`
   - 複合構造の読み取り:
     - `(`: リスト読み取りループ（ドット対 `.` に対応、空リスト `()` に対応）
     - `'`: クォート糖衣展開（`'x` を `(cons 'quote (cons x '()))` に展開）
3. **構文脱糖パスの拡充 (Step 23)**:
   - `cond`: `(cond ((test1 e1) (test2 e2) (else e3)))` をネストした `if` に展開。
   - `let*`: `(let* ((x 1) (y (+ x 2))) body)` をネストした `let` に展開。
   - 暗黙の `begin`: `lambda`, `let`, `letrec` における複数本体式（暗黙の `begin`）をサポート。
4. **相互再帰クロージャのヒープ・バックパッチ (Step 24)**:
   - `compile-letrec` において、全クロージャのスタック配置完了後に、相互参照する自由変数スロットをヒープ上で自動バックパッチ。

---

## 5. 完了条件 / Success Criteria (DoD)

- [x] `(read-char)` / `(write-char c)` が正しく動作すること。
- [x] `(cond ...)` が正しく `if` に脱糖されて期待通りの分岐結果を返すこと。
- [x] `(let* ...)` が正しく連鎖的スコープとして脱糖・実行されること。
- [x] S 式リーダー `read` が整数、真偽値、文字、空リスト、真性リスト、ドット対、クォートを正確にパースすること。
- [x] `./test.sh` で Phase 1〜6 の全テストがグリーンであること。
- [x] `ulisp/README.md` の進捗状況表で Phase 6 が完了として反映されていること。
