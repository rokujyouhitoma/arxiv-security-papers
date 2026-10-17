---
ID: 550
種別: Feature
優先度: Medium
ステータス: Open (New)
---

# [FEAT/ENH] R7RS 準拠の遅延評価機構 (delay / force / delay-force / promise?) の実装 (ID: 550)

## 1. 概要 / Summary
R7RS-small (Section 4.2.5) に規定されている遅延評価（Lazy Evaluation）機構を ULisp に導入する。
ストリーム処理、無限遅延リスト、遅延アルゴリズムの実装基盤として、`delay`, `force`, `delay-force`, `make-promise`, `promise?` を実装する。プロミス（promise）は「評価済みフラグ、キャッシュされた計算結果、または未評価のクロージャ」を保持するメモ化セル（ベクタまたはペア構造）として表現し、再帰的な `delay-force`（反復的な遅延チェーン）においてもメモリ・スタックを無駄に消費しないトランポリン構造をサポートする。

---

## 2. トレーサビリティ / Traceability
- **規格仕様**: R7RS-small Section 4.2.5 "Delayed evaluation"
- **設計仕様書**: [DSN-33 (ULISP 包括設計仕様書)](../../docs/designs/DSN-33-ulisp_underlying_x86_native_aot_compiler_architecture_specification.md)
- **関連Issue**: Issue #536 (R7RS ベクタ型), Issue #533 (衛生的マクロ展開器)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [ulisp/lib/promise.scm](../../ulisp/lib/promise.scm) (新規作成: 遅延評価標準マクロおよびランタイム関数)
- [ ] [ulisp/compiler.scm](../../ulisp/compiler.scm) (マクロテーブルまたは標準環境組み込み)
- [ ] [ulisp/tests/test_promise.scm](../../ulisp/tests/test_promise.scm) (新規作成: 遅延評価包括テストスイート)
- [ ] [ulisp/test.sh](../../ulisp/test.sh) (テストランナー追加)
- [ ] [ulisp/test_c.sh](../../ulisp/test_c.sh) (Portable C テストランナー追加)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/550-r7rs-lazy-evaluation-delay-force`

1. **プロミスデータ構造設計**:
   - プロミスを 3 要素のベクタ `#(%%promise <done?> <val-or-thunk>)` として定義。
   - `(promise? x)` は第 0 要素が `'%%promise` であるかを検査。
2. **マクロ脱糖**:
   - `(delay expr)` $\to$ `(make-promise (lambda () expr))`
   - `(delay-force expr)` $\to$ `(make-promise (lambda () expr))`（未フラット化プロミス）
3. **`force` のトランポリン展開**:
   - `force` はプロミスを受け取り、未評価であればサンクを実行。
   - サンクの戻り値が別のプロミスである場合（`delay-force` 由来）、ループでアンパックし、スタックを深く消費することなく平坦化（flatten）して結果をキャッシュ。
   - 評価済みプロミスに対して再度 `force` が呼ばれた場合は、即座にキャッシュされた値を返す（メモ化）。
4. **テストスイートの構築**:
   - 基本的な遅延評価とメモ化（副作用が 1 度しか起きないことの確認）。
   - `delay-force` による深層遅延ループ（スタックオーバーフローしないことの確認）。
   - 遅延ストリーム（エラトステネスの篩等の無限リスト）。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] `delay`, `force`, `delay-force`, `make-promise`, `promise?` が R7RS 仕様通りに動作すること
- [ ] メモ化により、同一プロミスの複数回 `force` で副作用式が 1 度だけ評価されること
- [ ] `delay-force` の反復実行でスタックオーバーフローが発生しないこと
- [ ] x86-64 および Portable C の両バックエンドで 100% 動作すること
- [ ] `make test`, `make test_c`, `make bootstrap` が 100% PASS すること
