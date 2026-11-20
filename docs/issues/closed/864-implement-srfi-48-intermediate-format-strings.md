---
ID: 864
種別: Feature
優先度: Medium
ステータス: Closed
---

# [FEAT/ENH] SRFI 48 中級フォーマット文字列 API ((scheme format)) の実装 (ID: 864)

## 1. 概要 / Summary
R7RS-large Orange Docket において文字列・書式化操作の共通標準として審議・策定されている **SRFI 48 (Intermediate Format Strings)** は、先行の SRFI 28 (Basic Format Strings) を大幅に拡張し、実用的な中級書式化文字列 API を提供する標準仕様である。

先行 Issue #654 において基本的な `~a`, `~s`, `~%`, `~~` のみを備える SRFI 28 が実装されたが、以下の重要な中級機能が未対応のままとなっており、`ulisp/docs/ref_r7rs_compliance.md` §2.4 において「× (未サポート)」となっている：
1. **基数指定出力**: 10進数 (`~d`)、16進数 (`~x`)、8進数 (`~o`)、2進数 (`~b`) による数値書式化。
2. **文字およびレイアウト制御**: 文字 (`~c`)、タブ文字 (`~t`)、スペース (`~_`)、先行改行検査付きフレッシュライン (`~&`)。
3. **固定小数点・幅寄せ書式化**: 幅指定および小数点以下桁数丸め・右側ゼロ埋め (`~wF`, `~w,dF`)、複素数表記対応。
4. **構造出力・間接再帰書式化**: 循環データ構造配慮出力 (`~w`)、リストの pretty-print 出力 (`~y`)、フォーマット文字列と引数リストを受け取る間接呼出 (`~?`, `~k`)。
5. **出力先ディスパッチ**: 第1引数にポート (`output-port?`)、`#t` (標準出力 `current-output-port`)、`#f` (文字列生成返却)、またはポート省略 (文字列生成返却) を許容する多重ディスパッチ。
6. **自己文書化ヘルプ**: サポートされる全ディレクティブの構文一覧を出力するヘルプ機能 (`~h`)。

本 Issue では、純粋 Scheme による完全自律型 SRFI 48 実装を [ulisp/lib/format.scm](../../ulisp/lib/format.scm) に構築し、R7RS-large 標準モジュール `(scheme format)` および `(srfi 48)` として提供する。

---

