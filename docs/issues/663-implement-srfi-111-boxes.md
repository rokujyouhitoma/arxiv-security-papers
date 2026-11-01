---
ID: 663
種別: Feature
優先度: Medium
ステータス: Open (New)
---

# [FEAT/ENH] R7RS-large / SRFI 111 Boxes 単一要素可変セル API の実装 (ID: 663)

## 1. 概要 / Summary
R7RS-large Red Edition および SRFI 111 (Boxes) に準拠し、単一の可変オブジェクトを格納・参照・更新する第一級ボックスセル型とその操作手続き群（`box`, `box?`, `unbox`, `set-box!`）を実装する。
現在 ULisp では 1要素ベクタやペアでの代用運用（△）にとどまっていたが、専用レコード型またはヒープタグによる型安全なボックス型を独立提供し、クロージャ間の共有可変状態の明示的カプセル化を可能にする。

---

## 2. トレーサビリティ / Traceability
- 関連仕様:
  - SRFI 111: Boxes
  - R7RS-large Red Edition (Data Structures)
  - [ref_r7rs_compliance.md](../../ulisp/docs/ref_r7rs_compliance.md) §2.1 Red Edition
  - [DSN-33 (ULisp 包括設計仕様書)](../../docs/designs/DSN-33-ulisp_underlying_x86_native_aot_compiler_architecture_specification.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [ulisp/lib/box.scm](../ulisp/lib/box.scm) (新規ボックス型・アクセサ実装)
- [ ] [ulisp/lib/srfi/111.sld](../ulisp/lib/srfi/111.sld) (新規 SRFI 111 ライブラリ定義)
- [ ] [ulisp/lib/scheme/box.sld](../ulisp/lib/scheme/box.sld) (R7RS-large エクスポート)
- [ ] [ulisp/tests/test_srfi_111_boxes.scm](../ulisp/tests/test_srfi_111_boxes.scm) (新規単体テスト)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/663-implement-srfi-111-boxes`

1. `define-record-type` または専用タグ付き 1 要素構造としてボックス型を定義。
2. プリミティブ手続きの実装：
   - `(box value)`: 値を格納したボックスを生成
   - `(box? obj)`: ボックス型述語
   - `(unbox box)`: 格納値を参照
   - `(set-box! box value)`: 格納値を破壊的更新
3. `(srfi 111)` および `(scheme box)` ライブラリ定義を作成。
4. 単体テストにより、生成・更新・型述語の排他性を検証。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] `box`, `box?`, `unbox`, `set-box!` が仕様通り動作する
- [ ] 他の型（ベクタ、ペア等）と `box?` が衝突せず厳密に型識別できる
- [ ] `(srfi 111)` および `(scheme box)` としてインポート可能
- [ ] `make test` を通過する

