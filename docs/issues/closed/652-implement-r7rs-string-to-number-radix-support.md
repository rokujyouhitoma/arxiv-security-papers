---
ID: 652
種別: Feature
優先度: High
ステータス: Closed (Completed)
---

# [FEAT/ENH] R7RS §6.2.6 string->number の可変基数 (2/8/10/16進数) 対応と数値リテラルパースの拡充 (ID: 652)

## 1. 概要 / Summary
R7RS-small §6.2.6 (Numerical operations) で規定されている `(string->number string)` および `(string->number string radix)` を完全サポートする。
現状の ULisp では S 式リーダー内部で 10 進数のみを解析しているが、第 2 引数による基数指定（`radix`: 2, 8, 10, 16）および基数プレフィックス（`#b`, `#o`, `#d`, `#x`）、明示的な正負号（`+`, `-`）、正確性プレフィックス（`#e`）を解釈できるように拡張する。
また、S 式リーダー（`port-read`）ともパースエンジンを統合し、Scheme プログラム中の `#b1011` や `#xff` などの基数リテラルをネイティブにサポートする。

---

## 2. 背景と技術的課題 / Background & Technical Challenges
1. **可変基数アルゴリズム (Radix 2, 8, 10, 16)**:
   - 各基数に応じた有効数字（2: `0-1`, 8: `0-7`, 10: `0-9`, 16: `0-9, a-f, A-F`）の厳格な検証。
   - 左から右へ累積するホーナー法（Horner's method）による高速基数変換。
2. **プレフィックスと引数基数の直交性・整合性判定**:
   - R7RS 仕様では、文字列内に基数プレフィックス（`#b`, `#o`, `#d`, `#x`）が存在し、かつ第 2 引数 `radix` が指定された場合、両者が完全に一致していればパースを継続し、矛盾している場合は `#f` を返却しなければならない。
   - 符号（`+`, `-`）とプレフィックスの順序（例: `#x-ff` と `-#xff`）の双方を柔軟かつ厳格に受理。
3. **62-bit Fixnum 整数オーバーフロー防御 (CWE-190)**:
   - ULisp の Tagged Pointer 表現では Fixnum は 62-bit 符号付き整数（範囲: `[-2^61, 2^61 - 1]` = `[-2305843009213693952, 2305843009213693951]`）。
   - パース中の乗算・加算処理においてオーバーフロー境界を事前に検出し、Fixnum の表現可能範囲を超過した場合は安全に `#f` を返却。
4. **S式リーダー（`reader.scm`）との連携とコンパイラ後方互換性**:
   - `ulisp/lib/reader.scm` の `#` ディスパッチにおいて基数プレフィックスを認識させ、リーダーでも 2/8/10/16 進数リテラルを直接読み込み可能にする。
   - 3-Stage Bootstrap（Stage 1/2/3）および Pass 010（ライブラリインクルード）において既存の数値パース動作に一切の退行（regressions）が生じないことを保証。

---

## 3. セキュリティ要件と脅威分析 / Security Considerations
- **CWE-190: 整数オーバーフロー (Integer Overflow or Wraparound)**:
  - 悪意ある入力（例: `"99999999999999999999999999999999"` や `"#x7ffffffffffffffff"`）に対して、加算・乗算時のビット溢れやラップアラウンドを防止し、境界判定で即座に `#f` を返す。
- **CWE-125 / CWE-787: 境界外メモリアクセス防止**:
  - 空文字列 `""`、記号のみ `"+"` / `"-"`、プレフィックスのみ `"#x"` / `"#b"`、途中に不正文字を含む文字列に対し、文字列インデックス範囲チェックを徹底。
- **DoS / ReDoS 耐性**:
  - 正規表現エンジンに依存せず、文字配列走査による線形時間 $O(N)$ のステートマシンでパースを行い、過度なバックトラックやスタック枯渇を完全排除。

---

## 4. トレーサビリティ / Traceability
- **R7RS-small 仕様**:
  - Section 6.2.6 (Numerical operations: `string->number`)
  - Section 7.1.1 (Lexical structure: `<number>`, `<radix 2>`, `<radix 8>`, `<radix 10>`, `<radix 16>`)
- **仕様リファレンス**: [ref_r7rs_compliance.md](../../ulisp/docs/ref_r7rs_compliance.md) §1.3 (6.2.6)
- **関連モジュール**:
  - [ulisp/lib/reader.scm](../../ulisp/lib/reader.scm)
  - [ulisp/lib/math.scm](../../ulisp/lib/math.scm)
  - [ulisp/lib/scheme/base.sld](../../ulisp/lib/scheme/base.sld)
  - [ulisp/lib/scheme/r5rs.sld](../../ulisp/lib/scheme/r5rs.sld)

---

## 5. 影響範囲と関連ファイル / Scope and Affected Files
- [ulisp/lib/reader.scm](../../ulisp/lib/reader.scm):
  - `string->number-radix` コアパース手続きの実装。
  - `string->number` 多相マクロ（1引数/2引数ディスパッチ）の定義。
  - `port-read` における `#b`, `#o`, `#d`, `#x` 数値リテラルディスパッチの追加。
- [ulisp/lib/scheme/base.sld](../../ulisp/lib/scheme/base.sld):
  - `(scheme base)` の export リストに `string->number` を明示的追加。
