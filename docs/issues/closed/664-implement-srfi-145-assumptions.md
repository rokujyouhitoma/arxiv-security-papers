---
ID: 664
種別: Feature
優先度: Medium
ステータス: Closed (Completed)
---

# [FEAT/ENH] R7RS-large / SRFI 145 Assumptions 表明構文 (assume / assert) の実装 (ID: 664)

## 1. 概要 / Summary
SRFI 145 (Assumptions) に準拠し、プログラム内の不変条件・前提条件を明示的に表明・検査する構文 `assume`（および互換構文 `assert`）を完全実装する。
ULisp では現在 `guard` / `raise` / `error` の直接呼び出しによる代用（△）にとどまっていたが、本構文をマクロ展開器および構文脱糖器に組み込み、条件不成立時に仕様節番号・式・引数情報を付与した標準エラーオブジェクトを生成・送出し、条件成立時は式の値を透過的に返却可能にする。

---

## 2. トレーサビリティ / Traceability
- 関連仕様:
  - SRFI 145: Assumptions (`assume`, `assert`)
  - [ref_r7rs_compliance.md](../../ulisp/docs/ref_r7rs_compliance.md) §2.3 その他主要 SRFI
  - [DSN-33 (ULisp 包括設計仕様書)](../../docs/designs/DSN-33-ulisp_underlying_x86_native_aot_compiler_architecture_specification.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [ulisp/frontend/020_macro_expander.scm](../ulisp/frontend/020_macro_expander.scm) (`core-form-or-primitive?` への `assume`, `assert` 登録)
- [x] [ulisp/frontend/030_desugar.scm](../ulisp/frontend/030_desugar.scm) (`assume` / `assert` 構文の脱糖)
- [x] [ulisp/lib/srfi/145.sld](../ulisp/lib/srfi/145.sld) (新規 SRFI 145 ライブラリ定義)
- [x] [ulisp/lib/scheme/base.sld](../ulisp/lib/scheme/base.sld) (`assume`, `assert` のエクスポート)
- [x] [ulisp/docs/ref_r7rs_compliance.md](../ulisp/docs/ref_r7rs_compliance.md) (R7RS 準拠状況テーブル更新: △ から ◎)
- [x] [ulisp/tests/test_srfi_145_assume.scm](../ulisp/tests/test_srfi_145_assume.scm) (新規単体テスト)
- [x] [ulisp/Makefile](../ulisp/Makefile) (テストターゲット統合)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/664-implement-srfi-145-assumptions`

1. **構文の仕様**:
   - `(assume <expression> [message [obj ...]])`
   - `(assert <expression> [message [obj ...]])` (SRFI 145 互換)
   - 動作:
     - `<expression>` を評価する。
     - 真（`#f` 以外）の場合: `<expression>` の値を返す（式として評価される）。
     - 偽（`#f`）の場合: `(error message expression obj ...)` を発生させる。
     - `message` が省略された場合のデフォルトは `"invalid assumption [SRFI 145 §2]"`。

2. **Pass 030 (`030_desugar.scm`) での脱糖**:
   - `(desugar-assume expr)`:
     ```scheme
     (let ((tmp (unique-symbol "assume_tmp_")))
       (list 'let (list (list tmp expression))
             (list 'if tmp
                   tmp
                   (cons 'error (cons (or message "invalid assumption [SRFI 145]") (cons (list 'quote expression) objs))))))
     ```
   - 一時変数 `tmp` により `<expression>` は 1 回のみ評価される。

3. **ライブラリの作成**:
   - `ulisp/lib/srfi/145.sld` を作成し、`assume`, `assert` をエクスポート。

4. **単体テストの作成**:
   - 条件が真の場合に評価値が返ること。
   - 条件が偽の場合に例外（エラー）が発生すること。
   - 式の多重評価がないこと（副作用を持つ式で検証）。

---

## 5. 完了条件 / Success Criteria (DoD)
- [x] `assume` / `assert` の条件が真の場合に式の値が正常に返却される
- [x] 式が一度だけ評価される（副作用の多重発生がない）
- [x] 条件が偽の場合に適切なエラーメッセージとともに実行時例外が発生する
- [x] `(srfi 145)` ライブラリとしてインポート可能
- [x] `ref_r7rs_compliance.md` に SRFI 145 の完全準拠（◎）が反映される
- [x] `make test` を通過する
