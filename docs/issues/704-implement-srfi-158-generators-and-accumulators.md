---
ID: 704
種別: Feature
優先度: Medium
ステータス: Open (New)
---

# [FEAT/ENH] R7RS-large / SRFI 158 (scheme generator) 汎用ジェネレータ・アキュムレータライブラリの実装 (ID: 704)

## 1. 概要 / Summary

R7RS-large Tangerine Edition において正式採択され、Red Edition の SRFI 121 を完全包含・発展させた **SRFI 158 (Generators and Accumulators)** および標準ライブラリ **`(scheme generator)`** を ULisp AOT メタコンパイラ環境に実装する。
ジェネレータは、呼び出されるたびにシーケンスの次の要素を（末尾では EOF オブジェクト等を）返却する軽量な引数なし手続きであり、アキュムレータは値を 1 つずつ消費して蓄積する手続きである。
現在 ULisp リファレンスにおいて「△ 部分サポート（コルーチン継続で代用可能）」となっているジェネレータ領域を一挙に「◎ 完全サポート」へと引き上げる。

---

## 2. トレーサビリティ / Traceability

- 関連仕様:
  - R7RS-large Tangerine Edition: [TangerineEdition.md](https://github.com/johnwcowan/r7rs-work/blob/master/TangerineEdition.md)
  - SRFI 158 正典仕様書: [SRFI 158: Generators and Accumulators](https://srfi.schemers.org/srfi-158/srfi-158.html)
  - SRFI 121 正典仕様書: [SRFI 121: Generators](https://srfi.schemers.org/srfi-121/srfi-121.html)
  - ULisp 言語仕様準拠リファレンス: [ref_r7rs_compliance.md](../../ulisp/docs/ref_r7rs_compliance.md) §2.1, §2.2

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files

- [ ] [ulisp/lib/scheme/generator.sld](../../ulisp/lib/scheme/generator.sld) (新規 `(scheme generator)` ライブラリ定義)
- [ ] [ulisp/lib/srfi/158.sld](../../ulisp/lib/srfi/158.sld) (新規 `(srfi 158)` エイリアス定義)
- [ ] [ulisp/lib/srfi/121.sld](../../ulisp/lib/srfi/121.sld) (新規 `(srfi 121)` 互換定義)
- [ ] [ulisp/lib/generator.scm](../../ulisp/lib/generator.scm) (新規 ジェネレータ・アキュムレータコア実装)
- [ ] [ulisp/tests/test_generator.scm](../../ulisp/tests/test_generator.scm) (新規 ユニットテストスイート)
- [ ] [ulisp/docs/ref_r7rs_compliance.md](../../ulisp/docs/ref_r7rs_compliance.md) (ステータス更新)

---

## 4. 実装方針 / Implementation Plan

Target Branch: `feat/704-implement-srfi-158-generators-and-accumulators`

1. **ジェネレータコンストラクタ**:
   - `generator`, `circular-generator`, `make-iota-generator`, `make-range-generator`
   - `make-coroutine-generator` (`call/cc` 連携コルーチン)
   - `list->generator`, `vector->generator`, `string->generator`, `bytevector->generator`
2. **ジェネレータ変換器・コンビネータ**:
   - `gcons*`, `gappend`, `gflatten`, `ggroup`, `gmerge`, `gmap`, `gfilter`, `gremove`
   - `gtake`, `gdrop`, `gtake-while`, `gdrop-while`, `gdelete`, `gdelete-neighbor-dups`
3. **ジェネレータコンシューマ**:
   - `generator->list`, `generator->reverse-list`, `generator->vector`, `generator->string`
   - `generator-fold`, `generator-for-each`, `generator-find`, `generator-count`, `generator-any`, `generator-every`
4. **アキュムレータ**:
   - `make-accumulator`, `count-accumulator`, `list-accumulator`, `string-accumulator` 等。

---

## 5. 完了条件 / Success Criteria (DoD)

- [ ] `(scheme generator)`, `(srfi 158)`, `(srfi 121)` ライブラリが定義され、全標準手続きがエクスポートされていること。
- [ ] ジェネレータ生成、合成、変換、およびアキュムレータによる消費のテストケースが PASS すること。
- [ ] AOT ネイティブコンパイルおよび Portable C バックエンドの両方で回帰テストが PASS すること。
- [ ] `make verify_r7rs_traceability` が 100% PASS し、`ref_r7rs_compliance.md` のステータスが **◎** に更新されること。
