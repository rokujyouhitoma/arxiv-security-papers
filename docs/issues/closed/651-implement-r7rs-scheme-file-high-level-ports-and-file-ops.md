---
ID: 651
種別: Feature
優先度: High
ステータス: Closed (Completed)
---

# [FEAT/ENH] R7RS §6.13 / §6.14 (scheme file) 上位ファイルポート API およびファイル操作手続きの実装 (ID: 651)

## 1. 概要 / Summary
R7RS-small §6.13.1 (Ports) および §6.14 (System Interface) で規定されている上位ファイル入出力ポート手続き群、およびファイル管理手続き群を完全実装し、標準ライブラリ `(scheme file)` を 100% 準拠にする。
現状の ULisp では低レベル Linux x86-64 システムコール（`sys-open`, `sys-read`, `sys-write`, `sys-close`）および基本的な `open-input-file` が部分的に実装されているが、ファイル出力ポート（`open-output-file`, `open-binary-output-file`）、高階ポート制御（`call-with-input-file`, `call-with-output-file`, `call-with-port`）、動的カレントポート切り替え（`with-input-from-file`, `with-output-to-file`）、およびファイルシステム操作（`file-exists?`, `delete-file`）が未完備である。
本改修により、ベアメタル Linux 環境におけるファイル I/O エコシステムを完備し、例外安全なポート自動クローズと完全な R7RS 互換性を実現する。

---

## 2. 背景と技術的課題 / Background & Technical Challenges
1. **Linux x86-64 ゼロ libc システムコール統合**:
   - `file-exists?`: `sys_access(pathname, F_OK=0)` (Syscall 21) を使用し、ファイル存在性を高精度に判定。
   - `delete-file`: `sys_unlink(pathname)` (Syscall 87) を使用し、ファイルの安全な削除を実現。失敗時は Scheme 例外（`error`）をシグナル。
   - `open-output-file`: `sys_open(pathname, flags, mode)` (Syscall 2) で `O_WRONLY | O_CREAT | O_TRUNC` (577) およびパーミッション 0666 (438) でオープン。
2. **ファイル出力ポート (`%file-output-port`) とバッファリング**:
   - `port.scm` に `%file-output-port` レコード型を新設。4096 バイトの内部バッファを持ち、満杯時の自動フラッシュおよび `flush-output-port` / `close-port` 時のフラッシュを保証。
   - `port-write-char` および `port-write-string` を拡張し、`%file-output-port` への出力をサポート。
3. **動的カレントポート連携 (`parameterize`)**:
   - `current-input-port` および `current-output-port` を引数なし取得・引数あり更新が可能なプロトコルに拡張し、`parameterize`（Pass 029）による動的切り替えと連動。
   - 引数なしの `read-char`, `peek-char`, `write-char`, `write-string`, `display`, `write`, `newline` が動的に `(current-input-port)` / `(current-output-port)` を参照するように整備。
4. **例外安全なリソース管理 (RAII / Port Auto-Close)**:
   - `call-with-port`, `call-with-input-file`, `call-with-output-file`, `with-input-from-file`, `with-output-to-file` において、`guard` を用いた例外補足を行い、ブロック脱出時（正常終了・例外発生問わず）に確実に `close-port` が呼ばれる安全機構を構築。

---

## 3. セキュリティ要件と脅威分析 / Security Considerations
- **パストラバーサル & 境界外アクセス防止**:
  - Scheme 文字列は ULisp の内部実装において末尾が `\0`（NUL終端）で初期化・アロケートされるため、`%ptr-untag` で直接カーネルシステムコールへ安全に渡せる。
  - バッファ書き込み時のインデックス範囲チェックを徹底し、4096 バイト境界での自動フラッシュを行うことでバッファオーバーフローを防止。
- **ファイルディスクリプタ枯渇 (FD Leak) 防止**:
  - `call-with-port` および `with-*-file` の全高階手続きに `guard` による確実なクローズ機構を義務付け、例外発生時にも fd がリークしないよう保証。

---

## 4. トレーサビリティ / Traceability
- **R7RS-small 仕様**:
  - Section 6.13.1 (Ports: `open-*-file`, `call-with-*-file`, `with-*-file`, `call-with-port`)
  - Section 6.14 (System interface: `file-exists?`, `delete-file`)
  - Section 7.1.7 (Library `(scheme file)`)
- **仕様リファレンス**: [ref_r7rs_compliance.md](../../ulisp/docs/ref_r7rs_compliance.md) §1.3 (6.13.1, 6.13.3, 6.14), §1.4 (`(scheme file)`)
- **関連ライブラリ**:
  - [ulisp/lib/posix.scm](../../ulisp/lib/posix.scm)
  - [ulisp/lib/port.scm](../../ulisp/lib/port.scm)
  - [ulisp/lib/printer.scm](../../ulisp/lib/printer.scm)
  - [ulisp/lib/scheme/file.sld](../../ulisp/lib/scheme/file.sld)
  - [ulisp/lib/scheme/base.sld](../../ulisp/lib/scheme/base.sld)

---

