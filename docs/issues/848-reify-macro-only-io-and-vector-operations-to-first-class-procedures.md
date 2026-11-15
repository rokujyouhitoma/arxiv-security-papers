---
ID: 848
種別: Feature
優先度: High
ステータス: Open (New)
---

# [FEAT/ENH] マクロ限定 I/O 手続きおよびベクタ操作の第一級手続き (First-Class Procedures) 化 (ID: 848)

## 1. 概要 / Summary
R7RS-small 仕様では、標準入出力手続きやコレクション操作（`write-char`, `write-u8`, `write-string`, `read-line`, `read-u8`, `peek-u8`, `vector-append`, `bytevector-copy!` 等）はすべて高階関数に渡すことができる第一級手続きでなければならない。
しかし現状の ULisp では、これらは `define-syntax`（マクロ）または Pass 026/Pass 030 のコンパイル時構文脱糖としてのみ存在しており、`map` や `apply` に渡した場合に未定義エラーまたは構文エラーとなる。
本 Issue では、これらの操作をランタイムの第一級手続きオブジェクトとして具現化 (reify) し、規格適合の高階関数呼び出しを可能にする。

---

## 2. トレーサビリティ / Traceability
- 関連仕様:
  - R7RS-small Section 6.7 (Strings), 6.8 (Vectors), 6.9 (Bytevectors), 6.13 (Input and output)
  - [ref_r7rs_compliance.md](../../ulisp/docs/ref_r7rs_compliance.md) §1.3
  - [DSN-33 (ULisp 包括設計仕様書)](../designs/DSN-33-ulisp_underlying_x86_native_aot_compiler_architecture_specification.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [ulisp/lib/port.scm](../../ulisp/lib/port.scm)
- [ ] [ulisp/lib/vector.scm](../../ulisp/lib/vector.scm)
- [ ] [ulisp/lib/bytevector.scm](../../ulisp/lib/bytevector.scm)
- [ ] [ulisp/frontend/026_desugar_constructors.scm](../../ulisp/frontend/026_desugar_constructors.scm)
- [ ] [ulisp/tests/test_ports.scm](../../ulisp/tests/test_ports.scm)
- [ ] [ulisp/tests/test_stdlib_r7rs.scm](../../ulisp/tests/test_stdlib_r7rs.scm)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/848-reify-macro-only-io-and-vector-operations-to-first-class-procedures`

1. **ポート操作の第一級化 (`ulisp/lib/port.scm`)**:
   - `write-char`, `write-u8`, `write-string`, `read-line`, `read-u8`, `peek-u8` を `case-lambda` による第一級手続きとして再定義する（オプショナルポート引数をランタイムディスパッチ）。
   - 単純構文マクロ呼び出し形式のインライン展開最適化は維持しつつ、変数参照コンテキストでは正規のクロージャオブジェクトを解決可能にする。
2. **ベクタ・バイトベクタ操作の第一級化 (`ulisp/lib/vector.scm`, `ulisp/lib/bytevector.scm`)**:
   - `vector-append`, `bytevector-append`, `vector-copy!`, `bytevector-copy!` を第一級手続きとして実装し、`apply` や `map` による可変長呼び出しに対応。
3. **高階関数連携の検証**:
   - `(for-each write-char '(#\a #\b #\c))` や `(apply vector-append ...)` などのユニットテストを追加。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] `write-char`, `write-string`, `read-line`, `vector-append` 等が手続きオブジェクトとして `procedure?` で `#t` を返すこと。
- [ ] `(apply write-char ...)` および `(map write-char ...)` が正常に動作すること。
- [ ] 既存のインライン脱糖最適化と矛盾なく共存していること。
- [ ] 全テストスイートが PASS すること。
