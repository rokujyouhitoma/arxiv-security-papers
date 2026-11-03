---
ID: 703
種別: Feature
優先度: High
ステータス: Closed
---

# [FEAT/ENH] R7RS-large / SRFI 41 (scheme stream) 遅延評価ストリームライブラリの実装 (ID: 703)

## 1. 概要 / Summary

R7RS-large Red Edition に規定される遅延評価ストリーム仕様 **SRFI 41 (Streams)** および標準ライブラリ **`(scheme stream)`** を ULisp AOT メタコンパイラ環境に実装する。
SRFI 41 は、無限列や遅延パイプライン処理を空間リークなく安全に扱うための包括的なストリーム操作 API を提供する。

---

## 2. トレーサビリティ / Traceability

- 関連仕様:
  - R7RS-large Red Edition: [RedEdition.md](https://github.com/johnwcowan/r7rs-work/blob/master/RedEdition.md)
  - SRFI 41 正典仕様書: [SRFI 41: Streams](https://srfi.schemers.org/srfi-41/srfi-41.html)
  - 前提実装: [Issue #550](550-implement-r7rs-lazy-evaluation-delay-force.md) (SRFI-45 遅延評価)
  - ULisp 言語仕様準拠リファレンス: [ref_r7rs_compliance.md](../../../ulisp/docs/ref_r7rs_compliance.md) §2.1, §3

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files

- [x] [ulisp/lib/scheme/stream.sld](../../../ulisp/lib/scheme/stream.sld) (新規 `(scheme stream)` ライブラリ定義)
- [x] [ulisp/lib/srfi/41.sld](../../../ulisp/lib/srfi/41.sld) (新規 `(srfi 41)` エイリアス定義)
- [x] [ulisp/lib/stream.scm](../../../ulisp/lib/stream.scm) (新規 ストリームコア実装)
- [x] [ulisp/Makefile](../../../ulisp/Makefile) (`ULISP_STD_LIBS` への `lib/stream.scm` 統合および `test_srfi_41_streams` ターゲット追加)
- [x] [ulisp/compiler/helpers.scm](../../../ulisp/compiler/helpers.scm) (`builtin-library-name?` への `stream`, `41` 追加)
- [x] [ulisp/tests/test_srfi_41_streams.scm](../../../ulisp/tests/test_srfi_41_streams.scm) (新規 ユニットテストスイート)
- [x] [ulisp/docs/ref_r7rs_compliance.md](../../../ulisp/docs/ref_r7rs_compliance.md) (ステータス更新)

---

## 4. 実装方針 / Implementation Plan

Target Branch: `feat/703-implement-srfi-41-streams`

### Step 1: 基本ストリーム型とコア構文 (`stream-primitive` 相当)
- `<stream>` および `<stream-pare>` レコード型、`stream-null`, `stream-cons`, `stream?`, `stream-null?`, `stream-pair?`, `stream-car`, `stream-cdr`, `stream-lambda` を実装。

### Step 2: 派生ストリーム構文と手続き群 (`stream-derived` 相当)
- 構文 (`define-stream`, `stream`, `stream-let`, `stream-of`) および派生手続き (`list->stream`, `port->stream`, `stream->list`, `stream-from`, `stream-range`, `stream-constant`, `stream-iterate`, `stream-unfold`, `stream-unfolds`, `stream-append`, `stream-concat`, `stream-reverse`, `stream-ref`, `stream-length`, `stream-map`, `stream-for-each`, `stream-fold`, `stream-scan`, `stream-zip`, `stream-filter`, `stream-take`, `stream-take-while`, `stream-drop`, `stream-drop-while`) を完全実装。

---

## 5. 完了条件 / Success Criteria (DoD)

- [x] `(scheme stream)` および `(srfi 41)` ライブラリが定義され、SRFI 41 全標準手続き・マクロがエクスポートされていること。
- [x] 有限・無限ストリーム（フィボナッチ数列、素数の篩、`stream-of` 内包表記等）のテストケースがすべて PASS すること。
- [x] `make -C ulisp test_srfi_41_streams` により AOT ネイティブコンパイル・実行テストが全件 PASS すること。
- [x] `python3 ulisp/scripts/lint_sexpr.py` および `make verify_r7rs_traceability` が 100% PASS し、`ref_r7rs_compliance.md` のステータスが **◎** に更新されること。

