---
ID: 704
種別: Feature
優先度: Medium
ステータス: Closed
---

# [FEAT/ENH] R7RS-large / SRFI 158 (scheme generator) 汎用ジェネレータ・アキュムレータライブラリの実装 (ID: 704)

## 1. 概要 / Summary

R7RS-large Tangerine Edition において正式採択され、Red Edition の SRFI 121 を完全包含・発展させた **SRFI 158 (Generators and Accumulators)** および標準ライブラリ **`(scheme generator)`** を ULisp AOT メタコンパイラ環境に実装する。
ジェネレータは、呼び出されるたびにシーケンスの次の要素を（末尾では EOF オブジェクトを）返却する軽量な引数なし手続きであり、アキュムレータは値を 1 つずつ消費して蓄積し、`eof-object` を受け取った時点で最終結果オブジェクトを返却する状態付き手続きである。

---

## 2. トレーサビリティ / Traceability

- 関連仕様:
  - R7RS-large Tangerine Edition: [TangerineEdition.md](https://github.com/johnwcowan/r7rs-work/blob/master/TangerineEdition.md)
  - SRFI 158 正典仕様書: [SRFI 158: Generators and Accumulators](https://srfi.schemers.org/srfi-158/srfi-158.html)
  - SRFI 121 正典仕様書: [SRFI 121: Generators](https://srfi.schemers.org/srfi-121/srfi-121.html)
  - ULisp 言語仕様準拠リファレンス: [ref_r7rs_compliance.md](../../../ulisp/docs/ref_r7rs_compliance.md) §2.1, §2.2, §3

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files

- [x] [ulisp/lib/scheme/generator.sld](../../../ulisp/lib/scheme/generator.sld) (新規 `(scheme generator)` ライブラリ定義)
- [x] [ulisp/lib/srfi/158.sld](../../../ulisp/lib/srfi/158.sld) (新規 `(srfi 158)` エイリアス定義)
- [x] [ulisp/lib/srfi/121.sld](../../../ulisp/lib/srfi/121.sld) (新規 `(srfi 121)` 互換定義)
- [x] [ulisp/lib/generator.scm](../../../ulisp/lib/generator.scm) (新規 ジェネレータ・アキュムレータコア実装)
- [x] [ulisp/Makefile](../../../ulisp/Makefile) (`ULISP_STD_LIBS` への `lib/generator.scm` 統合および `test_generator` ターゲット追加)
- [x] [ulisp/compiler/helpers.scm](../../../ulisp/compiler/helpers.scm) (`builtin-library-name?` への `generator`, `121`, `158` 追加)
- [x] [ulisp/tests/test_generator.scm](../../../ulisp/tests/test_generator.scm) (新規 ユニットテストスイート)
- [x] [ulisp/docs/ref_r7rs_compliance.md](../../../ulisp/docs/ref_r7rs_compliance.md) (ステータス更新)

---

## 4. 実装方針 / Implementation Plan

Target Branch: `feat/704-implement-srfi-158-generators-and-accumulators`

### Step 1: ジェネレータコンストラクタ (`ulisp/lib/generator.scm`)
- `generator`, `circular-generator`, `make-iota-generator`, `make-range-generator`, `make-coroutine-generator`, `list->generator`, `vector->generator`, `reverse-vector->generator`, `string->generator`, `bytevector->generator`, `make-for-each-generator`, `make-unfold-generator` を実装。

### Step 2: ジェネレータ変換器・コンビネータ (Operations)
- `gcons*`, `gappend`, `gflatten`, `ggroup`, `gmerge`, `gmap`, `gcombine`, `gfilter`, `gremove`, `gstate-filter`, `gtake`, `gdrop`, `gtake-while`, `gdrop-while`, `gdelete`, `gdelete-neighbor-dups`, `gindex`, `gselect` を実装。

### Step 3: ジェネレータコンシューマ (Consumers) & アキュムレータ (Accumulators)
- `generator->list`, `generator->reverse-list`, `generator->vector`, `generator->vector!`, `generator->string`, `generator-fold`, `generator-for-each`, `generator-map->list`, `generator-find`, `generator-count`, `generator-any`, `generator-every`, `generator-unfold`、および SRFI 158 標準アキュムレータ群を実装。

---

## 5. 完了条件 / Success Criteria (DoD)

- [x] `(scheme generator)`, `(srfi 158)`, `(srfi 121)` ライブラリが定義され、全標準手続きがエクスポートされていること。
- [x] ジェネレータの生成・コルーチン中断再開 (`make-coroutine-generator`)・合成・変換・コンシューマ消費・アキュムレータ蓄積のテストケースがすべて PASS すること。
- [x] `make -C ulisp test_generator` により AOT ネイティブコンパイル・実行テストが全件 PASS すること。
- [x] `python3 ulisp/scripts/lint_sexpr.py` および `make verify_r7rs_traceability` が 100% PASS し、`ref_r7rs_compliance.md` のステータスが **◎** に更新されること。

