---
ID: 549
種別: Feature
優先度: Medium
ステータス: Closed
---

# [FEAT/ENH] R7RS 準拠の構造化レコード型 (define-record-type) のマクロ脱糖および高速フィールドアクセス機構の実装 (ID: 549)

## 1. 概要 / Summary
R7RS-small (Section 5.5) に規定されているユーザ定義の複合データ型 `define-record-type` を実装する。
ULisp は既にベクタ型（Issue #536）および衛生的マクロ展開器（Issue #533）を備えているため、`define-record-type` はコンパイラ低レイヤに手を加えることなく、一意な型識別タグシンボルを持つ固定長ベクタへの脱糖マクロとして高効率かつ安全に実現可能である。これにより、コンストラクタ、型述語、フィールドアクセサ（getter）、ミューテータ（setter）が Scheme マクロ定義によって完全自動生成される。

---

## 2. トレーサビリティ / Traceability
- **規格仕様**: R7RS-small Section 5.5 "Record-type definitions"
- **設計仕様書**: [DSN-33 (ULISP 包括設計仕様書)](../../docs/designs/DSN-33-ulisp_underlying_x86_native_aot_compiler_architecture_specification.md)
- **関連Issue**: Issue #536 (R7RS ベクタ型の完全実装), Issue #533 (衛生的マクロ展開器)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [ulisp/passes/030_desugar.scm](../../ulisp/passes/030_desugar.scm) (`define-record-type` 脱糖展開エンジン)
- [x] [ulisp/passes/010_library.scm](../../ulisp/passes/010_library.scm) (ライブラリ名前空間リネーム & エクスポート対応)
- [x] [ulisp/passes/020_macro_expander.scm](../../ulisp/passes/020_macro_expander.scm) (コア形式保護)
- [x] [ulisp/compiler.scm](../../ulisp/compiler.scm) (Nanopass 結合ドライバ)
- [x] [ulisp/tests/test_record.scm](../../ulisp/tests/test_record.scm) (新規作成: レコード型ユニットテスト)
- [x] [ulisp/test.sh](../../ulisp/test.sh) (x86 テストランナー追加 & スモークテスト強化)
- [x] [ulisp/test_c.sh](../../ulisp/test_c.sh) (Portable C テストランナー追加)
- [x] [ulisp/bootstrap.sh](../../ulisp/bootstrap.sh) (自己ホストブートストラップのタイムスタンプ依存検証)
- [x] [ulisp/docs/r7rs_specification_compliance.md](../../ulisp/docs/r7rs_specification_compliance.md) (R7RS 適合表更新)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/549-r7rs-define-record-type`

1. **マクロ仕様設計**:
   - `define-record-type <name> (<constructor> <field> ...) <predicate> (<field> <accessor> [<modifier>]) ...` 構文のパース。
   - レコード実体は `#(%%record-type-<name> <field1-val> <field2-val> ...)` というベクタとして表現。
2. **述語・アクセサ・ミューテータの生成**:
   - `<predicate>`: `(lambda (x) (and (vector? x) (> (vector-length x) 0) (eq? (vector-ref x 0) '%%record-type-<name>)))`
   - `<accessor>`: `(lambda (x) (if (<predicate> x) (vector-ref x <index>) (error ...)))`
   - `<modifier>`: `(lambda (x val) (if (<predicate> x) (vector-set! x <index> val) (error ...)))`
3. **性能とアンボクシング**:
   - 将来的なインライン化や型推論（Pass 4b S-Annotator）と協調できるよう、シンプルな `vector-ref` / `vector-set!` 呼び出しに展開。
4. **テストスイート検証**:
   - 不変フィールド、可変フィールド、複数フィールド、シャドウイング等の動作を検証。

---

## 5. 完了条件 / Success Criteria (DoD)
- [x] `(define-record-type ...)` によって正しくコンストラクタ、述語、アクセサ、ミューテータが生成されること
- [x] 生成されたレコード型に対して `predicate?` が型安全に真偽値を判定できること
- [x] フィールドの読み書き（不変・可変）が意図通り行えること
- [x] x86-64 および Portable C の両バックエンドで動作すること
- [x] `make test`, `make test_c`, `make bootstrap` が 100% PASS すること
