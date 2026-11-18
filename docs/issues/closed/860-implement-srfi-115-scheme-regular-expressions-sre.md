---
ID: 860
種別: Feature
優先度: Medium
ステータス: Closed
---

# [FEAT/ENH] SRFI 115 S 式正規表現エンジン (SRE) および (scheme regex) の実装 (ID: 860)

## 1. 概要 / Summary
R7RS-large Tangerine Edition においてテキスト処理・パターン照合の標準として定められている **SRFI 115 (Scheme Regular Expressions)** は、S 式で記述される正規表現 (SRE: Scheme Regular Expressions) のパーサ、コンパイラ、およびマッチングエンジンを規定する。
文字列ベースの正規表現（POSIX / PCRE）と異なり、バックスラッシュによるエスケープ問題がなく、Scheme のリスト・シンボル・文字リテラルと完全に親和し、高い合成可能性と型安全性を誇る。

現行の ULisp においては未実装（`×`）となっており、テキスト抽出や構文解析において高水準な正規表現 API が利用できない状態にある。
本 Issue では、純粋 Scheme による完全自律型 SRE マッチングエンジン（コンパイラ・VM・バックトラック探索・キャプチャ管理）を [ulisp/lib/regex.scm](../../ulisp/lib/regex.scm) に実装し、R7RS-large 標準モジュール `(scheme regex)` および `(srfi 115)` として提供する。

---