## 5. 影響範囲と関連ファイル / Scope and Affected Files
- [ulisp/lib/posix.scm](../../ulisp/lib/posix.scm): `sys-access` (21), `sys-unlink` (87), `file-exists?`, `delete-file` の追加。
- [ulisp/lib/port.scm](../../ulisp/lib/port.scm):
  - `%file-output-port` レコード構造・述語の定義。
  - `open-output-file`, `open-binary-output-file`, `open-binary-input-file` の実装。
  - `port-write-char`, `port-write-string`, `flush-output-port`, `close-port` の拡張。
  - `current-input-port`, `current-output-port` のパラメータ化セルプロトコル対応。
  - `call-with-port`, `call-with-input-file`, `call-with-output-file`, `with-input-from-file`, `with-output-to-file` の例外安全実装。
  - `read-char`, `peek-char`, `write-char`, `write-string` のデフォルトポートを `(current-input-port)` / `(current-output-port)` に統一。
- [ulisp/lib/printer.scm](../../ulisp/lib/printer.scm): `newline`, `display`, `write` のデフォルト出力先を `(current-output-port)` に統一。
- [ulisp/lib/scheme/file.sld](../../ulisp/lib/scheme/file.sld): `(scheme file)` のエクスポートおよび include 依存関係の整備。
- [ulisp/docs/ref_r7rs_compliance.md](../../ulisp/docs/ref_r7rs_compliance.md): §6.13.1, §6.14, `(scheme file)` のステータスを `◎ 100%` に更新。
- [ulisp/tests/test_file_port.scm](../../ulisp/tests/test_file_port.scm): 新設テストスイート（ファイル作成・読み書き・クローズ・削除・例外安全性・カレントポート切り替え）。
- [ulisp/Makefile](../../ulisp/Makefile): `test_file_port` ターゲット追加および `make test` への統合。

---

## 6. 実装方針 / Implementation Plan
Target Branch: `feat/651-implement-r7rs-scheme-file-high-level-ports-and-file-ops`

1. **POSIX システムコール拡張 (`lib/posix.scm`)**:
   - `sys-access (syscall 21)`: `sys_access(path, mode)`
   - `sys-unlink (syscall 87)`: `sys_unlink(path)`
   - `(define (file-exists? filename) (= (sys-access filename 0) 0))`
   - `(define (delete-file filename) ...)`
2. **ポート抽象とファイル出力ポートの実装 (`lib/port.scm`)**:
   - `%file-output-port` レコード構造: `(list '%file-output-port fd buf-cell len-cell filename binary?)`
   - `open-output-file`: O_WRONLY(1) | O_CREAT(64) | O_TRUNC(512) = 577, mode=438(0666) でオープン。
   - `open-binary-output-file`, `open-binary-input-file` の追加。
   - `port-write-char`, `port-write-string`, `flush-output-port`, `close-port` で `%file-output-port` を処理。
   - `textual-port?` / `binary-port?` のフラグ判定。
3. **パラメータ連動と高階ポート制御**:
   - `*current-input-port-cell*`, `*current-output-port-cell*` を導入し、引数なしで値取得、引数ありで値更新。
   - `call-with-port`: `guard` で保護し、ブロック脱出時に確実に `close-port`。
   - `call-with-input-file` / `call-with-output-file` の実装。
   - `with-input-from-file` / `with-output-to-file`: `parameterize` でカレントポートを一時バインドし、例外安全にクローズ。
4. **テストスイート `tests/test_file_port.scm` の作成**:
   - `file-exists?` と `delete-file` の動作（存在チェック、削除、削除後の非存在確認）。
   - ファイル出力ポートへの文字・文字列書き込みと `flush-output-port`。
   - ファイル入力ポートからの `read-char`, `read-line`, `read-string`。
   - `call-with-input-file` / `call-with-output-file` の動作および自動クローズ。
   - `with-output-to-file` 内での `display` / `write` / `newline` のリダイレクト出力検証。
   - `with-input-from-file` 内での `read` / `read-char` のリダイレクト入力検証。
   - 例外発生時の自動クローズとファイル削除（クリーンアップ）。
5. **Makefile, Bootstrap & ドキュメント更新**:
   - `make test_file_port` を追加し、`make test` に統合。
   - `./bootstrap.sh` による 3-Stage Bootstrap 検証とシードバイナリ更新。
   - `ref_r7rs_compliance.md` の適合度を更新。

---

## 7. 完了条件 / Success Criteria (DoD)
- [x] `file-exists?` および `delete-file` が正常に機能すること。
- [x] `open-output-file` / `open-binary-output-file` でファイルが新規作成・上書きされ、正常にデータがフラッシュされること。
- [x] `call-with-input-file` / `call-with-output-file` が実行され、処理完了後にポートが確実にクローズされていること。
- [x] `with-input-from-file` / `with-output-to-file` によりカレントポートが一時的に切り替わり、標準入出力手続きがファイルと連携すること。
- [x] `tests/test_file_port.scm` の全テストが 100% PASS すること。
- [x] 3-Stage Bootstrap（`bootstrap.sh`）で固定点収束し、`make test` に退行（regressions）がないこと。
- [x] `ref_r7rs_compliance.md` の `(scheme file)` が `◎ 100%` に更新されていること。
- [x] すべてのファイルリンクが相対パスで記述されていること。
