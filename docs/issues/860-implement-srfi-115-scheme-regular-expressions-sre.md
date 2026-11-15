---
ID: 860
種別: Feature
優先度: Medium
ステータス: Open (New)
---

# [FEAT/ENH] SRFI 115 S 式正規表現エンジン (SRE) および (scheme regex) の実装 (ID: 860)

## 1. 概要 / Summary
R7RS-large Tangerine Edition においてテキスト処理の標準として定められている SRFI 115 (Scheme Regular Expressions) は、S 式で記述される正規表現 (SRE) のパーサ、コンパイラ、およびマッチングエンジンを規定する。
文字列ベースの正規表現と異なり、エスケープ地獄がなく合成可能性・型安全性が極めて高い。
現状の ULisp では「× (未サポート)」となっている。
本 Issue では、NFA/DFA およびバックトラックマッチングアルゴリズムによる純粋 Scheme 製 SRE エンジンを実装し、`(scheme regex)` および `(srfi 115)` として提供する。

---

## 2. トレーサビリティ / Traceability
- 関連仕様:
  - R7RS-large Tangerine Edition: `(scheme regex)`
  - SRFI 115: Scheme Regular Expressions
  - [ref_r7rs_compliance.md](../../ulisp/docs/ref_r7rs_compliance.md) §2.2
  - [DSN-33 (ULisp 包括設計仕様書)](../designs/DSN-33-ulisp_underlying_x86_native_aot_compiler_architecture_specification.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [ulisp/lib/regex.scm](../../ulisp/lib/regex.scm) (新規作成)
- [ ] [ulisp/lib/scheme/regex.sld](../../ulisp/lib/scheme/regex.sld) (新規作成)
- [ ] [ulisp/lib/srfi/115.sld](../../ulisp/lib/srfi/115.sld) (新規作成)
- [ ] [ulisp/tests/test_srfi_115.scm](../../ulisp/tests/test_srfi_115.scm) (新規作成)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/860-implement-srfi-115-scheme-regular-expressions-sre`

1. **SRE 構文パーサ**:
   - リテラル文字列、文字セット、連鎖 `(: ...)`, 選択 `(or ...)`, 繰り返し `(* ...)`, `(+ ...)`, `(? ...)`, キャプチャ `(submatch ...)`, 名名前付きキャプチャ、アサーション `(bos)`, `(eos)`, `(bow)`, `(eow)`.
2. **マッチング実行系**:
   - `regexp`, `rx`, `regexp?`, `regexp-matches`, `regexp-matches?`, `regexp-search`, `regexp-fold`, `regexp-extract`, `regexp-replace`, `regexp-replace-all`.
   - マッチオブジェクトのアクセサ: `regexp-match-submatch`, `regexp-match-submatch-start`, `regexp-match-submatch-end`.
3. **テスト検証**:
   - SRFI 115 公式テストケース群を移植し、各種正規表現パターンの適合性を検証。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] `(scheme regex)` / `(srfi 115)` からすべての SRE API が利用可能であること。
- [ ] 部分マッチ、全一致、置換、キャプチャ抽出が正しく動作すること。
- [ ] `test_srfi_115.scm` が全 PASS すること。
