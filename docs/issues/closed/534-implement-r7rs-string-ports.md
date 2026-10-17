---
ID: 534
種別: Feature
優先度: High
ステータス: Closed
---

# [FEAT/ENH] メモリ上インメモリ構文解析および書式化のための R7RS 文字列ポート (open-input-string / open-output-string) の実装 (ID: 534)

## 1. 概要 / Summary
現在の ULisp は、標準入力（stdin）およびローカルファイル（fd / `open`）からの入出力のみをサポートしており、メモリ上に展開された文字列（論文 Abstract、JSON、メタデータ、S 式テキスト）を直接リーダーで読み取ったり、書式化出力をメモリバッファへ蓄積する機能が欠如している。
本 Issue では、R7RS Section 6.13.1（Ports / String ports）に準拠した文字列入力ポート `(open-input-string str)`、文字列出力ポート `(open-output-string)`、および蓄積文字列取得プリミティブ `(get-output-string port)` を実装する。
これにより、ディスク I/O やファイル生成を一切経由することなく、インメモリでの超高速な S 式パース・構文木変換・フォーマット出力を実現する。

---

## 2. トレーサビリティ / Traceability
- **関連規格**:
  - R7RS Section 6.13.1 (Ports: `open-input-string`, `open-output-string`, `get-output-string`, `port?`, `input-port?`, `output-port?`, `textual-port?`, `close-port`)
  - R7RS Section 6.13.2 (Input: `read`, `read-char`, `peek-char`)
  - R7RS Section 6.13.3 (Output: `display`, `write`, `write-char`, `write-string`, `newline`)
- **関連設計書**:
  - [DSN-33: ULISP 包括設計仕様書 (第4章 I/O およびランタイム機構)](../designs/DSN-33-ulisp_underlying_x86_native_aot_compiler_architecture_specification.md)
  - [DSN-36: 完全ベアメタル自己完結型 Freestanding 実行基盤](../designs/DSN-36-ulisp_baremetal_freestanding_pure_scheme_runtime.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [ulisp/lib/port.scm](../../ulisp/lib/port.scm) (新規作成: 文字列ポート型構造体および入出力プリミティブ・標準述語群)
- [x] [ulisp/lib/reader.scm](../../ulisp/lib/reader.scm) (ポート引数指定 `(port-read port)`, `(read [port])`, `(read-char [port])`, `(peek-char [port])` への対応)
- [x] [ulisp/lib/printer.scm](../../ulisp/lib/printer.scm) (出力先ポート指定 `(display val [port])`, `(write val [port])`, `(write-char val [port])`, `(write-string val [port])`, `(newline [port])` への対応)
- [x] [ulisp/Makefile](../../ulisp/Makefile) (ライブラリ結合順への `lib/port.scm` 追加、テストターゲット追加)
- [x] [ulisp/bootstrap.sh](../../ulisp/bootstrap.sh) (ブートストラップ結合順への `lib/port.scm` 追加)
- [x] [ulisp/test.sh](../../ulisp/test.sh) (テストスクリプト結合順への `lib/port.scm` 追加、文字列ポート単体テスト)
- [x] [ulisp/tests/test_ports.scm](../../ulisp/tests/test_ports.scm) (R7RS 文字列ポート網羅的単体テストスイート新規作成)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/534-ulisp-r7rs-string-ports`

1. **文字列ポートのヒープデータ構造 (`ulisp/lib/port.scm`)**:
   - 入力ポート: `(list '%string-input-port source-str pos-cell len)`
     - `pos-cell` は現在読み出しインデックスを保持するセル `(cons 0 '())`
     - `len` は `(string-length source-str)`
   - 出力ポート: `(list '%string-output-port buf-cell len-cell cap-cell)`
     - `buf-cell` は可変文字列バッファを保持するセル `(cons (make-string init-cap) '())`
     - `len-cell` は現在長を保持するセル `(cons 0 '())`
     - `cap-cell` は現在容量を保持するセル `(cons init-cap '())`
     - 容量超過時は 2 倍拡張バッファを再割り当てして文字列コピーを実行。
   - 標準ポート:
     - `*stdin-port*`: `(list '%standard-input-port 0)`
     - `*stdout-port*`: `(list '%standard-output-port 1)`
   - ポート述語群:
     - `port?`, `input-port?`, `output-port?`, `textual-port?`, `binary-port?`, `port-open?`, `close-port`, `close-input-port`, `close-output-port`
     - `current-input-port`, `current-output-port`

2. **リーダーのポート対応 (`ulisp/lib/reader.scm`)**:
   - `port-read-char`, `port-peek-char`, `port-read` を提供し、ポート引数を受け付けるようリファクタリング。
   - `read-char`, `peek-char`, `read` は多相マクロ（`define-syntax`）またはラッパー関数により省略時は `*stdin-port*`（標準入力）へディスパッチ。

3. **プリンタのポート対応 (`ulisp/lib/printer.scm`)**:
   - `port-write-char`, `port-write-string`, `port-display`, `port-write`, `port-newline` を提供。
   - `write-char`, `write-string`, `display`, `write`, `newline` は多相マクロまたはラッパーにより省略時は `*stdout-port*`（標準出力）へディスパッチ。
   - `(get-output-string port)` は出力ポートの現在長分を `substring` で切り出して返却。

4. **ビルドパイプラインおよびブートストラップ連携**:
   - `Makefile`, `bootstrap.sh`, `test.sh` の結合シーケンスに `lib/port.scm` を組み込み。
   - 既存の全テストケースに対する 100% 後方互換性を保証。

---

## 5. 完了条件 / Success Criteria (DoD)
- [x] `(read (open-input-string "(+ 1 2)"))` が正しく S 式 `(+ 1 2)` を返すこと。
- [x] `(let ((p (open-output-string))) (display "hello" p) (get-output-string p))` が `"hello"` を返すこと。
- [x] インメモリでの `read` がディスク I/O なしで 10,000 回連続実行でき、リークがないこと。
- [x] `port?`, `input-port?`, `output-port?`, `textual-port?`, `close-port` などの述語群が R7RS 準拠で正しく判定されること。
- [x] `make test_ports` (または `make test`) が全 PASS すること。
- [x] 自己ホスティング固定点ブートストラップ（`bootstrap.sh`）が完全一致でパスすること。

