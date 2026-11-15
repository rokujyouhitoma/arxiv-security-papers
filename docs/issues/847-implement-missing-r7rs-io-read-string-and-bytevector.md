---
ID: 847
種別: Feature
優先度: High
ステータス: Open (New)
---

# [FEAT/ENH] R7RS ポート I/O 未実装手続き (read-string, read-bytevector, read-bytevector!) の実装 (ID: 847)

## 1. 概要 / Summary
R7RS-small §6.13.2 仕様および `(scheme base)` において要求されるポート入力手続き `read-string`、`read-bytevector`、`read-bytevector!` が、仕様書 `ref_r7rs_compliance.md` 上では「◎ 完全サポート」と記載されているにもかかわらず、実際には `ulisp/lib/port.scm` および `ulisp/lib/bytevector.scm` に実装が存在しない。
本 Issue では、テキストポートからの指定文字数読み取り `read-string` およびバイナリポートからのバイトベクタ一括読み取り `read-bytevector`, `read-bytevector!` を完全実装し、R7RS §6.13.2 適合性を確保する。

---

## 2. トレーサビリティ / Traceability
- 関連仕様:
  - R7RS-small Section 6.13.2 (Input procedures)
  - [ref_r7rs_compliance.md](../../ulisp/docs/ref_r7rs_compliance.md) §1.3 (6.13.2 入力手続き)
  - [DSN-33 (ULisp 包括設計仕様書)](../designs/DSN-33-ulisp_underlying_x86_native_aot_compiler_architecture_specification.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [ulisp/lib/port.scm](../../ulisp/lib/port.scm)
- [ ] [ulisp/lib/bytevector.scm](../../ulisp/lib/bytevector.scm)
- [ ] [ulisp/lib/scheme/base.sld](../../ulisp/lib/scheme/base.sld)
- [ ] [ulisp/tests/test_ports.scm](../../ulisp/tests/test_ports.scm)
- [ ] [ulisp/docs/ref_r7rs_compliance.md](../../ulisp/docs/ref_r7rs_compliance.md)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/847-implement-missing-r7rs-io-read-string-and-bytevector`

1. **`read-string` の実装 (`ulisp/lib/port.scm`)**:
   - `(read-string k [port])` の手続き定義。`k` 文字を上限として指定ポートから読み出し、新しくアロケートした文字列として返却。
   - 入力途中で EOF に達した場合は、読み取れた文字のみからなる文字列を返却。1文字も読めずに EOF の場合は `eof-object` を返却。
2. **`read-bytevector` および `read-bytevector!` の実装 (`ulisp/lib/bytevector.scm`)**:
   - `(read-bytevector k [port])`: `k` バイト分の新しいバイトベクタをアロケートして読み込み返却。
   - `(read-bytevector! bv [port [start [end]]])`: 既存バイトベクタの指定範囲に直接バッファ読み込みを行い、実際に読み込んだバイト数を返却。
3. **ユニットテストと仕様ドキュメント同期**:
   - `test_ports.scm` に文字列・バイナリ・EOF 境界条件の検証ケースを追加。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] `(read-string k [port])` が任意のテキストポートに対して正しく動作すること。
- [ ] `(read-bytevector k [port])` および `(read-bytevector! bv [port [start [end]]])` がバイナリポートに対して正しく動作すること。
- [ ] 0 バイト読み出し、部分読み出し、EOF 検出が R7RS §6.13.2 仕様に準拠していること。
- [ ] `test_ports.scm` のテストがすべて PASS すること。
