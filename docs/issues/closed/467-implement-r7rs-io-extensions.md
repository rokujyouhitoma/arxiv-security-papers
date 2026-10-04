# Issue #467: R7RS 入出力拡張プリミティブの網羅 (R7RS 6.13 / Input and output)

## 1. 概要 (Overview)
R7RS-small 第6.13節「Input and output」で規定されている拡張入出力操作を網羅・完備する。
具体的には、スライス指定対応バルク出力 `write-string`（オプショナル `start`, `end` 対応）、共有・循環参照ラベル付き出力 `write-shared`（`#1=(...)` SRFI-38 datum label 表記）、非検出高速出力 `write-simple`、循環検出付き標準 `write`、ならびにバイナリポートの柔軟な可変長引数スライスI/O (`read-bytevector`, `read-bytevector!`, `write-bytevector`) を実装・完備する。

## 2. 背景・動機 (Background & Motivation)
- **R7RS 6.13 入出力仕様の完全準拠**: 現在 ILISP は基本ポートと `read`, `display`, `read-char`, `write-char` などを提供しているが、`write-shared` や `write-simple` は未実装であり、`write` は Python の `repr` に依存していたため循環リスト等で再帰深度上限（`RecursionError`）に達する課題があった。
- **共有構造・循環参照の安全な印字**: Scheme において `set-car!` や `set-cdr!` で構築される循環リストや複雑な共有グラフを安全に可視化するために、R7RS 規格の Datum Labels（`#1=`, `#1#`）による `write-shared` および `write` の実装が不可欠である。
- **部分文字列・バイトベクタスライスのゼロコピー高効率I/O**: `write-string` や `read-bytevector!`, `write-bytevector` において `start` / `end` インデックスによる部分スライス直接I/Oをサポートし、余分なメモリ確保を避けた高速なストリーム処理を可能にする。

## 3. 要件仕様 (Requirements Specification)
### 3.1 文字列出力拡張
- `(write-string string [port [start [end]]])`:
  - `string` の `[start:end]` 部分（デフォルトは全文字列）を `port`（デフォルトはカレント出力ポート）に出力。`start`/`end` が範囲外の場合はエラー。

### 3.2 共有・循環構造表記と出力手続き (R7RS 6.13.3)
- `(write-simple obj [port])`:
  - 共有・循環構造の検出を行わず、再帰的に Scheme datum 形式で `port` へ出力。
- `(write-shared obj [port])`:
  - オブジェクト内の循環参照および共有部分（2回以上参照される同一オブジェクト: ペア、ベクタ、文字列、バイトベクタ、レコード等）を走査し、`#n=...` で定義し、以降を `#n#` で参照する形式で出力。
- `(write obj [port])`:
  - 循環参照が存在する場合のみラベル `#n=` / `#n#` を用いて循環を表現し、有限共有構造はそのまま展開して出力（R7RS 推奨セマンティクス）。

### 3.3 バイナリポート可変長引数スライス操作
- `(read-bytevector k [port])`:
  - `k` バイト読み込み、バイトベクタまたは EOF を返却。
- `(read-bytevector! bytevector [port [start [end]]])`:
  - 引数の省略パターンに対応:
    - `(read-bytevector! bv)`
    - `(read-bytevector! bv port)`
    - `(read-bytevector! bv port start)`
    - `(read-bytevector! bv port start end)`
  - 実際に読み込まれたバイト数を整数（または EOF）で返却。
- `(write-bytevector bytevector [port [start [end]]])`:
  - 引数の省略パターンに対応:
    - `(write-bytevector bv)`
    - `(write-bytevector bv port)`
    - `(write-bytevector bv port start)`
    - `(write-bytevector bv port start end)`
  - 指定範囲のバイトを `port` に出力。

## 4. 影響範囲・対象ファイル (Target Files)
- `ilisp/port.py`:
  - `write_string` の `start`, `end` 引数サポート
  - `format_datum` 構文構築エンジンおよび `write_simple`, `write_shared`, `write_val` の実装
- `ilisp/env.py`:
  - `prim_write_string` の可変長引数ディスパッチ
  - `prim_write_simple`, `prim_write_shared` の新設・登録
  - `prim_read_bytevector_bang`, `prim_write_bytevector` の柔軟な引数ディスパッチ
  - プリミティブ辞書への登録
- `ilisp/syntax.py`: 予約識別子リストの同期
- `tests/ilisp/test_io_extensions.py`: 新規テストスイート (14件)
- `ilisp/docs/SPEC_R7RS.md`: 第3.12節および標準ライブラリ `(scheme write)` の準拠状況更新
- `docs/issues/closed/467-implement-r7rs-io-extensions.md`: クローズされた本 Issue ファイル

## 5. DoD (Definition of Done)
- [x] `(write-string str [port [start [end]]])` が正常に動作する。
- [x] `write-simple` が共有検出なしで Scheme 形式の出力を生成する。
- [x] `write-shared` が循環リスト・共有構造に対して `#1=(...)` 表記を生成し、無限ループを回避する。
- [x] `write` が循環参照を検知して安全に出力する。
- [x] `read-bytevector!` および `write-bytevector` が任意のオプショナル引数パターン（1〜4引数）で動作する。
- [x] `tests/ilisp/test_io_extensions.py` を含む全テストが 100% PASS。
- [x] `flake8` 0 警告、`mypy --strict` 0 エラー。
- [x] `ilisp/docs/SPEC_R7RS.md` の入出力準拠ステータスが更新される。
