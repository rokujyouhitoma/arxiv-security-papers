---
ID: 852
種別: Feature
優先度: High
ステータス: Open (New)
---

# [FEAT/ENH] R7RS 標準ライブラリ定義 (base.sld, cxr.sld, r5rs.sld) のエクスポート漏れシンボルの補完 (ID: 852)

## 1. 概要 / Summary
R7RS-small 仕様の第 7 章 (Libraries) と ULisp の `.sld` 定義を網羅的に照合した結果、実装が存在するにもかかわらず `.sld` の `export` 節から漏れているシンボルや、仕様上要求される補助構文が未エクスポートとなっている箇所が多数確認された。
- `(scheme base)`: `...`, `=>`, `_`, `else`（補助構文識別子）、`newline`、`string-for-each`、`string-map`、`vector-append`、`vector-for-each`、`vector-map` が未エクスポート。
- `(scheme cxr)`: R7RS §7.1.5 では全 28 種（`caar`, `cadr`, `cdar`, `cddr` を含む）が要求されるが、現在 24 種のみ。
- `(scheme r5rs)`: `ceiling`, `cos`, `denominator`, `floor`, `map`, `quasiquote`, `round` が未エクスポート。
本 Issue ではこれら全標準ライブラリ定義の `export` 句およびインクルード構成を修正し、R7RS-small 仕様に 100% 準拠させる。

---

## 2. トレーサビリティ / Traceability
- 関連仕様:
  - R7RS-small Section 7.1 (Library Syntax: 7.1.1 `(scheme base)`, 7.1.5 `(scheme cxr)`, 7.1.16 `(scheme r5rs)`)
  - [ref_r7rs_compliance.md](../../ulisp/docs/ref_r7rs_compliance.md) §1.4
  - [DSN-33 (ULisp 包括設計仕様書)](../designs/DSN-33-ulisp_underlying_x86_native_aot_compiler_architecture_specification.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [ulisp/lib/scheme/base.sld](../../ulisp/lib/scheme/base.sld)
- [ ] [ulisp/lib/scheme/cxr.sld](../../ulisp/lib/scheme/cxr.sld)
- [ ] [ulisp/lib/scheme/r5rs.sld](../../ulisp/lib/scheme/r5rs.sld)
- [ ] [ulisp/tests/test_stdlib_r7rs.scm](../../ulisp/tests/test_stdlib_r7rs.scm)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/852-complete-missing-r7rs-standard-library-exports-in-base-cxr-and-r5rs`

1. **`base.sld` の修正**:
   - `export` リストに `...`, `=>`, `_`, `else`, `newline`, `string-for-each`, `string-map`, `vector-append`, `vector-for-each`, `vector-map` を追加。
   - `newline` の実体を含む `../printer.scm` を `include` に追加。
2. **`cxr.sld` の修正**:
   - `caar`, `cadr`, `cdar`, `cddr` の 4 種を export に追加し、全 28 手続きを網羅。
3. **`r5rs.sld` の修正**:
   - `ceiling`, `cos`, `denominator`, `floor`, `map`, `quasiquote`, `round` を export に追加。
4. **仕様整合テストの作成**:
   - 各ライブラリからインポートしたシンボルがすべて解決可能であることを検証するスモークテストを追加。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] `(import (scheme base))` 時に `string-map` や `vector-for-each`、`newline` が問題なく呼び出せること。
- [ ] `(import (scheme cxr))` で `caar` 〜 `cddddr` の全 28 手続きが参照可能であること。
- [ ] `(import (scheme r5rs))` で R5RS 規定の全シンボルがインポートできること。
- [ ] テストスイートが全 PASS すること。
