---
ID: 862
種別: Feature
優先度: Medium
ステータス: Open (New)
---

# [FEAT/ENH] SRFI 180 RFC 8259 準拠 JSON パーサおよびジェネレータ ((scheme json)) の実装 (ID: 862)

## 1. 概要 / Summary
R7RS-large Orange / Hypnos Docket に規定される SRFI 180 (JSON) は、RFC 8259 規格に完全準拠した JSON データのストリーミングおよびインメモリ双方向パーサ・シリアライザを規定する。
現代の Web API、CTI 脅威インテリジェンス、データ交換において JSON は事実上の標準フォーマットであり、コンパイラおよびツールチェーンの外部連携能力を高める。
本 Issue では、純粋 Scheme 製の高性能 RFC 8259 準拠 JSON ライブラリ `(scheme json)` および `(srfi 180)` を実装する。

---

## 2. トレーサビリティ / Traceability
- 関連仕様:
  - R7RS-large Orange / Hypnos Docket: `(scheme json)`
  - SRFI 180: JSON
  - RFC 8259 (The JavaScript Object Notation Data Interchange Format)
  - [ref_r7rs_compliance.md](../../ulisp/docs/ref_r7rs_compliance.md) §2.4
  - [DSN-33 (ULisp 包括設計仕様書)](../designs/DSN-33-ulisp_underlying_x86_native_aot_compiler_architecture_specification.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [ulisp/lib/json.scm](../../ulisp/lib/json.scm) (新規作成)
- [ ] [ulisp/lib/scheme/json.sld](../../ulisp/lib/scheme/json.sld) (新規作成)
- [ ] [ulisp/lib/srfi/180.sld](../../ulisp/lib/srfi/180.sld) (新規作成)
- [ ] [ulisp/tests/test_srfi_180.scm](../../ulisp/tests/test_srfi_180.scm) (新規作成)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/862-implement-srfi-180-json-parser-and-serializer`

1. **データマッピング規約**:
   - JSON null -> `'null`, false -> `#f`, true -> `#t`
   - JSON array -> Scheme vector
   - JSON object -> 連想リスト (Alist) またはハッシュテーブル
2. **高水準 API**:
   - `json-read`, `json-write`, `string->json`, `json->string`, `bytes->json`, `json->bytes`。
3. **低水準ストリーミング API**:
   - `json-generator`, `json-fold` による巨大 JSON のストリーミング読み出し。
4. **RFC 8259 厳格適合テスト**:
   - Unicode サロゲートペア、エスケープシーケンス、数値パースの境界条件テストを実施。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] `(scheme json)` / `(srfi 180)` からのインポートが可能であること。
- [ ] 不正な JSON 入力に対して適切な `read-error?` が送出されること。
- [ ] 往復テスト (`json->string (string->json s)`) が完全に一致すること。
- [ ] `test_srfi_180.scm` が全 PASS すること。
