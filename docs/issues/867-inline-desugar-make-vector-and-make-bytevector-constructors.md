---
ID: 867
種別: Feature
優先度: High
ステータス: Open (New)
---

# [FEAT/ENH] make-vector および make-bytevector 充填コンストラクタのインライン脱糖 (ID: 867)

## 1. 概要 / Summary
R7RS 仕様では、`(make-vector k fill)` および `(make-bytevector k fill)` は初期充填値 `fill` を受け取る 2 引数呼び出しをサポートしている。
現在、`frontend/026_desugar_constructors.scm` において、`(make-string k ch)` は `desugar-make-string-fill` によりコンパイラ内部でインラインループ（`letrec loop`）に脱糖されているが、`make-vector` と `make-bytevector` は外部ライブラリ関数 `make-vector-fill` / `make-bytevector-fill` への関数呼び出しに脱糖されている。
このため、`(make-vector 3 42)` や `(make-bytevector 3 42)` といった基本的なコンストラクタ式をコンパイルする際にも標準ライブラリ（`lib/vector.scm` や `lib/bytevector.scm`）の include が必須となり、ポータブル C バックエンド（`test_c`）や最小構成バイナリでのオーバーヘッドの原因となっている。
本 Issue では、`make-vector` および `make-bytevector` の 2 引数フォームを `desugar-make-string-fill` と同様にコンパイラ内部で完全インライン脱糖し、外部関数への依存を解消する。

---

## 2. トレーサビリティ / Traceability
- R7RS Section 6.8 (Vectors): `(make-vector k [fill])`
- R7RS Section 6.9 (Bytevectors): `(make-bytevector k [byte])`
- 関連 Issue: [Issue #866](866-optimize-test-c-library-includes-for-high-speed-execution.md)
- 実装ファイル: [ulisp/frontend/026_desugar_constructors.scm](../../ulisp/frontend/026_desugar_constructors.scm)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [ulisp/frontend/026_desugar_constructors.scm](../../ulisp/frontend/026_desugar_constructors.scm)
- [ ] [ulisp/compiler/verifier.scm](../../ulisp/compiler/verifier.scm)
- [ ] [ulisp/lib/vector.scm](../../ulisp/lib/vector.scm)
- [ ] [ulisp/lib/bytevector.scm](../../ulisp/lib/bytevector.scm)
- [ ] [ulisp/tests/test_passes.scm](../../ulisp/tests/test_passes.scm)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/867-inline-desugar-vector-bytevector-fill`

1. `ulisp/frontend/026_desugar_constructors.scm` に `desugar-make-vector-fill` および `desugar-make-bytevector-fill` を実装：
   - 2 引数 `(make-vector len fill)` を以下のようにインライン脱糖：
     ```scheme
     (let ((l len) (f fill))
       (let ((v (%make-vector l)))
         (letrec ((loop (lambda (i)
                          (if (< i l)
                              (begin
                                (vector-set! v i f)
                                (loop (+ i 1)))
                              v))))
           (loop 0))))
     ```
   - 2 引数 `(make-bytevector len fill)` を同様にインライン脱糖：
     ```scheme
     (let ((l len) (f fill))
       (let ((bv (%make-bytevector l)))
         (letrec ((loop (lambda (i)
                          (if (< i l)
                              (begin
                                (bytevector-u8-set! bv i f)
                                (loop (+ i 1)))
                              bv))))
           (loop 0))))
     ```
2. `desugar-make-vector` および `desugar-make-bytevector` を更新し、1 引数の場合は既存の `%make-vector` / `%make-bytevector`、2 引数の場合は上記インライン脱糖器を呼び出す。
3. `make-vector-fill` および `make-bytevector-fill` は後方互換性のためライブラリ内に定義を残すか、または脱糖により不要化する。
4. 単体テスト `tests/test_passes.scm` および `test_c.sh` にて動作検証。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] `(make-vector 3 42)` がライブラリ include なしでネイティブ C / x86-64 実行可能となり、`#(42 42 42)` を生成すること。
- [ ] `(make-bytevector 3 42)` がライブラリ include なしでネイティブ C / x86-64 実行可能となり、`#u8(42 42 42)` を生成すること。
- [ ] `make -C ulisp test_passes` および `make -C ulisp test_c` が正常に PASS すること。
- [ ] `make -C ulisp bootstrap` による自己ホスト固定点が検証されること。
