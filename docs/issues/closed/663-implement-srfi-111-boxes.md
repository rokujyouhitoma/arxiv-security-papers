---
ID: 663
種別: Feature
優先度: Medium
ステータス: Closed (Completed)
---

# [FEAT/ENH] R7RS-large / SRFI 111 Boxes 単一要素可変セル API の実装 (ID: 663)

## 1. 概要 / Summary
R7RS-large Red Edition および SRFI 111 (Boxes) に準拠し、単一の可変オブジェクトを格納・参照・更新する第一級ボックスセル型とその操作手続き群（`box`, `box?`, `unbox`, `set-box!`）を実装する。
現在 ULisp では 1要素ベクタやペアでの代用運用（△）にとどまっていたが、型安全なボックス型タグまたはレコード型を独立提供し、クロージャ間の共有可変状態の明示的カプセル化やポインタ操作を可能にする。

---

## 2. トレーサビリティ / Traceability
- 関連仕様:
  - SRFI 111: Boxes
  - R7RS-large Red Edition (Data Structures: Boxes)
  - [ref_r7rs_compliance.md](../../ulisp/docs/ref_r7rs_compliance.md) §2.1 Red Edition
  - [DSN-33 (ULisp 包括設計仕様書)](../../docs/designs/DSN-33-ulisp_underlying_x86_native_aot_compiler_architecture_specification.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [ulisp/lib/box.scm](../ulisp/lib/box.scm) (新規ボックス型・アクセサ・変更手続き実装)
- [x] [ulisp/lib/srfi/111.sld](../ulisp/lib/srfi/111.sld) (新規 SRFI 111 ライブラリ定義)
- [x] [ulisp/lib/scheme/box.sld](../ulisp/lib/scheme/box.sld) (R7RS-large エクスポート)
- [x] [ulisp/docs/ref_r7rs_compliance.md](../ulisp/docs/ref_r7rs_compliance.md) (R7RS 準拠状況テーブル更新: △ から ◎)
- [x] [ulisp/tests/test_srfi_111_boxes.scm](../ulisp/tests/test_srfi_111_boxes.scm) (新規単体テスト)
- [x] [ulisp/Makefile](../ulisp/Makefile) (テストターゲット統合)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/663-implement-srfi-111-boxes`

1. **型構造の設計**:
   - ボックスは単一の値を保持する可変コンテナである。
   - レコード型または専用内部タグ `(%box <val-cell>)` または `(cons '%box (cons value '()))` を採用。
   - ベクタや通常のペアと `eq?` / `equal?` / `box?` で混同されない排他性を保証。

2. **プリミティブ手続きの実装 (`ulisp/lib/box.scm`)**:
   - `(box value)`: `(cons '%box (cons value '()))`
   - `(box? obj)`: `(and (pair? obj) (eq? (car obj) '%box) (pair? (cdr obj)))`
   - `(unbox b)`:
     - `(if (box? b) (cadr b) (error "unbox: not a box" b))`
   - `(set-box! b val)`:
     - `(if (box? b) (set-car! (cdr b) val) (error "set-box!: not a box" b))`

3. **ライブラリの作成**:
   - `ulisp/lib/srfi/111.sld` および `ulisp/lib/scheme/box.sld` を定義。

4. **単体テストの作成**:
   - 基本生成、参照、破壊的更新の検証。
   - 他の型（ペア、ベクタ、文字列、数値）に対して `box?` が `#f` を返すことの排他性検証。
   - `unbox` / `set-box!` に非ボックスを渡した際の型エラー検証。

---

## 5. 完了条件 / Success Criteria (DoD)
- [x] `box`, `box?`, `unbox`, `set-box!` が仕様通り動作する
- [x] 他の型（ベクタ、ペア等）と `box?` が衝突せず厳密に型識別できる
- [x] `(srfi 111)` および `(scheme box)` としてインポート可能
- [x] `ref_r7rs_compliance.md` に SRFI 111 の完全準拠（◎）が反映される
- [x] `make test` を通過する