## 2. トレーサビリティ / Traceability
- **関連標準仕様**:
  - R7RS-large Orange Docket: `(scheme format)`
  - SRFI 48: [Intermediate Format Strings](https://srfi.schemers.org/srfi-48/srfi-48.html) (by Ken Dickey)
  - SRFI 28: [Basic Format Strings](https://srfi.schemers.org/srfi-28/srfi-28.html) (上位互換性保持)
  - [ref_r7rs_compliance.md](../../ulisp/docs/ref_r7rs_compliance.md) §2.4 (Orange Docket 準拠状況: 390 行目)
  - [Issue #654: Implement SRFI 28 Basic Format String](closed/654-implement-srfi-28-basic-format-string.md)
  - [DSN-33 (ULisp 包括設計仕様書)](../designs/DSN-33-ulisp_underlying_x86_native_aot_compiler_architecture_specification.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [ulisp/lib/format.scm](../../ulisp/lib/format.scm) (修正・機能拡張: SRFI 48 完全仕様準拠 `format` 手続き、出力先ディスパッチ、ディレクティブパーサ、`~F` 数値桁数・幅寄せエンジン、`~?` 間接呼出、`~h` ヘルプ)
- [x] [ulisp/lib/srfi/48.sld](../../ulisp/lib/srfi/48.sld) (新規作成: `(srfi 48)` ライブラリ定義、Traceability ヘッダー)
- [x] [ulisp/lib/scheme/format.sld](../../ulisp/lib/scheme/format.sld) (新規作成: `(scheme format)` ライブラリ定義、Traceability ヘッダー)
- [x] [ulisp/lib/srfi/28.sld](../../ulisp/lib/srfi/28.sld) (既存 `(srfi 28)` との上位互換性維持確認)
- [x] [ulisp/tests/test_format.scm](../../ulisp/tests/test_format.scm) (テストスイート拡張: 既存 33 件に加え、基数、文字・制御文字、~F 固定小数点、~? 間接呼出、ポート出力、異常系・境界値テストを追加)
- [x] [ulisp/Makefile](../../ulisp/Makefile) (`lint_sexpr` ターゲットへの `lib/srfi/48.sld` および `lib/scheme/format.sld` の追加)
- [x] [ulisp/docs/ref_r7rs_compliance.md](../../ulisp/docs/ref_r7rs_compliance.md) (SRFI 48 準拠ステータスを `◎` に更新)
- [x] [docs/issues/README.md](README.md) (Issue 台帳更新: ステータス管理)

---

## 4. セキュリティ考慮事項と脅威分析 / Security Considerations & Threat Modeling
フォーマット文字列処理は外部からの入力やシステムログ生成、例外出力等で日常的に使用されるため、以下の脅威ベクトルを分析し防護策を講じる：

1. **フォーマット文字列注入 (Format String Injection)**:
   - *脅威*: 外部から供給された信頼できない文字列が `format-string` として渡された場合、意図しないディレクティブ展開や情報漏洩、予期しない引数消費が発生する恐れがある。
   - *対策*: 厳格な引数検証 (`require-an-arg`) を行い、ディレクティブの要求数と引数リストの要素数が完全一致しない場合は即座にエラー (`error "format: too few arguments"` / `error "format: unused arguments"`) を送出する。
2. **リソース枯渇 (DoS via Memory / String Allocation in `~w,dF`)**:
   - *脅威*: `~99999999F` のように非現実的に巨大な幅や小数点以下桁数が指定された場合、巨大な文字列アロケーションによりヒープ枯渇や GC 圧迫を引き起こす。
   - *対策*: パディング処理における桁数・幅の健全性チェックを行い、不正な負数や極端なパラメータを早期に棄却する。
3. **間接フォーマット (`~?`) による無限再帰・スタックオーバーフロー**:
   - *脅威*: `~?` で循環的なフォーマット指定や再帰呼出が行われた場合、コールスタックが枯渇する。
   - *対策*: `~?` に渡される引数が文字列（フォーマットテンプレート）およびリスト（引数群）であることを厳格に型検査し、消費を保証する。循環データ構造に対しては `~w` による安全なトラバーサルを提供する。
4. **型安全性 (Type Safety Enforcement)**:
   - *脅威*: `~d`, `~x`, `~o`, `~b` に非数値、`~c` に非文字が渡された場合、ランタイムがクラッシュするリスク。
   - *対策*: 各ディレクティブ処理時に `number?` や `char?` による事前バリデーションを行い、型不一致時は安全かつ説明的な例外を送出する。

---

## 5. 仕様定義とアーキテクチャ設計 / Specification & Architecture Design

### 5.1 手続きシグネチャとディスパッチ規則
```scheme
(format [port] format-string arg ...)
```
引数の解釈順序：
1. 引数リストが空の場合: `(error "format: required format-string argument is missing")`
2. 第1引数が文字列の場合:
   - `port` は `#f` とみなされる（結果は文字列として返却される）。
   - 第1引数は `format-string`、残りは `arg ...`。
3. 第1引数が文字列以外の場合:
   - 第1引数は `port`。第2引数は `format-string`。残りは `arg ...`。
   - `port` の許容値:
     - `#t`: `(current-output-port)` に直接出力。返却値は未規定値 (`(if #f #f)`)。
     - `#f`: 内部で `(open-output-string)` を生成し、出力完了後に `(get-output-string port)` を返却。
     - `(output-port? port)` が真のオブジェクト: 当該ポートに出力。返却値は未規定値。
     - それ以外: `(error "format: bad output-port argument" port)`

### 5.2 サポートする全フォーマットディレクティブ一覧
大文字・小文字は等価（大文字に正規化してディスパッチ）。

| ディレクティブ | ニーモニック | 動作・セマンティクス | 引数消費 |
| :--- | :--- | :--- | :---: |
| `~a`, `~A` | Any | `(display arg port)` による人間向け表示 | 1 |
| `~s`, `~S` | Slashified | `(write arg port)` による機械可読表示 | 1 |
| `~w`, `~W` | WriteCircular | 循環データ構造を考慮した表示（`write` または循環保護出力） | 1 |
| `~d`, `~D` | Decimal | 10進数表現 (`(number->string arg 10)`) | 1 |
| `~x`, `~X` | heXadecimal | 16進数表現 (`(number->string arg 16)`) | 1 |
| `~o`, `~O` | Octal | 8進数表現 (`(number->string arg 8)`) | 1 |
| `~b`, `~B` | Binary | 2進数表現 (`(number->string arg 2)`) | 1 |
| `~c`, `~C` | Character | 1文字出力 (`(write-char arg port)`) | 1 |
| `~y`, `~Y` | Yuppify | リストの整形出力 (pretty-print / write) | 1 |
| `~?`, `~k`, `~K` | Indirection | 間接再帰書式化。第1引数は `format-string`、第2引数は引数リスト | 2 |
| `~wF`, `~w,dF` | Fixed | 幅 `w` への左スペースパディング、小数点以下 `d` 桁丸め固定小数点出力 | 1 |
| `~~` | Tilde | チルダ記号 `#\~` を 1 文字出力 | 0 |
| `~t`, `~T` | Tab | タブ文字 (`#\tab` / `(integer->char 9)`) を出力 | 0 |
| `~%` | Newline | 改行文字 (`#\newline`) を出力 | 0 |
| `~&` | Freshline | 直前が出力末尾で改行でなかった場合のみ改行を出力 | 0 |
| `~_` | Space | 空白文字 (`#\space`) を 1 文字出力 | 0 |
| `~h`, `~H` | Help | 全ディレクティブの構文ヘルプ文字列を出力 | 0 |

### 5.3 `~F` ディレクティブのアルゴリズム設計
1. パラメータ構文解析:
   - `~` の後に連続する数字を読み取り、カンマ `,` があれば前者を `width`、後者を `digits` とする。
   - `~F`: `width = 0`, `digits = #f`
   - `~wF`: `width = w`, `digits = #f`
   - `~w,dF`: `width = w`, `digits = d`
2. 文字列引数の場合:
   - `digits` は無視し、文字列の長さが `width` 未満であれば左側に空白文字を埋める (`string-grow`)。
3. 数値引数の場合:
   - 複素数の場合: 実部と虚部をそれぞれ `~0,dF` で書式化し、`+` または `-` と `i` を付加した上で全体を `width` にパディング。
   - `digits` が指定されている場合:
     - 実数を文字列化 (`inexact->string`)。
     - 小数点 `.` の位置および指数部 `e` の位置を検出。
     - 小数点以下の桁数が `digits` 未満の場合は右側に `0` をパディング。
     - 小数点以下の桁数が `digits` 超過の場合は、指定桁数で四捨五入（丸め）。
     - 整数部、小数部、指数部を再結合し、全体を `width` に合わせて左空白パディング。
   - `digits` が省略されている場合:
     - `(number->string real)` をそのまま幅 `width` に左空白パディング。

---

## 6. 実装方針 / Implementation Plan
Target Branch: `feat/864-implement-srfi-48-intermediate-format-strings`

1. **基本基盤と `format.scm` のリファクタリング (`ulisp/lib/format.scm`)**:
   - 既存の SRFI 28 `%format` を SRFI 48 の完全仕様に基づいてリニューアル。
   - `string-grow`, `compose-with-digits`, `format-fixed` ヘルパー関数の実装。
   - `has-newline?` によるフレッシュライン (`~&`) 状態追跡。
   - 引数検証ユーティリティ (`require-an-arg`) の実装。
   - `format` エントリポイントのディスパッチ処理 (`port` 引数の多重化対応、`case-lambda` による variadic 処理)。
2. **モジュール定義ファイル (`.sld`) の配備**:
   - `ulisp/lib/srfi/48.sld`: `(srfi 48)` ライブラリ定義。
   - `ulisp/lib/scheme/format.sld`: `(scheme format)` ライブラリ定義。
   - いずれも `;;; Traceability: ulisp/docs/ref_r7rs_compliance.md` ヘッダーを付与。
   - `ulisp/lib/srfi/28.sld`: 互換性維持確認。
3. **包括的テストスイートの構築・拡張 (`ulisp/tests/test_format.scm`)**:
   - Group 1: 基本文字列およびエスケープなしフォーマット
   - Group 2: エスケープと改行制御 (`~%`, `~~`, `~t`, `~_`, `~&` フレッシュライン)
   - Group 3: `~a` および `~A` (display 表示)
   - Group 4: `~s`, `~S`, および `~w`, `~W` (write / 循環保護出力)
   - Group 5: 基数指定数値フォーマット (`~d`, `~x`, `~o`, `~b`)
   - Group 6: 文字出力 (`~c`) および Pretty-print (`~y`)
   - Group 7: 固定小数点・幅寄せフォーマット (`~F`, `~wF`, `~w,dF`, 複素数対応)
   - Group 8: 間接フォーマット (`~?`, `~k`)
   - Group 9: 出力先ディスパッチ (`#f`, `#t`, 出力ポートオブジェクト)
   - Group 10: ヘルプ出力 (`~h`) およびエラー処理・境界値・セキュリティテスト (引数不足、引数過剰、型不一致、未知ディレクティブ)
4. **ビルドシステム統合と品質検証**:
   - `ulisp/Makefile` の `lint_sexpr` ターゲットに `lib/srfi/48.sld` および `lib/scheme/format.sld` を追加。
   - `make -C ulisp test_format` の全 PASS 確認。
   - `make -C ulisp test_lint_sexpr` および `make -C ulisp test_r7rs_traceability` の全 PASS 確認。
   - `make -C ulisp test` の全 PASS 確認。
   - `ulisp/docs/ref_r7rs_compliance.md` の SRFI 48 ステータスを `◎` に更新。

---

## 7. 完了条件 / Success Criteria (DoD)
- [x] `(scheme format)` および `(srfi 48)` がエクスポートされ、`format` 手続きが利用可能であること。
- [x] 既存の `(srfi 28)` との上位互換性が 100% 保持されていること。
- [x] 出力先ポート引数（`#t`, `#f`, `output-port`、省略）の多重ディスパッチが正確に機能すること。
- [x] `~d`, `~x`, `~o`, `~b` の基数指定数値出力が正しく動作すること。
- [x] `~c`, `~t`, `~_`, `~&` 等の文字・レイアウト制御ディレクティブが仕様通り動作すること。
- [x] `~wF` および `~w,dF` による固定小数点数・幅寄せパディング・四捨五入が正確に動作すること。
- [x] `~?` および `~k` による間接再帰書式化が安全かつ正確に動作すること。
- [x] `~h` によりサポートされるディレクティブのヘルプ文字列が出力されること。
- [x] 引数不足、引数余剰、型不一致に対する堅牢な例外送出が行われること。
- [x] `ulisp/tests/test_format.scm` が拡充され、全テストケースが 100% PASS すること。
- [x] `ulisp/Makefile` の `lint_sexpr` に関連ファイルが登録され、`make -C ulisp test` で自動実行されること。
- [x] `ulisp/docs/ref_r7rs_compliance.md` の SRFI 48 ステータスが `◎` に更新されていること。
- [x] すべてのファイル内リンクが相対パスで記述され、絶対パスが 0 件であること。
