# Issue #457: R7RS 入出力ポートシステムと S式 Datum リーダーの実装

## 1. 概要 (Overview)
ILISP はこれまで基本入出力として `prim_display`, `prim_newline`, `prim_write`, `prim_read_char` 等の最小限の標準入出力関数のみを提供していた。
しかし、完全な R7RS 準拠の言語処理系として発展させるためには、ファイルおよび文字列を包括するポート抽象化システム（`Port`）、動的なカレントポート管理、およびポートから S 式 Datum を読み込む `read` 手続き（Datum リーダー）が不可欠である。

本 Issue では、R7RS-small 仕様の第 6.13 節（Input and output）および標準ライブラリ `(scheme read)`, `(scheme file)`, `(scheme base)` に準拠した入出力ポートシステムと Datum リーダーを設計・実装し、高度なファイル I/O およびプログラム解析・自己解釈（Self-Interpretation）の基盤を確立する。

---

## 2. 目的とゴール (Goals)
1. **入出力ポート抽象化 (`ilisp/port.py`)**:
   - `Port` 基底クラスおよび派生クラス群の実装
     - `TextualInputPort`, `TextualOutputPort`
     - `StringInputPort`, `StringOutputPort`
     - `FileInputPort`, `FileOutputPort`
     - `StandardInputPort`, `StandardOutputPort`, `StandardErrorPort`
   - ポート状態・種別判定述語: `port?`, `input-port?`, `output-port?`, `textual-port?`, `binary-port?`, `port-open?`
   - ポート終了手続き: `close-port`, `close-input-port`, `close-output-port`
   - カレントポート管理: `current-input-port`, `current-output-port`, `current-error-port`（パラメータオブジェクト的動的束縛の対応）
   - 文字列ポート操作: `open-input-string`, `open-output-string`, `get-output-string`
   - ファイルポート操作: `open-input-file`, `open-output-file`, `call-with-port`, `call-with-input-file`, `call-with-output-file`, `with-input-from-file`, `with-output-to-file`
2. **S式 Datum リーダー & 文字・行入出力の実装**:
   - `read([port])`: 指定ポート（省略時はカレント入力ポート）から次の 1 つの S 式 Datum をパースして返却。EOF 時は `eof-object` を返却。
   - `eof-object`, `eof-object?`: EOF オブジェクト生成および判定述語。
   - `read-char([port])`, `peek-char([port])`, `read-line([port])`, `read-string(k, [port])`: 文字・行・文字列読み込み。
   - `write-char(char, [port])`, `write-string(string, [port])`, `flush-output-port([port])`: 文字・文字列出力・フラッシュ。
   - `display`, `write`, `newline` のオプショナルポート引数対応。
3. **組み込みライブラリの拡充 (`ilisp/module.py`)**:
   - `(scheme read)`: `read` のエクスポート。
   - `(scheme file)`: ファイルポート操作関数のエクスポート。
   - `(scheme base)`: ポート基本操作・文字列ポート・文字入出力関数のエクスポート。
4. **テストスイートの整備 (`tests/ilisp/test_ports_and_read.py`)**:
   - 文字列ポートに対する S 式 `read`（リスト、シンボル、リテラル、ドット対、マクロ記法）。
   - ファイル一時生成・書き込み・読み込みの一連のラウンドトリップ検証。
   - `call-with-port` および例外発生時のポート自動クローズ挙動検証。
   - `current-input-port` / `current-output-port` の切り替え検証。
5. **品質ゲートと R7RS 仕様網羅マトリクスの更新**:
   - `ilisp/docs/SPEC_R7RS.md` のポートおよび I/O 関連ステータスの反映。

---

## 3. 完了条件 (Definition of Done)
- [x] `ilisp/port.py` にポートクラス群および各種操作関数が実装されている。
- [x] `ilisp/reader.py` の `Reader` が文字列だけでなく入力ポートを直接扱えるよう拡張されている。
- [x] `read`, `read-char`, `peek-char`, `read-line`, `write-char`, `write-string` 等が実装されている。
- [x] `(scheme read)` および `(scheme file)` ライブラリが `LibraryRegistry` に登録されている。
- [x] `tests/ilisp/test_ports_and_read.py` に網羅的なテストが追加され、全テストが 100% PASS すること（全 118 件完全通過）。
- [x] 静的解析（flake8, mypy --strict）をエラー 0 件でパスすること。
- [x] `SPEC_R7RS.md` の仕様準拠状況が更新されていること。

---

## 4. 実装結果サマリー (Implementation Summary)
- **ポート抽象化システム (`ilisp/port.py`)**:
  - `Port` 基底クラス、テキスト入出力ポート（`TextualInputPort`, `TextualOutputPort`）、文字列ポート（`StringInputPort`, `StringOutputPort`）、ファイルポート（`FileInputPort`, `FileOutputPort`）、および標準入出力ポート（`StandardInputPort` 他）を実装。
  - 述語群（`port?`, `input-port?`, `output-port?`, `textual-port?`, `binary-port?`, `port-open?` 他）およびクローズ手続きを完備。
  - `current-input-port`, `current-output-port`, `current-error-port` によるコンテキスト動的カレントポート管理。
  - `call-with-port`, `call-with-input-file`, `call-with-output-file`, `with-input-from-file`, `with-output-to-file` による安全なリソース解放・ポート切り替えを実現。
- **手書き Datum リーダー & 文字/行入出力の汎用ポート統合 (`ilisp/reader.py`)**:
  - `Reader` クラスを `Union[str, TextualInputPort]` 受入および pushback バッファ (`_unread_buf`) モデルへリファクタリング。
  - `read([port])` により任意の入力ポートから S 式 Datum をストリームとして 1 つずつ読み取りパース可能に拡張。EOF 時は `EOF`（`eof-object`）を返却。
  - `read-char`, `peek-char`, `read-line`, `read-string`, `char-ready?`, `write-char`, `write-string`, `flush-output-port`, `newline`, `display`, `write` のポート対応。
- **標準ライブラリの登録 (`ilisp/module.py`)**:
  - `(scheme read)`: `read`
  - `(scheme file)`: ファイルポート操作
  - `(scheme base)`: ポート基本操作・文字列ポート・文字入出力
  - `(scheme write)`: 文字・文字列出力手続きの拡充
- **品質・テスト検証**:
  - `tests/ilisp/test_ports_and_read.py`: 13 件の単体・統合テストを新規作成。
  - ILISP テストスイート **全 118 件が 100% PASS**。
  - `flake8`, `mypy --strict` エラー 0 件達成。
  - `ilisp/docs/SPEC_R7RS.md` を更新し、入出力・システム項目の準拠率を 87% (26/30)、`(scheme read)` と `(scheme file)` を完全準拠 (100%) に昇格。
