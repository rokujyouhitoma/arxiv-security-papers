---
ID: 703
種別: Feature
優先度: High
ステータス: Open (New)
---

# [FEAT/ENH] R7RS-large / SRFI 41 (scheme stream) 遅延評価ストリームライブラリの実装 (ID: 703)

## 1. 概要 / Summary

R7RS-large Red Edition に規定される遅延評価ストリーム仕様 **SRFI 41 (Streams)** および標準ライブラリ **`(scheme stream)`** を ULisp AOT メタコンパイラ環境に実装する。
SRFI 41 は、無限列や遅延パイプライン処理を空間リークなく安全に扱うための包括的な古典的ストリーム操作 API を提供する。
ULisp では既に [Issue #550](closed/550-implement-r7rs-lazy-evaluation-delay-force.md) において SRFI-45 準拠のトランポリン付き遅延評価プロミス (`delay`, `force`, `delay-force`) を完全ネイティブ実装済みであり、その強力な基盤上にストリーム構文および高階手続きを構築することで、高効率なストリーム実行系を実現する。

---

## 2. トレーサビリティ / Traceability

- 関連仕様:
  - R7RS-large Red Edition: [RedEdition.md](https://github.com/johnwcowan/r7rs-work/blob/master/RedEdition.md)
  - SRFI 41 正典仕様書: [SRFI 41: Streams](https://srfi.schemers.org/srfi-41/srfi-41.html)
  - 前提実装: [Issue #550](closed/550-implement-r7rs-lazy-evaluation-delay-force.md) (SRFI-45 遅延評価)
  - ULisp 言語仕様準拠リファレンス: [ref_r7rs_compliance.md](../../ulisp/docs/ref_r7rs_compliance.md) §2.1

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files

- [ ] [ulisp/lib/scheme/stream.sld](../../ulisp/lib/scheme/stream.sld) (新規 `(scheme stream)` ライブラリ定義)
- [ ] [ulisp/lib/srfi/41.sld](../../ulisp/lib/srfi/41.sld) (新規 `(srfi 41)` エイリアス定義)
- [ ] [ulisp/lib/stream.scm](../../ulisp/lib/stream.scm) (新規 ストリームコア実装)
- [ ] [ulisp/tests/test_stream.scm](../../ulisp/tests/test_stream.scm) (新規 ユニットテストスイート)
- [ ] [ulisp/docs/ref_r7rs_compliance.md](../../ulisp/docs/ref_r7rs_compliance.md) (ステータス更新)

---

## 4. 実装方針 / Implementation Plan

Target Branch: `feat/703-implement-srfi-41-streams`

1. **基本ストリーム型とコア構文 (stream-primitive)**:
   - `stream-null`, `stream-cons` マクロ (`delay-force` を用いた空間リークのない遅延ペア)
   - `stream?`, `stream-null?`, `stream-pair?`
   - `stream-car`, `stream-cdr`
   - `stream-lambda` 構文
2. **派生ストリーム手続き群 (stream-derived)**:
   - 生成・変換: `stream`, `stream-unfold`, `stream-range`, `list->stream`, `stream->list`, `port->stream`
   - アクセス・走査: `stream-ref`, `stream-length`, `stream-append`, `stream-concat`
   - フィルタ・マッピング: `stream-map`, `stream-for-each`, `stream-filter`, `stream-take`, `stream-drop`
   - 高度操作: `stream-fold`, `stream-scan`, `stream-zip`

---

## 5. 完了条件 / Success Criteria (DoD)

- [ ] `(scheme stream)` および `(srfi 41)` ライブラリが定義され、全標準手続き・マクロがエクスポートされていること。
- [ ] 無限ストリーム走査時において O(1) 空間計算量が維持され、空間リークやスタックオーバーフローが発生しないこと。
- [ ] AOT ネイティブコンパイルおよび Portable C バックエンドの両方で回帰テストが PASS すること。
- [ ] `make verify_r7rs_traceability` が 100% PASS し、`ref_r7rs_compliance.md` のステータスが **◎** に更新されること。
