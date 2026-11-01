---
ID: 660
種別: Feature
優先度: High
ステータス: Open (New)
---

# [FEAT/ENH] R7RS §6.13 バイトベクタポートおよびノンブロッキング入力述語 (char-ready? / u8-ready?) の完全実装 (ID: 660)

## 1. 概要 / Summary
R7RS-small §6.13.1 (Ports) および §6.13.2 (Input Procedures) に準拠し、メモリ上のバイナリバイトベクタポート手続き群（`open-input-bytevector`, `open-output-bytevector`, `get-output-bytevector`）およびノンブロッキング入力可能性述語（`char-ready?`, `u8-ready?`）を完全実装・昇格（△から◎）させる。
現在、バイトベクタポートは基本定義のみで網羅的テストが不足しており、また `char-ready?` / `u8-ready?` はスタブ・部分実装にとどまっているため、POSIX システムコール・内部バッファ残量と協調した厳密な R7RS ポート I/O を確立する。

---

## 2. トレーサビリティ / Traceability
- 関連仕様:
  - R7RS-small §6.13.1: Ports (`open-input-bytevector`, `open-output-bytevector`, `get-output-bytevector`)
  - R7RS-small §6.13.2: Input procedures (`char-ready?`, `u8-ready?`)
  - [ref_r7rs_compliance.md](../../ulisp/docs/ref_r7rs_compliance.md) §1.3.13 入出力とポート
  - [DSN-33 (ULisp 包括設計仕様書)](../../docs/designs/DSN-33-ulisp_underlying_x86_native_aot_compiler_architecture_specification.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [ulisp/lib/port.scm](../ulisp/lib/port.scm) (ポート内部構造、ready 判定ロジック)
- [ ] [ulisp/lib/bytevector.scm](../ulisp/lib/bytevector.scm) (バイトベクタポート実装)
- [ ] [ulisp/lib/posix.scm](../ulisp/lib/posix.scm) (ノンブロッキング poll/select システムコール連携)
- [ ] [ulisp/tests/test_r7rs_bytevector_ports.scm](../ulisp/tests/test_r7rs_bytevector_ports.scm) (新規単体テスト)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/660-implement-r7rs-bytevector-ports-and-ready-predicates`

1. バイトベクタポート:
   - `open-input-bytevector`: 与えられた bytevector をラップし、カーソル位置を管理する入力ポートオブジェクトを生成。
   - `open-output-bytevector`: 可変長動的バッファを持つ出力ポートを生成。
   - `get-output-bytevector`: 現在蓄積されたバイト列をスライス複製して bytevector として返却。
2. 入力レディ述語 (`char-ready?` / `u8-ready?`):
   - メモリポート（文字列・バイトベクタ）: 未読文字/バイトが存在するか EOF に達していれば `#t`。
   - ファイル/標準入力ポート: 内部リードバッファに未読データがある場合は即時 `#t`。空の場合は POSIX `poll` (タイムアウト 0ms) で読み取り可能かノンブロッキング判定。
3. 単体テストを作成し、境界値・EOF 挙動・バイナリ往復を検証。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] `open-input-bytevector`, `open-output-bytevector`, `get-output-bytevector` を用いたバイナリ読み書きが完全動作する
- [ ] `char-ready?` および `u8-ready?` が文字列ポート、バイトベクタポート、ファイル記述子で正確な真偽値を返す
- [ ] `ref_r7rs_compliance.md` のステータスが △ から ◎ に更新される
- [ ] `make test` を通過する

