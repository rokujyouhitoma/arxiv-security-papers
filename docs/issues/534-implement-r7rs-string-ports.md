---
ID: 534
種別: Feature
優先度: High
ステータス: Open (New)
---

# [FEAT/ENH] メモリ上インメモリ構文解析および書式化のための R7RS 文字列ポート (open-input-string / open-output-string) の実装 (ID: 534)

## 1. 概要 / Summary
現在の ULisp は、標準入力（stdin）およびローカルファイル（fd / `open`）からの入出力のみをサポートしており、メモリ上に展開された文字列（論文 Abstract、JSON、メタデータ、S 式テキスト）を直接リーダーで読み取ったり、書式化出力をメモリバッファへ蓄積する機能が欠如している。
本 Issue では、R7RS Section 6.13.1（Ports / String ports）に準拠した文字列入力ポート `(open-input-string str)`、文字列出力ポート `(open-output-string)`、および蓄積文字列取得プリミティブ `(get-output-string port)` を実装する。
これにより、ディスク I/O やファイル生成を一切経由することなく、インメモリでの超高速な S 式パース・構文木変換・フォーマット出力を実現する。

---

## 2. トレーサビリティ / Traceability
- **関連規格**:
  - R7RS Section 6.13.1 (Ports: `open-input-string`, `open-output-string`, `get-output-string`)
  - R7RS Section 6.13.2 (Input: `read`, `read-char`, `peek-char`)
- **関連設計書**:
  - [DSN-33: ULISP 包括設計仕様書 (第4章 I/O およびランタイム機構)](../designs/DSN-33-ulisp_underlying_x86_native_aot_compiler_architecture_specification.md)
  - [DSN-36: 完全ベアメタル自己完結型 Freestanding 実行基盤](../designs/DSN-36-ulisp_baremetal_freestanding_pure_scheme_runtime.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [ulisp/lib/port.scm](../../ulisp/lib/port.scm) (新規作成: 文字列ポート型構造体および入出力プリミティブ)
- [ ] [ulisp/lib/reader.scm](../../ulisp/lib/reader.scm) (引数ポート指定 `(read [port])`, `(read-char [port])` への対応)
- [ ] [ulisp/lib/printer.scm](../../ulisp/lib/printer.scm) (出力先ポート指定 `(display val [port])`, `(write val [port])` への対応)
- [ ] [ulisp/passes/07_backend_x86_64.scm](../../ulisp/passes/07_backend_x86_64.scm) (ポートオブジェクトヒープレイアウトの組み込み)
- [ ] [tests/test_bare_metal_ulisp.py](../../tests/test_bare_metal_ulisp.py) (インメモリ文字列パース E2E 単体テスト)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/534-ulisp-r7rs-string-ports`

1. **文字列ポートのヒープデータ構造**:
   - 入力ポート: `[PORT_IN_TAG, source_str, current_pos, length]`
   - 出力ポート: `[PORT_OUT_TAG, dynamic_buf, current_len, capacity]`
2. **リーダー・プリンタのポート引数多相化**:
   - デフォルトポート（未指定時）は従来の標準入出力（stdin=0 / stdout=1）を使用。
   - ポート引数が渡された場合は、ポートタグを検査し、文字列ポートであればインデックス進捗による文字リード/追記バッファライトを実行。
3. **`get-output-string` による文字列抽出**:
   - 出力バッファの現在長分を新しい Scheme 文字列として切り出して返却。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] `(read (open-input-string "(+ 1 2)"))` が正しく S 式 `(+ 1 2)` を返すこと。
- [ ] `(let ((p (open-output-string))) (display "hello" p) (get-output-string p))` が `"hello"` を返すこと。
- [ ] インメモリでの `read` がディスク I/O なしで 10,000 回連続実行でき、リークがないこと。
- [ ] 自己ホスティング固定点ブートストラップ（`bootstrap.sh`）が完全一致でパスすること。
