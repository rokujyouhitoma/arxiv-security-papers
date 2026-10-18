---
ID: 554
種別: Documentation
優先度: Medium
ステータス: Closed
---

# [DOC] ULisp メタコンパイラの R7RS-small および R7RS-large 仕様準拠状況一覧ドキュメントの策定 (ID: 554)

## 1. 概要 / Summary
ULisp ネイティブ AOT メタコンパイラがサポートしている言語機能および未サポート機能を網羅的・体系的に整理するため、R7RS-small (Section 4〜6 および全16標準ライブラリ) および R7RS-large (Red Edition / Tangerine Edition / 主要SRFI) の全仕様項目と仕様番号（Section 番号 / SRFI 番号）を対応付けた技術ドキュメント `ulisp/docs/r7rs_specification_compliance.md` を策定する。また、`ulisp/docs/README.md` に本ドキュメントへのリンクを追加する。

---

## 2. トレーサビリティ / Traceability
- **規格仕様**:
  - R7RS-small: Revised^7 Report on the Algorithmic Language Scheme (Small Language, 2013)
  - R7RS-large: Red Edition (Data Structures), Tangerine Edition (Numerics)
- **設計仕様書**: [DSN-33 (ULISP 包括設計仕様書)](../../docs/designs/DSN-33-ulisp_underlying_x86_native_aot_compiler_architecture_specification.md)
- **関連Issue**:
  - Issue #548 (define-library / import)
  - Issue #540 (call/cc & dynamic-wind)
  - Issue #538 (values & call-with-values)
  - Issue #533 (衛生的マクロ展開器)
  - Issue #531 (例外 guard & raise)
  - Issue #501 (Cheney's 2-Space GC)
  - Issue #549 (define-record-type)
  - Issue #550 (delay / force)
  - Issue #551 (シーケンス手続き拡充)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [ulisp/docs/r7rs_specification_compliance.md](../../ulisp/docs/r7rs_specification_compliance.md) (新規作成: R7RS 仕様準拠状況詳細一覧ドキュメント)
- [x] [ulisp/docs/README.md](../../ulisp/docs/README.md) (体系目次へのリンク追加)
- [x] [docs/issues/README.md](../../docs/issues/README.md) (Issue 台帳登録)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/554-r7rs-compliance-documentation`

1. **R7RS-small 仕様番号の完全網羅**:
   - Section 4.1, 4.2, 4.3 (式・構文・マクロ)
   - Section 5.1〜5.6 (プログラム構造・モジュール)
   - Section 6.1〜6.14 (全標準手続き・等価性・数値・コレクション・継続・例外・I/O・システム)
   - 16標準ライブラリ (`(scheme base)`, `(scheme read)`, `(scheme write)` 等) の対応状況
2. **R7RS-large 仕様番号 (SRFI) の完全網羅**:
   - Red Edition: SRFI 1, 9, 11, 39, 111, 113, 116, 117, 121, 125, 128, 132, 133, 134, 135, 146
   - Tangerine Edition: SRFI 141, 143, 144, 151, 160, 179
   - その他主要 SRFI: SRFI 170, 64, 18/226, 115, 145 等
3. **ステータス・内部実装パスの明記**:
   - 各項目について ◎ (完全対応), △ (部分対応), × (未対応), ✕* (AOT対象外) を付与し、対応する `ulisp/passes/` や `ulisp/lib/` の実装ファイル、および未対応機能の背景・計画を記載。
4. **品質ゲート検証**:
   - 相対リンクの完全整合性確認。

---

## 5. 完了条件 / Success Criteria (DoD)
- [x] `ulisp/docs/r7rs_specification_compliance.md` が作成され、R7RS-small および R7RS-large の全仕様番号が明記されていること
- [x] サポート状況（◎ / △ / × / ✕*）および内部実装ファイル・未対応理由が整理されていること
- [x] `ulisp/docs/README.md` の目次にリンクが追加されていること
- [x] 相対リンクが正しく機能し、絶対パスが含まれないこと
- [x] Issue 554 がクローズされ、`main` ブランチにコミット・マージされること
