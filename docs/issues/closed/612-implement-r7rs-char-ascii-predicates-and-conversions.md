---
ID: 612
種別: Feature
優先度: Medium
ステータス: Closed (Done)
---

# [FEAT/ENH] R7RS (scheme char) ASCII 文字・文字列述語群および大小文字変換手続きの実装 (ID: 612)

## 1. 概要 / Summary
R7RS-small §6.6, §6.7 および `(scheme char)` で規定されている文字・文字列の大文字小文字無視（Case-insensitive）比較述語、文字種判定述語、および大小文字変換手続き（計19手続き）を実装する。
初期フェーズとして標準 ASCII / 基本ラテン文字セット（0〜127）を完全対象とし、将来の Unicode 展開への拡張性を担保しつつ、ULisp コンパイラおよび標準ライブラリにおけるテキスト処理・字句解析基盤を大幅に強化する。

主な対象手続き（全19種）:
1. **文字種判定述語 (Character Predicates)**:
   - `char-alphabetic?`: ASCII 英字 (`a-z`, `A-Z`) 判定
   - `char-numeric?`: ASCII 10進数字 (`0-9`) 判定
   - `char-whitespace?`: 空白・制御改行文字 (`#\space`, `#\tab`, `#\newline`, `#\return`, `#\page`, ASCII 9-13, 32) 判定
   - `char-upper-case?`: ASCII 大文字 (`A-Z`) 判定
   - `char-lower-case?`: ASCII 小文字 (`a-z`) 判定
   - `digit-value`: 10進数字文字 (`0-9`) の整数値 (`0-9`) 返却（非数字文字は `#f`）
2. **文字大小変換およびケースフォールディング (Character Conversions)**:
   - `char-upcase`: 小文字を大文字へ変換（その他は恒等）
   - `char-downcase`: 大文字を小文字へ変換（その他は恒等）
   - `char-foldcase`: ASCII 単純ケースフォールディング（ASCII では `char-downcase` と同等）
3. **大文字小文字同一視文字比較 (Case-insensitive Character Comparisons)**:
   - `char-ci=?`, `char-ci<?`, `char-ci>?`, `char-ci<=?`, `char-ci>=?`: 2引数および Pass 030 連鎖比較脱糖による可変長比較
4. **文字列大小変換 (String Conversions)**:
   - `string-upcase`: `string-map` を用いた全文字大文字変換
   - `string-downcase`: `string-map` を用いた全文字小文字変換
   - `string-foldcase`: `string-map` を用いた全文字ケースフォールディング
5. **大文字小文字同一視文字列比較 (Case-insensitive String Comparisons)**:
   - `string-ci=?`, `string-ci<?`, `string-ci>?`, `string-ci<=?`, `string-ci>=?`: 辞書式順序比較および Pass 030 連鎖比較脱糖

---

## 2. トレーサビリティ / Traceability
- **R7RS-small 規格仕様**:
  - §6.6: Characters (`char-ci*`, `char-alphabetic?`, `char-numeric?`, `char-whitespace?`, `char-upper-case?`, `char-lower-case?`, `digit-value`, `char-upcase`, `char-downcase`, `char-foldcase`)
  - §6.7: Strings (`string-ci*`, `string-upcase`, `string-downcase`, `string-foldcase`)
  - §5.6 / §7.1.3: `(scheme char)` ライブラリ仕様
- **ULisp 内部設計ドキュメント**:
  - [R7RS 仕様準拠状況リファレンス](../../ulisp/docs/ref_r7rs_compliance.md) §1.3 (6.6, 6.7), §1.4 (`(scheme char)`)
  - [ULisp 成果物・ライブラリ設計](../../ulisp/docs/spec_library_modules.md)

---

## 3. 脅威モデル分析とセキュリティ要件 (Threat Model & Security Mitigations)
1. **境界値・不正入力耐性**:
   - `char->integer` / `integer->char` 変換時における範囲外入力の抑止。ASCII 範囲外（0未満または128以上）の文字が渡された場合でも、未定義動作やメモリ破損を起こさず安全に `#f` または文字そのものを返却する安全設計（Defensive Fallthrough）。
2. **バッファオーバーフロー・メモリ安全性**:
   - `string-upcase` / `string-downcase` 等における新規文字列生成時、入力文字列の `string-length` を厳格に参照して `make-string` を行い、正確な境界内コピーを行うことでバッファオーバーランを排除。
3. **辞書式順序比較の決定性・一貫性**:
   - `string-ci*` 比較において、最短長プレフィックスが完全一致した後の長さ比較（`len1 < len2`, `len1 > len2`, `len1 = len2`）の三値ロジックを厳密に実装し、全順序関係（Strict Weak Ordering）を保証。
4. **GC 協調と一時オブジェクト保護**:
   - 文字列マッピング処理において世代別コピー GC との整合性を保ち、ヒープポインタ破損を防ぐ。

---

