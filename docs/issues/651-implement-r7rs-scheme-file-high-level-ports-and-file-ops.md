---
ID: 651
種別: Feature
優先度: High
ステータス: Open (New)
---

# [FEAT/ENH] R7RS §6.13 / §6.14 (scheme file) 上位ファイルポート API およびファイル操作手続きの実装 (ID: 651)

## 1. 概要 / Summary
R7RS-small §6.13.1 および §6.14 で規定されているファイル入出力ポート手続き群（`open-input-file`, `open-output-file`, `open-binary-input-file`, `open-binary-output-file`, `call-with-input-file`, `call-with-output-file`, `with-input-from-file`, `with-output-to-file`）およびファイル管理手続き（`file-exists?`, `delete-file`）を完全実装し、標準ライブラリ `(scheme file)` を 100% 準拠にする。
低レベル POSIX システムコール（[ulisp/lib/posix.scm](../../ulisp/lib/posix.scm)）とポート抽象（[ulisp/lib/port.scm](../../ulisp/lib/port.scm)）を統合する。

---

## 2. トレーサビリティ / Traceability
- R7RS-small: Section 6.13.1 (Ports), Section 6.14 (System Interface)
- 仕様リファレンス: [ref_r7rs_compliance.md](../../ulisp/docs/ref_r7rs_compliance.md) §1.3 (6.13.1, 6.14), §1.4 (`(scheme file)`)
- 関連ライブラリ: [ulisp/lib/port.scm](../../ulisp/lib/port.scm), [ulisp/lib/posix.scm](../../ulisp/lib/posix.scm), [ulisp/lib/scheme/file.sld](../../ulisp/lib/scheme/file.sld)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [ulisp/lib/port.scm](../../ulisp/lib/port.scm)
- [ ] [ulisp/lib/posix.scm](../../ulisp/lib/posix.scm)
- [ ] [ulisp/lib/scheme/file.sld](../../ulisp/lib/scheme/file.sld)
- [ ] [ulisp/docs/ref_r7rs_compliance.md](../../ulisp/docs/ref_r7rs_compliance.md)
- [ ] [ulisp/tests/test_file_port.scm](../../ulisp/tests/test_file_port.scm) (新規テスト)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/651-implement-r7rs-scheme-file-high-level-ports-and-file-ops`

1. `open-input-file` / `open-output-file` において、POSIX `sys-open` を呼び出してファイルディスクリプタを取得し、ULisp のポートレコード（テキスト / バイナリフラグ、バッファ、fd）を生成・返却する。
2. `call-with-input-file` / `call-with-output-file` を `call-with-port` を用いて例外安全・確実自動クローズされるように実装。
3. `with-input-from-file` / `with-output-to-file` を `parameterize`（`current-input-port` / `current-output-port`）を用いて実装。
4. `file-exists?` (POSIX `stat`/`access`) および `delete-file` (POSIX `unlink`) をScheme APIとして標準化。
5. `(scheme file)` のエクスポート定義を完備する。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] 一時ファイルへの書き込み・読み取り・削除および例外発生時のポート自動クローズが正常に動作すること。
- [ ] `(scheme file)` の全仕様手続きがエクスポートされ、テストを通過すること。
- [ ] `ref_r7rs_compliance.md` の `(scheme file)` サポート率を 100% に更新すること。

