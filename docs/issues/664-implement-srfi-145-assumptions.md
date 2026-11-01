---
ID: 664
種別: Feature
優先度: Medium
ステータス: Open (New)
---

# [FEAT/ENH] R7RS-large / SRFI 145 Assumptions 表明構文 (assume / assert) の実装 (ID: 664)

## 1. 概要 / Summary
SRFI 145 (Assumptions) に準拠し、プログラム内の不変条件・前提条件を明示的に表明・検査する構文 `assume`（および互換構文 `assert`）を実装する。
ULisp では現在 `guard` / `raise` / `error` の直接呼び出しによる代用（△）にとどまっているが、本構文をマクロ脱糖器に組み込み、条件不成立時に仕様節番号・式・引数情報を付与した標準エラーオブジェクトを生成・送出可能にする。

---

## 2. トレーサビリティ / Traceability
- 関連仕様:
  - SRFI 145: Assumptions (`assume`, `assert`)
  - [ref_r7rs_compliance.md](../../ulisp/docs/ref_r7rs_compliance.md) §2.3 その他主要 SRFI
  - [DSN-33 (ULisp 包括設計仕様書)](../../docs/designs/DSN-33-ulisp_underlying_x86_native_aot_compiler_architecture_specification.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [ulisp/frontend/030_desugar.scm](../ulisp/frontend/030_desugar.scm) (`assume` 構文の脱糖)
- [ ] [ulisp/lib/srfi/145.sld](../ulisp/lib/srfi/145.sld) (新規 SRFI 145 ライブラリ定義)
- [ ] [ulisp/tests/test_srfi_145_assume.scm](../ulisp/tests/test_srfi_145_assume.scm) (新規単体テスト)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/664-implement-srfi-145-assumptions`

1. `(assume <expression> [message [obj ...]])` 構文の定義：
   - `<expression>` が真の場合はその値を返却。
   - 偽の場合は `(error message expression obj ...)` を呼び出して例外を送出。
2. Pass 030 において最適化モード（`-O2` 以上等）で前提条件をコンパイラ型推論（S-RTyper）へのヒントとして活用可能な構造とする。
3. `(srfi 145)` ライブラリを定義し、エクスポート。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] `assume` の条件が真の場合に式の値が正常に返却される
- [ ] 条件が偽の場合に適切なエラーオブジェクトとともに実行時例外が発生する
- [ ] `(srfi 145)` ライブラリとして利用可能
- [ ] `make test` を通過する