## 2. トレーサビリティ / Traceability
- **関連標準仕様**:
  - R7RS-large Tangerine Edition: `(scheme regex)`
  - SRFI 115: [Scheme Regular Expressions](https://srfi.schemers.org/srfi-115/srfi-115.html) (by Alex Shinn)
  - [ref_r7rs_compliance.md](../../ulisp/docs/ref_r7rs_compliance.md) §2.2 (Tangerine Edition 準拠状況)
  - [DSN-33 (ULisp 包括設計仕様書)](../designs/DSN-33-ulisp_underlying_x86_native_aot_compiler_architecture_specification.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [ulisp/lib/regex.scm](../../ulisp/lib/regex.scm) (新規作成: SRE パーサ、コンパイラ、マッチャー、高水準操作手続き群)
- [x] [ulisp/lib/srfi/115.sld](../../ulisp/lib/srfi/115.sld) (新規作成: `(srfi 115)` ライブラリ定義、Traceability ヘッダー)
- [x] [ulisp/lib/scheme/regex.sld](../../ulisp/lib/scheme/regex.sld) (新規作成: `(scheme regex)` ライブラリ定義、Traceability ヘッダー)
- [x] [ulisp/tests/test_srfi_115.scm](../../ulisp/tests/test_srfi_115.scm) (新規作成: 公式準拠テストスイート)
- [x] [ulisp/Makefile](../../ulisp/Makefile) (`test_srfi_115` ターゲット追加、`lint_sexpr`、`test:` への登録)
- [x] [ulisp/docs/ref_r7rs_compliance.md](../../ulisp/docs/ref_r7rs_compliance.md) (SRFI 115 準拠ステータスを `◎` に更新)
- [x] [docs/issues/README.md](README.md) (Issue 台帳更新: ステータス管理)

---

## 4. 仕様定義とアーキテクチャ設計 / Specification & Architecture Design

### 4.1 エクスポート識別子一覧 (全 22 識別子)
`rx` (マクロ) および以下の手続き群：
1. **コンストラクタ & 述語**:
   - `regexp`: SRE をコンパイルして `regexp` オブジェクトを生成
   - `rx`: `(rx sre ...)` 構文（マクロ）
   - `regexp?`: オブジェクトが `regexp` か判定
   - `valid-sre?`: 与えられた S 式が妥当な SRE 構文かを検査
2. **マッチング実行**:
   - `regexp-matches`: 文字列全体に一致するか照合し、一致した場合は `regexp-match` オブジェクト、不一致は `#f`
   - `regexp-matches?`: 文字列全体の一致真偽値 (`#t` / `#f`)
   - `regexp-search`: 文字列内の任意の位置で最初に一致する箇所を探索
3. **マッチオブジェクト操作**:
   - `regexp-match?`: マッチオブジェクト判定述語
   - `regexp-match-count`: キャプチャされたサブマッチの総数
   - `regexp-match-submatch`: 指定インデックス（0 = 全体一致、1..n = グループ）または名前付きシンボルの部分文字列
   - `regexp-match-submatch-start`: サブマッチの開始文字インデックス
   - `regexp-match-submatch-end`: サブマッチの終了文字インデックス
4. **高水準テキスト操作**:
   - `regexp-fold`: マッチ箇所を走査しながら畳み込みを行う
   - `regexp-extract`: マッチした部分文字列のリストを抽出
   - `regexp-split`: マッチ箇所をデリミタとして文字列を分割
   - `regexp-partition`: マッチ部分と非マッチ部分を交互に含むリストを返却
   - `regexp-replace`: 最初のマッチ箇所を指定の置換パターン（文字列または手続き）で置換
   - `regexp-replace-all`: すべてのマッチ箇所を置換

### 4.2 SRE 構文サポート範囲
- **基本リテラル**:
  - `char` (例: `#\a`): 単一文字一致
  - `string` (例: `"hello"`): 文字列一致
  - `any`: 任意の 1 文字
  - `nonl`: 改行 (`#\newline`) 以外の任意の 1 文字
- **論理演算 & 連鎖**:
  - `(: sre ...)` / `(seq sre ...)`: 連鎖 (シーケンス)
  - `(or sre ...)`: 選択 (オルタネーション)
- **繰り返し (Greedy & Non-Greedy)**:
  - `(* sre ...)` / `(+ sre ...)` / `(? sre ...)`: 0回以上 / 1回以上 / 0〜1回
  - `(= n sre ...)`: ちょうど n 回
  - `(>= n sre ...)`: n 回以上
  - `(** from to sre ...)`: from 回以上 to 回以下
  - `(*? sre ...)`, `(+? sre ...)`, `(?? sre ...)`, `(**? from to sre ...)`: 非貪欲一致
- **キャプチャ**:
  - `(submatch sre ...)`: 番号付きサブマッチ (1-indexed)
  - `(submatch-named <name> sre ...)`: 名前付きサブマッチ (`<name>` はシンボル)
- **境界アサーション**:
  - `bos`, `(bos)`: 文字列の先頭 (Beginning of String)
  - `eos`, `(eos)`: 文字列の末尾 (End of String)
  - `bol`, `(bol)`: 行の先頭 (Beginning of Line)
  - `eol`, `(eol)`: 行の末尾 (End of Line)
  - `bow`, `(bow)`: 単語の先頭 (Beginning of Word)
  - `eow`, `(eow)`: 単語の末尾 (End of Word)
  - `nwb`, `(nwb)`: 非単語境界 (Non-Word Boundary)
  - `word`, `(word sre ...)`: 単語境界で挟まれた SRE
- **文字セット & 文字クラス**:
  - `(/ range ...)`: 文字範囲 (例: `(/ "a" "z")`, `(/ #\0 #\9)`)
  - `(~ cset ...)`: 文字セット補集合 (否定)
  - `(& cset ...)`: 文字セット積集合
  - `(- cset ...)`: 文字セット差集合
  - `(w/nocase sre ...)` / `(w/case sre ...)`: 大文字小文字同一視 / 区別
  - 標準クラス名: `alpha`, `alphabetic`, `numeric`, `whitespace`, `upper`, `lower`, `ascii`, `punct`, `cntrl`, `xdigit`, `blank`, `graph`, `print`

### 4.3 エンジン構造
- `define-record-type <regexp>`:
  - `pattern`: 元の SRE パターン
  - `num-submatches`: キャプチャグループの総数
  - `named-submatches`: 名前とインデックスの alist
  - `matcher`: コンパイル済みマッチャー手続き `(lambda (str start end whole-match? k-success k-fail) ...)`
- バックトラッキング型継続渡しマッチャー、または有限状態機械（NFA/DFA）によるバックトラック探索。
- マッチ成功時に `make-regexp-match` で結果コンテナ（部分文字列インデックス組 `(cons start end)` のベクタ）をインスタンス化。

---

## 5. 実装方針 / Implementation Plan
Target Branch: `feat/860-implement-srfi-115-scheme-regular-expressions-sre`

1. **データ構造定義 (`ulisp/lib/regex.scm`)**:
   - `define-record-type :regexp ...`
   - `define-record-type :regexp-match ...`
2. **文字セット判定・正規化エンジンの構築**:
   - 文字クラス述語テーブル (`char-alphabetic?`, `char-numeric?`, `char-whitespace?` 等)
   - 文字範囲 `(/ ...)`、否定 `(~ ...)`, 積 `(& ...)`, 差 `(- ...)` のセット述語合成器
3. **SRE コンパイラの実装**:
   - SRE S 式を走査し、サブマッチ番号付け・名前マップ構築
   - 各 SRE 構文要素をマッチャーコンビネータへ再帰的にコンパイル
4. **マッチャー実行基盤**:
   - 探索ループ: `regexp-matches`（全体一致）、`regexp-search`（各開始位置での部分探索）
   - キャプチャ開始・終了インデックスの記録と復元
5. **高水準ユーティリティ手続きの実装**:
   - `regexp-fold`, `regexp-extract`, `regexp-split`, `regexp-partition`, `regexp-replace`, `regexp-replace-all`
6. **モジュール定義**:
   - `ulisp/lib/srfi/115.sld`: `(srfi 115)`
   - `ulisp/lib/scheme/regex.sld`: `(scheme regex)`
   - Traceability ヘッダー (`;; §...`) の付与
7. **包括的テストスイートの作成 (`ulisp/tests/test_srfi_115.scm`)**:
   - Group 1: 基本リテラルと連鎖 (`char`, `string`, `any`, `nonl`, `(: ...)`, `(or ...)`)
   - Group 2: 繰り返し (`*`, `+`, `?`, `=`, `>=`, `**`, 非貪欲 `*?`, `+?`)
   - Group 3: キャプチャと名前付きグループ (`submatch`, `submatch-named`)
   - Group 4: 境界アサーション (`bos`, `eos`, `bol`, `eol`, `bow`, `eow`, `word`)
   - Group 5: 文字クラスと範囲 (`alpha`, `numeric`, `whitespace`, `(/ ...)`, `(~ ...)`, `w/nocase`)
   - Group 6: 高水準操作 (`regexp-fold`, `regexp-extract`, `regexp-split`, `regexp-replace`, `regexp-replace-all`)
8. **総合検証と品質ゲート**:
   - `make -C ulisp test_srfi_115` 100% PASS
   - `python3 scripts/verify_r7rs_traceability.py` 100% PASS
   - `make -C ulisp lint_sexpr` 100% PASS
   - `make -C ulisp bootstrap` による自己ホスト 5 モジュール並列固定点収束
   - `make -C ulisp test` の全テストスイート完走
   - `make py_compile && make check_format && make static_analysis` 100% PASS

---

## 6. 完了条件 / Success Criteria (DoD)
- [x] `(scheme regex)` および `(srfi 115)` から全 22 識別子が正常にエクスポートされていること。
- [x] `regexp`, `rx`, `valid-sre?` により妥当な SRE がコンパイル可能であること。
- [x] `regexp-matches` および `regexp-matches?` が文字列全体の一致を厳密に判定できること。
- [x] `regexp-search` が部分文字列の一致と位置（start/end）を正しく検出できること。
- [x] 番号付きおよび名前付き `submatch` の抽出・開始／終了インデックス取得が正確に動作すること。
- [x] 境界アサーション（`bos`, `eos`, `bol`, `eol`, `bow`, `eow`, `word`）が仕様通り判定されること。
- [x] 文字クラス・文字範囲・補集合・大文字小文字同一視 (`w/nocase`) が正しく機能すること。
- [x] `regexp-replace` および `regexp-replace-all` による文字列置換が正確に行われること。
- [x] `regexp-split`, `regexp-extract`, `regexp-partition`, `regexp-fold` が仕様通り動作すること。
- [x] 新規単体テスト `test_srfi_115.scm` の全グループが 100% PASS すること。
- [x] `python3 scripts/verify_r7rs_traceability.py` の監査が 100% PASS すること。
- [x] `make -C ulisp bootstrap` による自己ホスト 5 モジュール並列ビルドが固定点収束（Stage 2 == Stage 3 ビット完全一致）すること。
- [x] `make -C ulisp test` の全テストスイートがエラーなく完走すること。
- [x] トリプル品質ゲート（`make py_compile && make check_format && make static_analysis`）が 100% PASS すること。
- [x] 相対パス規則が厳格に遵守され、絶対パスの混入が 0 件であること。
