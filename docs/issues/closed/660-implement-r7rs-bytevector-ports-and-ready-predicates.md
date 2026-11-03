---
ID: 660
種別: Feature
優先度: High
ステータス: Closed (Completed)
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
- [x] [ulisp/lib/port.scm](../ulisp/lib/port.scm) (ポート内部構造、バイトベクタポート入出力、ready 判定ロジック)
- [x] [ulisp/lib/posix.scm](../ulisp/lib/posix.scm) (ノンブロッキング sys-poll システムコール連携)
- [x] [ulisp/lib/scheme/base.sld](../ulisp/lib/scheme/base.sld) (エクスポート宣言更新)
- [x] [ulisp/docs/ref_r7rs_compliance.md](../ulisp/docs/ref_r7rs_compliance.md) (R7RS 準拠状況テーブル更新: △ から ◎)
- [x] [ulisp/tests/test_r7rs_bytevector_ports.scm](../ulisp/tests/test_r7rs_bytevector_ports.scm) (新規単体テスト)
- [x] [ulisp/Makefile](../ulisp/Makefile) (テストターゲット統合)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/660-implement-r7rs-bytevector-ports-and-ready-predicates`

1. **バイトベクタポートの実装**:
   - `open-input-bytevector`:
     - 構造: `(list '%bytevector-input-port bv (cons 0 '()) (bytevector-length bv))`
     - `port-read-char`, `port-peek-char`, `port-read-u8`, `port-peek-u8` で透過的に読み取り。
     - 終端到達時は `eof-object` を返却。
   - `open-output-bytevector`:
     - 構造: `(list '%bytevector-output-port (cons (%make-bytevector 64) '()) (cons 0 '()) (cons 64 '()))`
     - `port-write-u8` および `port-write-char` でバッファ拡張（幾何級数倍加）しながら書き込み。
   - `get-output-bytevector`:
     - 現在蓄積されたバイト数分の新規 bytevector を割り当て、データをスライス複製して返却。
   - ポート種別述語:
     - `bytevector-input-port?`, `bytevector-output-port?`, `binary-port?` を整備。

2. **ノンブロッキング入力可能性述語の実装**:
   - `sys-poll`:
     - Linux x86-64 `sys_poll` (syscall 7) を `ulisp/lib/posix.scm` に実装。
     - `struct pollfd` (fd, events=POLLIN(1), revents=0) をスタックまたはセル上に配置し、timeout=0 (即時リターン) で実行。
   - `port-char-ready?` / `port-u8-ready?`:
     - 文字列ポート / バイトベクタポート: 未読データが存在するか、または既に EOF に達していれば `#t`（R7RS 仕様: 次の read がブロックしないことの保証、EOF の場合も `#t`）。
     - ファイルポート: 内部リードバッファに未読文字・バイトがあれば即座に `#t`。空の場合は対応する `fd` に対して `sys-poll` を実行し、戻り値 > 0 かつ `(POLLIN | POLLHUP | POLLERR)` であれば `#t`、そうでなければ `#f`。
   - `char-ready?`, `u8-ready?` マクロ:
     - 省略時引数は `(current-input-port)` を補完。

3. **単体テストの作成**:
   - `open-input-bytevector` からのバイト読み取り・peek・EOF 判定。
   - `open-output-bytevector` への書き込みと `get-output-bytevector` によるバイトベクタ抽出。
   - `char-ready?` および `u8-ready?` のメモリポート・ファイルポートでの正確な動作検証。

---

## 5. 完了条件 / Success Criteria (DoD)
- [x] `open-input-bytevector`, `open-output-bytevector`, `get-output-bytevector` を用いたバイナリ読み書きが完全動作する
- [x] `char-ready?` および `u8-ready?` が文字列ポート、バイトベクタポート、ファイル記述子で正確な真偽値を返す
- [x] `ref_r7rs_compliance.md` のステータスが △ から ◎ に更新される
- [x] `make test` を通過する
