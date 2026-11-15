---
ID: 864
種別: Feature
優先度: Medium
ステータス: Open (New)
---

# [FEAT/ENH] SRFI 48 中級フォーマット文字列 API ((scheme format)) の実装 (ID: 864)

## 1. 概要 / Summary
R7RS-large Orange Docket に規定される SRFI 48 (Intermediate Format Strings) は、SRFI 28 (Basic Format Strings) を拡張し、数値基数フォーマット (`~d`, `~x`, `~o`, `~b`)、浮動小数点数表現 (`~f`), タブ・改行制御、および間接フォーマット (`~?`) を提供する標準的な中級書式化文字列 API である。
先行 Issue #654 で SRFI 28 は実装されたが、数値フォーマット指定子を含む SRFI 48 は「× (未サポート)」のままである。
本 Issue では、SRFI 48 準拠の `format` 手続きおよび `(scheme format)`, `(srfi 48)` ライブラリを実装する。

---

## 2. トレーサビリティ / Traceability
- 関連仕様:
  - R7RS-large Orange Docket: `(scheme format)`
  - SRFI 48: Intermediate Format Strings
  - [ref_r7rs_compliance.md](../../ulisp/docs/ref_r7rs_compliance.md) §2.4
  - [Issue #654: Implement SRFI 28 Basic Format String](closed/654-implement-srfi-28-basic-format-string.md)
  - [DSN-33 (ULisp 包括設計仕様書)](../designs/DSN-33-ulisp_underlying_x86_native_aot_compiler_architecture_specification.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [ulisp/lib/format.scm](../../ulisp/lib/format.scm)
- [ ] [ulisp/lib/scheme/format.sld](../../ulisp/lib/scheme/format.sld) (新規作成)
- [ ] [ulisp/lib/srfi/48.sld](../../ulisp/lib/srfi/48.sld) (新規作成)
- [ ] [ulisp/tests/test_format.scm](../../ulisp/tests/test_format.scm)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/864-implement-srfi-48-intermediate-format-strings`

1. **ディレクティブパーサの拡張 (`ulisp/lib/format.scm`)**:
   - `~a`/`~s`/`~%`/`~~` (SRFI 28 継承) に加え、以下を追加:
   - `~d`: 10進数表現
   - `~x`: 16進数小文字表現
   - `~o`: 8進数表現
   - `~b`: 2進数表現
   - `~c`: 文字出力
   - `~f`: 浮動小数点数（固定小数点形式）
   - `~t`: タブ文字出力
   - `~?`: フォーマット文字列と引数リストを受け取るネスト書式化
   - `~w`: `write` による書き出し
2. **出力先ディスパッチ**:
   - 第1引数が `#t`（標準出力）、`#f`（文字列構築返却）、出力ポートの場合の処理。
3. **テスト検証**:
   - 全ディレクティブの動作と引数型ミスマッチ時のエラー送出を検証。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] `(scheme format)` および `(srfi 48)` から `format` が利用可能であること。
- [ ] `~d`, `~x`, `~f`, `~?` 等の中級ディレクティブが正確に書式化されること。
- [ ] `test_format.scm` が全 PASS すること。
