---
ID: 665
種別: Feature
優先度: High
ステータス: Closed (Completed)
---

# [FEAT/ENH] R7RS 仕様トレーサビリティ管理規約の全ライブラリ適用および診断タグ検証の確立 (ID: 665)

## 1. 概要 / Summary
`ref_r7rs_compliance.md` 第3章（Issue #561）で規定された「ハイブリッド方式（パターンB: ライブラリ宣言でのメタデータ集約 ＋ 手続き直前の `;; §X.Y.Z` セクションコメント）」を、`ulisp/lib/` 配下の全ライブラリファイル（`*.sld` / `*.scm`）に漏れなく適用し、コンパイラ診断エラーへの R7RS 仕様節タグ付与および CI 静的検証スクリプト `scripts/verify_r7rs_traceability.py` を確立する。
これにより、ULisp コードベース全体の R7RS 仕様追跡可能性（Traceability）を 100% 担保し、自動検証ゲートを構築する。

---

## 2. トレーサビリティ / Traceability
- 関連仕様:
  - [ref_r7rs_compliance.md](../../ulisp/docs/ref_r7rs_compliance.md) §3 R7RS 仕様トレーサビリティとライブラリメタデータ管理規約
  - [DSN-33 (ULisp 包括設計仕様書)](../../docs/designs/DSN-33-ulisp_underlying_x86_native_aot_compiler_architecture_specification.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [ulisp/lib/**/*.sld](../ulisp/lib/) (全 SLD ヘッダへの仕様節およびトレーサビリティ記載)
- [x] [ulisp/lib/**/*.scm](../ulisp/lib/) (全手続き定義直前への `;; §X.Y.Z` コメント付与)
- [x] [ulisp/frontend/020_macro_expander.scm](../ulisp/frontend/020_macro_expander.scm) (構文エラー時 `[R7RS §X.Y.Z]` タグ付与)
- [x] [ulisp/frontend/030_desugar.scm](../ulisp/frontend/030_desugar.scm) (構文エラー時 `[R7RS §X.Y.Z]` タグ付与)
- [x] [scripts/verify_r7rs_traceability.py](../scripts/verify_r7rs_traceability.py) (新規 CI トレーサビリティ検証スクリプト)
- [x] [Makefile](../Makefile) / [ulisp/Makefile](../ulisp/Makefile) (品質ゲート統合)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/665-enforce-r7rs-specification-traceability-and-diagnostic-tags`

1. **`ulisp/lib/**/*.sld` の全点検とヘッダ適用**:
   - すべての `.sld` ファイル冒頭に以下の統一形式ヘッダを付与・確認：
     ```scheme
     ;;; =======================================================================
     ;;; Library: (<lib> <name>)
     ;;; Specification: R7RS-small / SRFI ...
     ;;; Traceability: ulisp/docs/ref_r7rs_compliance.md
     ;;; =======================================================================
     ```

2. **`ulisp/lib/*.scm` のセクションコメント付与**:
   - 各手続き・マクロ定義の直前に `;; §X.Y.Z ...` 形式のコメントが存在することを網羅点検し、未記載の箇所に付与。

3. **コンパイラ診断エラータグの統一**:
   - `020_macro_expander.scm` および `030_desugar.scm` 内の `syntax-error` および `error` 出力メッセージを精査し、R7RS 仕様節タグ `[R7RS §X.Y.Z]` を付与。

4. **自動検証スクリプト (`scripts/verify_r7rs_traceability.py`) の実装**:
   - `ulisp/lib/` 配下の全 `.sld` ファイルに `Traceability: ulisp/docs/ref_r7rs_compliance.md` が含まれているか検査。
   - `ulisp/lib/*.scm` 内の手続き定義がセクションコメントを伴っているか静的解析。
   - `make static_analysis` または `make test` で実行可能にする。

---

## 5. 完了条件 / Success Criteria (DoD)
- [x] `ulisp/lib/` 配下のすべての `.sld` に仕様トレーサビリティヘッダが存在する
- [x] 全標準手続きに `;; §X.Y.Z` コメントが付与されている
- [x] コンパイラ構文エラーに R7RS 仕様節タグが含まれる
- [x] トレーサビリティ自動検証スクリプト `scripts/verify_r7rs_traceability.py` が 100% PASS する
- [x] `make test` を通過する