- [ulisp/docs/ref_r7rs_compliance.md](../../ulisp/docs/ref_r7rs_compliance.md):
  - §6.2.6 `string->number` のステータスを `△` から `◎` に更新。
- [ulisp/tests/test_string_to_number.scm](../../ulisp/tests/test_string_to_number.scm):
  - 新規テストスイートの作成（全基数、プレフィックス、符号、オーバーフロー、不正文字、S式リーダー連携）。
- [ulisp/Makefile](../../ulisp/Makefile):
  - `test_string_to_number` ターゲットの追加および `test:` 統合。

---

## 6. 実装方針 / Implementation Plan
Target Branch: `feat/652-implement-r7rs-string-to-number-radix-support`

1. **基数変換・文字判定ヘルパーの実装 (`lib/reader.scm`)**:
   - `(ulisp-digit-value ch radix)`: 文字 `ch` が指定基数 `radix` (2, 8, 10, 16) において有効な数字であれば整数値（0〜15）を返却、無効なら `#f`。
     - `0-9`: 0〜9
     - `a-f` / `A-F`: 10〜15 (radix 16 のみ)
2. **コアパースエンジン `(string->number-radix str default-radix)`**:
   - 文字列 `str` の検証（`string?` かつ `length > 0`）。
   - 状態機械によるプレフィックス抽出:
     - `pos` ポインタを進めながら、`#b`/`#B`, `#o`/`#O`, `#d`/`#D`, `#x`/`#X`, `#e`/`#E`, `#i`/`#I` を認識。
     - 符号（`+`, `-`）を抽出（プレフィックスの前または後）。
   - 基数決定とバリデーション:
     - プレフィックス基数と `default-radix` の矛盾チェック（矛盾時は `#f`）。
     - 基数が 2, 8, 10, 16 以外なら `#f`。
   - 数字列のパースとオーバーフロー防御:
     - 残りの文字を走査し、`ulisp-digit-value` で数値化。数字が 1 文字も無ければ `#f`。
     - 62-bit Fixnum 範囲チェック: `(* acc radix)` がオーバーフローしないか事前境界チェック。
     - 最終結果に符号を適用して返却。
3. **`string->number` マクロ & 手続き定義**:
   ```scheme
   (define (string->number-1 s) (string->number-radix s 10))
   (define (string->number-2 s r) (string->number-radix s r))
   (define-syntax string->number
     (syntax-rules ()
       ((string->number s) (string->number-radix s 10))
       ((string->number s r) (string->number-radix s r))))
   ```
4. **S 式リーダーへの数値プレフィックス統合 (`reader.scm`)**:
   - `port-read` の `#` ディスパッチに `#\b`, `#\B`, `#\o`, `#\O`, `#\d`, `#\D`, `#\x`, `#\X` を追加。
   - デリミタまでの文字を蓄積し、`string->number-radix` で解析。有効な数値であれば Fixnum を返し、不正であればエラーまたはシンボルとして処理。
5. **テストスイート `tests/test_string_to_number.scm` の作成**:
   - Group 1: 基本 10 進数（正数、負数、明示的 `+`）
   - Group 2: 第 2 引数基数指定（基数 2, 8, 10, 16）
   - Group 3: 基数プレフィックス（`#b`, `#o`, `#d`, `#x`、大文字・小文字、符号との組み合わせ）
   - Group 4: プレフィックスと引数基数の整合性・不整合性（不整合時は `#f`）
   - Group 5: エラーケース・境界値（空文字列、不正文字、オーバーフロー境界）
   - Group 6: S 式リーダー（`read`）での基数リテラル読み取り検証
6. **Makefile, Bootstrap & Triple Quality Gates**:
   - `test_string_to_number` を Makefile に登録。
   - `./bootstrap.sh`（3-Stage Bootstrap）実行による固定点収束検証。
   - Triple Quality Gate（`make check_format`, `make static_analysis`, `make test`）の通過。

---

## 7. 完了条件 / Success Criteria (DoD)
- [x] `(string->number "1010" 2)` => `10`、`(string->number "77" 8)` => `63`、`(string->number "ff" 16)` => `255` が正しく評価されること。
- [x] プレフィックス形式 `(string->number "#b1010")`、`(#x-1f)`、`(-#xff)` 等が正しく評価されること。
- [x] プレフィックス基数と第 2 引数基数が矛盾する場合（例: `(string->number "#xff" 10)`）に安全に `#f` が返ること。
- [x] 不正文字（例: `"12a" 10`）や記号のみ、空文字に対して例外を投げず安全に `#f` が返ること。
- [x] 62-bit Fixnum 上限・下限のオーバーフロー入力に対して安全に `#f` が返ること。
- [x] S 式リーダー（`read`）が `#b`, `#o`, `#d`, `#x` リテラルを正しくパースできること。
- [x] `tests/test_string_to_number.scm` の全テストが 100% PASS すること。
- [x] 3-Stage Bootstrap（`bootstrap.sh`）で固定点収束し、`make test` に退行がないこと。
- [x] `ref_r7rs_compliance.md` の §6.2.6 `string->number` が `◎` に更新されていること。
- [x] すべてのファイルリンクが相対パスで記述されていること。
