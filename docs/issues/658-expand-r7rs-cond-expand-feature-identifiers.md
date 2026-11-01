---
ID: 658
種別: Feature
優先度: High
ステータス: Open (New)
---

# [FEAT/ENH] R7RS §4.2.1 cond-expand 機能識別子および library 判定構文の拡充 (ID: 658)

## 1. 概要 / Summary
R7RS-small §4.2.1 (Condition-expanding construct: `cond-expand`) に準拠し、コンパイル時条件分岐構文 `cond-expand` の機能識別子（Feature Identifiers）およびライブラリ存在判定構文 `(library <name>)` を拡充する。
現在の ULisp ではプラットフォーム基本識別のみの部分サポート（△）にとどまっているため、標準規定の feature 識別子（`r7rs`, `exact-closed`, `little-endian` 等）および論理結合（`and`, `or`, `not`）の完全評価をサポートする。

---

## 2. トレーサビリティ / Traceability
- 関連仕様:
  - R7RS-small §4.2.1: Derived expression types (`cond-expand`)
  - R7RS-small §5.5.1: Features
  - [ref_r7rs_compliance.md](../../ulisp/docs/ref_r7rs_compliance.md) §1.1 式とコア構文
  - [DSN-33 (ULisp 包括設計仕様書)](../../docs/designs/DSN-33-ulisp_underlying_x86_native_aot_compiler_architecture_specification.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [ulisp/frontend/010_library.scm](../ulisp/frontend/010_library.scm) (モジュール読み込み時 cond-expand 処理)
- [ ] [ulisp/frontend/030_desugar.scm](../ulisp/frontend/030_desugar.scm) (一般式コンテキストにおける cond-expand 脱糖)
- [ ] [ulisp/tests/test_r7rs_cond_expand.scm](../ulisp/tests/test_r7rs_cond_expand.scm) (新規単体テスト)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/658-expand-r7rs-cond-expand-feature-identifiers`

1. ULisp がサポートする標準 feature 識別子リスト（`r7rs`, `exact-closed`, `little-endian`, `x86-64`, `linux`, `posix`, `ulisp` 等）を定義。
2. `(library <name>)` 構文のサポート: 指定ライブラリが利用可能・定義済みかをライブラリレジストリから判定。
3. 条件節内の `(and ...)`, `(or ...)`, `(not ...)` 複合条件式の再帰評価。
4. 該当する節の式を展開し、いずれにも一致せず `else` 節がない場合は `syntax-error` を報告。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] `r7rs`, `exact-closed`, `posix` 等の標準識別子が正しく `#t` / `#f` に評価される
- [ ] `(library (scheme base))` などのライブラリ存在条件式が正常に評価される
- [ ] `and`, `or`, `not`, `else` を含む複合条件が正しく分岐展開される
- [ ] `make test` を通過する