## 4. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [ulisp/lib/char.scm](../../ulisp/lib/char.scm): 新設。文字判定・変換手続き群および `char-ci*` 比較述語群の実装
- [x] [ulisp/lib/string.scm](../../ulisp/lib/string.scm): 文字列の大小文字変換および `string-ci*` 辞書式比較手続きの実装
- [x] [ulisp/lib/scheme/char.sld](../../ulisp/lib/scheme/char.sld): `(scheme char)` ライブラリ定義のインクルードパス・エクスポート確認
- [x] [ulisp/compiler/scope.scm](../../ulisp/compiler/scope.scm): `*scope-standard-builtins*` に新設 19 手続きを登録
- [x] [ulisp/frontend/030_desugar.scm](../../ulisp/frontend/030_desugar.scm): `char-ci*` および `string-ci*` の 3 引数以上連鎖比較（`desugar-chain-cmp`）の脱糖サポート追加
- [x] [ulisp/Makefile](../../ulisp/Makefile): `ULISP_STD_LIBS` に `lib/char.scm` を追加、テストターゲット `test_char` を新設し `test:` に統合
- [x] [ulisp/tests/test_char.scm](../../ulisp/tests/test_char.scm): 新設。全19手続きの単体テスト、エッジケース、複数引数比較テスト
- [x] [ulisp/tests/test_stdlib_r7rs.scm](../../ulisp/tests/test_stdlib_r7rs.scm): `(scheme char)` 統合動作検証を追加
- [x] [ulisp/docs/ref_r7rs_compliance.md](../../ulisp/docs/ref_r7rs_compliance.md): `(scheme char)` の準拠ステータスを更新 (20% → 100%)

---

## 5. 実装方針 / Implementation Plan
Target Branch: `feat/612-implement-r7rs-char-ascii-predicates-and-conversions`

### ステップ 1: `ulisp/lib/char.scm` の新設
1. `char->integer` / `integer->char` を活用し、ASCII コードポイント（65-90, 97-122, 48-57, 9-13, 32）による判定関数群を実装:
   - `(define (char-alphabetic? c) ...)`
   - `(define (char-numeric? c) ...)`
   - `(define (char-whitespace? c) ...)`
   - `(define (char-upper-case? c) ...)`
   - `(define (char-lower-case? c) ...)`
   - `(define (digit-value c) ...)`
   - `(define (char-upcase c) ...)`
   - `(define (char-downcase c) ...)`
   - `(define (char-foldcase c) ...)`
2. `char-foldcase` による正規化ヘルパー `%char-ci-compare` を作成し、2引数文字比較を定義:
   - `char-ci=?`, `char-ci<?`, `char-ci>?`, `char-ci<=?`, `char-ci>=?`

### ステップ 2: `ulisp/lib/string.scm` の機能拡張
1. `string-map` を活用して文字列大小文字変換を実装:
   - `(define (string-upcase s) (string-map char-upcase s))`
   - `(define (string-downcase s) (string-map char-downcase s))`
   - `(define (string-foldcase s) (string-map char-foldcase s))`
2. 文字単位で `%char-ci-compare` を行う辞書式比較ヘルパー `%string-ci-compare` を実装:
   - 最短長まで走査し、差分があればそれを返却。一致した場合は長さ差（`- len1 len2`）を比較。
   - `string-ci=?`, `string-ci<?`, `string-ci>?`, `string-ci<=?`, `string-ci>=?` を定義。

### ステップ 3: コンパイラ連携（Scope & Desugar）
1. `ulisp/compiler/scope.scm` の `*scope-standard-builtins*` に新設 19 手続きを登録。
2. `ulisp/frontend/030_desugar.scm` に `char-ci*` および `string-ci*` の連鎖比較パターンを追加。

### ステップ 4: ビルド・モジュール定義・テスト整備
1. `ulisp/Makefile` の `ULISP_STD_LIBS` に `lib/char.scm` を追加。
2. `test_char` ターゲットを追加し、`ulisp/tests/test_char.scm` を実行するテストフローを確立。
3. `make -C ulisp test` の全テストパスを確認。

### ステップ 5: ドキュメント更新と品質ゲート検証
1. `ulisp/docs/ref_r7rs_compliance.md` の §1.3 (6.6, 6.7) および §1.4 の `(scheme char)` を「◎ 100%」に更新。
2. `verify-quality-gates` をパスすることを確認。

---

## 6. 完了条件 / Success Criteria (DoD)
- [x] `(char-ci=? #\a #\A)` が `#t` を返すこと。
- [x] `(char-ci<? #\A #\b)` が `#t` を返すこと。
- [x] `(char-alphabetic? #\Z)` が `#t`、`(char-alphabetic? #\9)` が `#f` を返すこと。
- [x] `(char-numeric? #\5)` が `#t`、`(char-numeric? #\a)` が `#f` を返すこと。
- [x] `(char-whitespace? #\space)`, `(char-whitespace? #\tab)`, `(char-whitespace? #\newline)` が `#t` を返すこと。
- [x] `(char-upper-case? #\A)` が `#t`、`(char-lower-case? #\a)` が `#t` を返すこと。
- [x] `(digit-value #\7)` が `7` を返し、`(digit-value #\a)` が `#f` を返すこと。
- [x] `(char-upcase #\a)` が `#\A`、`(char-downcase #\A)` が `#\a`、`(char-foldcase #\A)` が `#\a` を返すこと。
- [x] `(string-ci<? "abc" "ABD")` が `#t`、`(string-ci=? "Scheme" "sChEmE")` が `#t` を返すこと。
- [x] `(string-upcase "Hello, World!")` が `"HELLO, WORLD!"` を返すこと。
- [x] `(string-downcase "Hello, World!")` が `"hello, world!"` を返すこと。
- [x] `(string-foldcase "Hello, World!")` が `"hello, world!"` を返すこと。
- [x] 3引数以上の連鎖比較 `(char-ci<? #\a #\B #\c)` および `(string-ci<? "a" "B" "c")` が `#t` を返すこと。
- [x] `(scheme char)` ライブラリ経由で全19手続きが利用可能であること。
- [x] `make -C ulisp test` が全件成功（0 failures）で完了すること。
