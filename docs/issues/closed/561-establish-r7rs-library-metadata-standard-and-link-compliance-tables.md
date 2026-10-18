---
ID: 561
種別: Feature
優先度: High
ステータス: Closed
完了日: 2026-10-18
---

# [FEAT] R7RS ライブラリメタデータ管理規約（パターンB＋コメントハイブリッド）の策定と準拠表実装リンクの網羅的整備 (ID: 561)

## 1. 概要 / Summary
R7RS 仕様および Scheme の言語文化・哲学（ミニマリズム、ポータビリティ、構文厳格性）に準拠したライブラリメタデータ管理標準として、「パターンB（ライブラリ宣言 `.sld` / ファイル単位でのメタデータ集約）」と「セクションコメント（`;; §X.Y.Z`）記法」のハイブリッド方式を ULisp の公式コーディング規約として確立する。
あわせて、`ulisp/docs/r7rs_specification_compliance.md` 内の準拠状況一覧表に記載されている各構文・手続き・モジュールについて、該当するコンパイラパスおよび標準ライブラリ（`ulisp/lib/*.scm`、`ulisp/passes/*.scm`）への相対リンクを網羅的に設定し、仕様と実装間の追跡性（Traceability）と保守性を飛躍的に高める。

---

## 2. トレーサビリティ / Traceability
- 関連仕様:
  - R7RS-small (Revised^7 Report on the Algorithmic Language Scheme - Small Language)
    - Section 4: Expressions (コア式・派生構文)
    - Section 5: Program Structure (define, define-library, define-record-type, define-values)
    - Section 6: Standard Procedures (等価性、算術、リスト、文字列、ベクタ、多値、遅延評価、例外、ポート)
  - DSN-33 (ULisp 包括設計仕様書)
  - 関連 Issue:
    - Issue #554: ULisp メタコンパイラの R7RS-small および R7RS-large 仕様準拠状況一覧ドキュメントの策定
    - Issue #548: R7RS ライブラリ構文 (define-library / import) の静的脱糖・フラット名前空間インクルード機構の実装

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [ulisp/docs/r7rs_specification_compliance.md](../../ulisp/docs/r7rs_specification_compliance.md) (各行の実装ファイル相対リンク化およびメタデータ方針の記載)
- [x] [docs/issues/561-establish-r7rs-library-metadata-standard-and-link-compliance-tables.md](561-establish-r7rs-library-metadata-standard-and-link-compliance-tables.md) (本 Issue 定義書)
- [x] [docs/issues/README.md](README.md) (Issue 台帳更新)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/561-establish-r7rs-library-metadata-standard-and-link-compliance-tables`

1. **メタデータ標準規約の文書化**:
   - `ulisp/docs/r7rs_specification_compliance.md` の序論または新設セクションに、「R7RS ライブラリメタデータおよびセクションコメント記法ガイドライン」を追記。
   - `.sld` ヘッダにおける `;;; Implements: §X.Y.Z` 記法および `ulisp/lib/*.scm` における `;; §X.Y.Z` 記法を明文化。

2. **仕様準拠表の全行ハイパーリンク化**:
   - `Section 4: Expressions` 表: 該当する `ulisp/passes/020_macro_expander.scm`, `ulisp/passes/030_desugar.scm`, `ulisp/passes/110_closure_convert.scm`, `ulisp/passes/130_lir.scm` への相対リンク付与。
   - `Section 5: Program Structure` 表: `ulisp/passes/010_library.scm`, `ulisp/passes/020_macro_expander.scm`, `ulisp/passes/030_desugar.scm` 等への相対リンク付与。
   - `Section 6: Standard Procedures` 表:
     - 6.1 等価性: `ulisp/lib/equality.scm`
     - 6.2 数値演算: `ulisp/lib/predicates.scm`, `ulisp/compiler/primitives.scm`
     - 6.3 ブール値: `ulisp/compiler/primitives.scm`
     - 6.4 リスト・ペア: `ulisp/lib/list.scm`, `ulisp/compiler/primitives.scm`
     - 6.5 シンボル: `ulisp/passes/040_analysis.scm`, `ulisp/runtime.c`
     - 6.6 文字: `ulisp/compiler/primitives.scm`
     - 6.7 文字列: `ulisp/lib/string.scm`
     - 6.8 ベクタ: `ulisp/lib/vector.scm`
     - 6.9 バイトベクタ: `ulisp/lib/bytevector.scm`
     - 6.10 制御機構: `ulisp/lib/continuation.scm`, `ulisp/lib/values.scm`, `ulisp/passes/030_desugar.scm`
     - 6.11 例外処理: `ulisp/lib/exception.scm`, `ulisp/passes/030_desugar.scm`
     - 6.12 環境・評価: `ulisp/passes/010_library.scm`
     - 6.13 入出力ポート: `ulisp/lib/port.scm`, `ulisp/lib/reader.scm`, `ulisp/lib/printer.scm`
     - 6.14 システムインタフェース: `ulisp/lib/posix.scm`
   - 遅延評価 (4.2.5 / SRFI-45): `ulisp/lib/promise.scm`
   - パラメータ (4.2.6 / SRFI-39): `ulisp/lib/parameter.scm`

3. **相対リンク検証**:
   - AGENTS.md のルール（絶対パス禁止、相対パス厳格遵守）に基づきリンクの正当性を検証。

---

## 5. 完了条件 / Success Criteria (DoD)
- [x] `ulisp/docs/r7rs_specification_compliance.md` にメタデータ管理設計方針（パターンB＋コメントハイブリッド）が明記されていること。
- [x] `ulisp/docs/r7rs_specification_compliance.md` 内の全テーブルにおいて「内部実装ファイル」列と「備考・技術仕様」列が明確に分離されていること。
- [x] 実装が存在する構文・手続き・ライブラリの「内部実装ファイル」列から、該当ファイルへの相対リンク（例: `../lib/list.scm` や `../passes/030_desugar.scm`）が網羅されていること。
- [x] 絶対パス（`/workspace/...` 等）が含まれず、すべて相対パスで記述されていること。
- [x] `docs/issues/README.md` 台帳に本 Issue 561 が登録されていること。
