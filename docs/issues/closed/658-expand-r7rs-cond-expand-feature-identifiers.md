---
ID: 658
種別: Feature
優先度: High
ステータス: Closed (Completed)
---

# [FEAT/ENH] R7RS §4.2.1 cond-expand 機能識別子および library 判定構文の拡充 (ID: 658)

## 1. 概要 / Summary
R7RS-small §4.2.1 (Condition-expanding construct: `cond-expand`) および §5.5.1 (Features) に準拠し、コンパイル時条件分岐構文 `cond-expand` の機能識別子（Feature Identifiers）およびライブラリ存在判定構文 `(library <name>)` を拡充・完全実装する。
現在の ULisp ではプラットフォーム基本識別のみの部分サポート（△）にとどまっていたため、標準規定の feature 識別子（`r7rs`, `exact-closed`, `little-endian`, `x86-64`, `linux`, `posix`, `ulisp` 等）および論理結合（`and`, `or`, `not`）、ならびに `(library <name>)` の静的・動的判定と `else` 節、未一致時の構文エラー送出を完全実装する。
本構文はライブラリ宣言（`define-library` 内）およびトップレベル／式コンテキストの両方で透過的に動作する。

---

## 2. トレーサビリティ / Traceability
- 関連仕様:
  - R7RS-small §4.2.1: Derived expression types (`cond-expand`)
  - R7RS-small §5.5.1: Features
  - R7RS-small §5.6.1: Library declarations (`cond-expand`)
  - [ref_r7rs_compliance.md](../../ulisp/docs/ref_r7rs_compliance.md) §1.1 式とコア構文
  - [DSN-33 (ULisp 包括設計仕様書)](../../docs/designs/DSN-33-ulisp_underlying_x86_native_aot_compiler_architecture_specification.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [ulisp/frontend/010_library.scm](../ulisp/frontend/010_library.scm) (モジュール読み込み時およびトップレベル `cond-expand` 展開、`builtin-library-name?` / `library-exists?` 判定)
- [x] [ulisp/frontend/020_macro_expander.scm](../ulisp/frontend/020_macro_expander.scm) (`core-form-or-primitive?` への `cond-expand` 登録)
- [x] [ulisp/frontend/027_desugar_conditionals.scm](../ulisp/frontend/027_desugar_conditionals.scm) (一般式コンテキストにおける `cond-expand` 脱糖)
- [x] [ulisp/lib/scheme/base.sld](../ulisp/lib/scheme/base.sld) (`cond-expand` エクスポート)
- [x] [ulisp/docs/ref_r7rs_compliance.md](../ulisp/docs/ref_r7rs_compliance.md) (R7RS 準拠状況テーブル更新: △ から ◎)
- [x] [ulisp/tests/test_r7rs_cond_expand.scm](../ulisp/tests/test_r7rs_cond_expand.scm) (新規単体テスト)
- [x] [ulisp/Makefile](../ulisp/Makefile) (テストターゲット統合)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/658-expand-r7rs-cond-expand-feature-identifiers`

1. **Feature 識別子評価基盤の実装**:
   - `ulisp-supported-feature?`:
     - サポート対象: `ulisp`, `r7rs`, `exact-closed`, `little-endian`, `x86-64`, `posix`, `linux`, `unix`
     - 非サポート（#f）: `windows`, `big-endian`, `ratios`, `exact-complex`, `arm`, `arm-64`, `darwin`, `bsd`
   - `ulisp-library-available?`:
     - 指定されたライブラリ名 `(lib ...)` が `builtin-library-name?` か、または `try-load-external-library` / レジストリ探索でロード可能か検査。

2. **条件式再帰評価器 (`eval-feature-requirement`)**:
   - `<feature-identifier>` (シンボル): `(ulisp-supported-feature? id)`
   - `(library <name>)`: `(ulisp-library-available? name)`
   - `(and <req> ...)`: すべての要件が `#t` であれば `#t`、空の場合は `#t`
   - `(or <req> ...)`: いずれかの要件が `#t` であれば `#t`、空の場合は `#f`
   - `(not <req>)`: 要件の真偽値を反転
   - その他: `error` または `#f`

3. **`cond-expand` 節の選択と展開 (`expand-cond-expand`)**:
   - 各節 `(<requirement> <body1> ...)` を順次走査。
   - 要件が `#t` の場合、そのボディをスプライシング展開（複数式の場合は `(begin body1 ...)`）。
   - `(else <body1> ...)` 節の処理。
   - 一致する節がなく `else` もない場合: `syntax-error` `[R7RS §4.2.1]: cond-expand no matching clause` を送出。

4. **コンテキスト別の組み込み**:
   - `define-library` 内: `parse-define-library-form` において `(cond-expand ...)` を解釈し、合致した節のライブラリ宣言（`import`, `export`, `begin`, `include` 等）を `decls` にスプライシング。
   - トップレベルおよび一般式: `010_library.scm` の `expand-cond-expands-in-forms` および `027_desugar_conditionals.scm` の `desugar-cond-expand` で式レベルで脱糖。

5. **単体テストと検証**:
   - `tests/test_r7rs_cond_expand.scm` を作成し、標準識別子、論理結合、library 判定、未一致エラーを網羅検証。

---

## 5. 完了条件 / Success Criteria (DoD)
- [x] `r7rs`, `exact-closed`, `little-endian`, `x86-64`, `posix`, `linux`, `ulisp` が正しく `#t` に評価される
- [x] `windows`, `big-endian`, `ratios` などの非対応識別子が `#f` に評価される
- [x] `(library (scheme base))` などのライブラリ存在条件式が正常に `#t` に評価される
- [x] 存在しない `(library (scheme non-existent-lib-999))` が `#f` に評価される
- [x] `and`, `or`, `not`, `else` を含む複合条件が正しく分岐展開される
- [x] `define-library` 宣言内および通常式コンテキストの両方で動作する
- [x] `ref_r7rs_compliance.md` のステータスが △ から ◎ に更新される
- [x] `make test` および Nanopass テストをすべて通過する
