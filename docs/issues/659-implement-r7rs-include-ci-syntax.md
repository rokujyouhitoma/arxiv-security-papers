---
ID: 659
種別: Feature
優先度: Medium
ステータス: Open (New)
---

# [FEAT/ENH] R7RS §4.1.7 大文字小文字無視ファイル包含構文 (include-ci) の実装 (ID: 659)

## 1. 概要 / Summary
R7RS-small §4.1.7 (Inclusion: `include-ci`) に準拠し、外部ファイルを読み込む際に大文字・小文字を同一視（Case-insensitive / Case-folding）して S 式をパースしプログラムへ静的結合する `include-ci` 構文を実装する。
ULisp では通常の `include` は実装済み（△）であるが、大文字小文字無視版である `include-ci` が未実装（×）であるため、レガシー Scheme コードや R7RS 標準ポータブルコードの包含を可能にする。

---

## 2. トレーサビリティ / Traceability
- 関連仕様:
  - R7RS-small §4.1.7: Inclusion (`include-ci`)
  - [ref_r7rs_compliance.md](../../ulisp/docs/ref_r7rs_compliance.md) §1.1 式とコア構文
  - [DSN-33 (ULisp 包括設計仕様書)](../../docs/designs/DSN-33-ulisp_underlying_x86_native_aot_compiler_architecture_specification.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [ulisp/frontend/010_library.scm](../ulisp/frontend/010_library.scm) (ライブラリ宣言内 include-ci 処理)
- [ ] [ulisp/frontend/030_desugar.scm](../ulisp/frontend/030_desugar.scm) (トップレベル式コンテキストでの include-ci 展開)
- [ ] [ulisp/lib/reader.scm](../ulisp/lib/reader.scm) (リーダーにおける case-folding モード対応)
- [ ] [ulisp/tests/test_r7rs_include_ci.scm](../ulisp/tests/test_r7rs_include_ci.scm) (新規単体テスト)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/659-implement-r7rs-include-ci-syntax`

1. リーダー (`reader.scm`) またはパーサにシンボル名の大文字小文字フォールディング（小文字統一）フラグを追加。
2. `include-ci` 処理時に指定されたファイルを読み込む際、ケースフォールディングを有効化して S 式リストを構築。
3. `begin` スプライシングによってプログラム本体に静的インライン展開。
4. 単体テストにより、大文字シンボル（例: `LAMBDA`, `DEFINE`）が小文字として解釈され正しくコンパイルされることを検証。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] `include-ci` で指定されたファイル内の大文字シンボルが小文字に正規化されて読み込まれる
- [ ] ライブラリ定義内およびトップレベルの両方で `include-ci` が使用可能
- [ ] 既存の `include`（Case-sensitive）の動作に副作用を与えない
- [ ] `make test` を通過する

