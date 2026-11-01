---
ID: 665
種別: Feature
優先度: High
ステータス: Open (New)
---

# [FEAT/ENH] R7RS 仕様トレーサビリティ管理規約の全ライブラリ適用および診断タグ検証の確立 (ID: 665)

## 1. 概要 / Summary
`ref_r7rs_compliance.md` 第3章（Issue #561）で規定された「ハイブリッド方式（パターンB: ライブラリ宣言でのメタデータ集約 ＋ 手続き直前の `;; §X.Y.Z` セクションコメント）」を、`ulisp/lib/` 配下の全ライブラリファイル（`*.sld` / `*.scm`）に漏れなく適用し、コンパイラ診断エラーへの R7RS 仕様節タグ付与および CI 静的検証スクリプトを確立する。
これにより、ULisp コードベース全体の R7RS 仕様追跡可能性（Traceability）を 100% 担保する。

---

## 2. トレーサビリティ / Traceability
- 関連仕様:
  - [ref_r7rs_compliance.md](../../ulisp/docs/ref_r7rs_compliance.md) §3 R7RS 仕様トレーサビリティとライブラリメタデータ管理規約
  - [DSN-33 (ULisp 包括設計仕様書)](../../docs/designs/DSN-33-ulisp_underlying_x86_native_aot_compiler_architecture_specification.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [ulisp/lib/**/*.sld](../ulisp/lib/) (全 SLD ヘッダへの仕様節およびトレーサビリティ記載)
- [ ] [ulisp/lib/**/*.scm](../ulisp/lib/) (全手続き定義直前への `;; §X.Y.Z` コメント付与)
- [ ] [ulisp/frontend/020_macro_expander.scm](../ulisp/frontend/020_macro_expander.scm) (構文エラー時 `[R7RS §X.Y.Z]` タグ出力)
- [ ] [ulisp/frontend/030_desugar.scm](../ulisp/frontend/030_desugar.scm) (構文エラー時 `[R7RS §X.Y.Z]` タグ出力)
- [ ] [scripts/verify_r7rs_traceability.py](../scripts/verify_r7rs_traceability.py) (新規 CI トレーサビリティ検証スクリプト)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/665-enforce-r7rs-specification-traceability-and-diagnostic-tags`

1. `ulisp/lib/` 以下のすべての `.sld` ファイルに、対応する R7RS 仕様節および `ref_r7rs_compliance.md` へのトレーサビリティヘッダコメントを追加・点検。
2. `ulisp/lib/*.scm` の全手続き・マクロ定義の直前に、R7RS セクション番号コメント（例: `;; §6.10 Control features: dynamic-wind`）を付与。
3. マクロ展開器（Pass 020）および構文脱糖器（Pass 030）のエラー送出箇所を精査し、標準構文エラーに `[R7RS §X.Y.Z]` プレフィックスを統一付与。
4. Makefile または CI に `verify_r7rs_traceability.py` チェックを組み込み、未準拠ファイルの自動検出を可能にする。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] `ulisp/lib/` 配下のすべての `.sld` に仕様トレーサビリティヘッダが存在する
- [ ] 全標準手続きに `;; §X.Y.Z` コメントが付与されている
- [ ] コンパイラ構文エラーに R7RS 仕様節タグが含まれる
- [ ] トレーサビリティ自動検証スクリプトが 100% PASS する
- [ ] `make test` を通過する

