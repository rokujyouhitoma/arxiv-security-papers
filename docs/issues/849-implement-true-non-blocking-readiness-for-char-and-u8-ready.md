---
ID: 849
種別: Feature
優先度: Medium
ステータス: Open (New)
---

# [FEAT/ENH] char-ready? および u8-ready? のノンブロッキング入力準備状態判定の実装 (ID: 849)

## 1. 概要 / Summary
R7RS §6.13.2 仕様において、`char-ready?` および `u8-ready?` は「`#t` を返した場合、直後の `read-char` / `read-u8` はハング（ブロッキング）しない」ことが保証される述語である。
しかし現状の `ulisp/lib/port.scm`（L722-L728）では、全入力ポートに対して無条件に `#t` を返却するダミースタブとなっており、標準入力やパイプにおいてブロックが発生する規格違反がある。
本 Issue では、ファイルディスクリプタに対する POSIX `poll` / `select` システムコール連携、およびメモリポート／内部バッファの先読み状態検査を導入し、仕様に合致した準備状態判定を実装する。

---

## 2. トレーサビリティ / Traceability
- 関連仕様:
  - R7RS-small Section 6.13.2 (Input procedures: `char-ready?`, `u8-ready?`)
  - [ref_r7rs_compliance.md](../../ulisp/docs/ref_r7rs_compliance.md) §1.3 (6.13.2)
  - [DSN-33 (ULisp 包括設計仕様書)](../designs/DSN-33-ulisp_underlying_x86_native_aot_compiler_architecture_specification.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [ulisp/lib/port.scm](../../ulisp/lib/port.scm)
- [ ] [ulisp/lib/posix.scm](../../ulisp/lib/posix.scm)
- [ ] [ulisp/tests/test_ports.scm](../../ulisp/tests/test_ports.scm)
- [ ] [ulisp/tests/test_r7rs_bytevector_ports.scm](../../ulisp/tests/test_r7rs_bytevector_ports.scm)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/849-implement-true-non-blocking-readiness-for-char-and-u8-ready`

1. **メモリポート (String / Bytevector Ports) の判定**:
   - 内部バッファのインデックスが終端に達していない場合は即座に `#t`、終端に達している場合（EOF）も R7RS 仕様に基づき `#t` を返却。
2. **ファイルポート / 標準入力 (File / Stdin Ports) の判定**:
   - `peek-char` による先読みバッファに未消費データが存在する場合は `#t`。
   - バッファが空の場合は、`ulisp/lib/posix.scm` を通じて `sys-poll`（タイムアウト 0ms）を呼び出し、FD の読み取り可能イベント（POLLIN）を非ブロッキング判定する。
3. **境界条件と例外テスト**:
   - 空文字列ポート、データが残っているパイプ、即時利用不可能な入力に対する判定を検証するテストケースを `test_ports.scm` に拡充。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] `(char-ready?)` および `(char-ready? port)` が入力データ未到着時に `#f` を返すこと。
- [ ] データ到着済みまたは EOF の場合に `#t` を返すこと。
- [ ] `(u8-ready?)` および `(u8-ready? port)` がバイナリポートで同等に機能すること。
- [ ] ポート関連テストがすべて PASS すること。
