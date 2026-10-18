---
ID: 550
種別: Feature
優先度: Medium
ステータス: Closed
---

# [FEAT/ENH] R7RS 準拠の遅延評価機構 (delay / force / delay-force / promise?) の実装 (ID: 550)

## 1. 概要 / Summary
R7RS-small (Section 4.2.5) に規定されている遅延評価（Lazy Evaluation）機構を ULisp に導入する。
ストリーム処理、無限遅延リスト、遅延アルゴリズムの実装基盤として、`delay`, `force`, `delay-force`, `make-promise`, `promise?` を実装する。プロミス（promise）は SRFI-45（Primitives for Expressing Iterative Lazy Algorithms）および R7RS-small Section 4.2.5 規格に完全準拠し、未評価・評価済みタグと値またはサンクを保持するコンテナセル構造として表現し、再帰的な `delay-force`（反復的な遅延チェーン）においても空間リークやスタックオーバーフローを発生させないトランポリン平坦化構造をサポートする。

---

## 2. トレーサビリティ / Traceability
- **規格仕様**: R7RS-small Section 4.2.5 "Delayed evaluation", Section 7.3 "Derived expression types", SRFI-45
- **設計仕様書**: [DSN-33 (ULISP 包括設計仕様書)](../../docs/designs/DSN-33-ulisp_underlying_x86_native_aot_compiler_architecture_specification.md)
- **関連Issue**: Issue #536 (R7RS ベクタ型), Issue #533 (衛生的マクロ展開器), Issue #554 (R7RS 準拠状況ドキュメント)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [ulisp/lib/promise.scm](../../ulisp/lib/promise.scm) (新規作成: SRFI-45 / R7RS Section 4.2.5 準拠のランタイム関数群)
- [x] [ulisp/passes/020_macro_expander.scm](../../ulisp/passes/020_macro_expander.scm) (コア予約語登録: `delay`, `delay-force`)
- [x] [ulisp/passes/030_desugar.scm](../../ulisp/passes/030_desugar.scm) (マクロ脱糖・正規化パス: `delay`, `delay-force`)
- [x] [ulisp/passes/160_backend_c.scm](../../ulisp/passes/160_backend_c.scm) (`%idiv` で `%rdx` に剰余をセット、文字列リテラルのアライメント保証)
- [x] [ulisp/compiler.scm](../../ulisp/compiler.scm) (コンパイラ本体再生成 `make compiler`)
- [x] [ulisp/Makefile](../../ulisp/Makefile) (ビルドスクリプト・テストターゲット追加: `test_promise`)
- [x] [ulisp/bootstrap.sh](../../ulisp/bootstrap.sh) (ブートストラップ時ライブラリ連結に `lib/promise.scm` 追加)
- [x] [ulisp/test.sh](../../ulisp/test.sh) (x86-64 テストランナー追加: Step 33, Step 32b, Step 33b)
- [x] [ulisp/test_c.sh](../../ulisp/test_c.sh) (Portable C テストランナー追加: Step 14)
- [x] [ulisp/tests/test_promise.scm](../../ulisp/tests/test_promise.scm) (新規作成: 遅延評価包括テストスイート)
- [x] [ulisp/tests/test_record.scm](../../ulisp/tests/test_record.scm) (ポータブル出力形式へのリファクタリング)
- [x] [ulisp/docs/r7rs_specification_compliance.md](../../ulisp/docs/r7rs_specification_compliance.md) (R7RS 準拠状況テーブル更新: 4.2.5 ◎)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/550-r7rs-lazy-evaluation-delay-force`

1. **プロミスデータ構造設計 (SRFI-45 準拠)**:
   - プロミスは `#(%%promise (tag . val-or-thunk))` のベクタセルとして表現する。
   - `tag` はシンボル `'eager` (評価済み値保持) または `'lazy` (未評価サンク保持)。
   - `(promise? x)`: 第 0 要素が `'%%promise` であるベクタであるかを判定。
   - `(make-promise obj)`: `obj` が既にプロミスであればそのまま返し、それ以外は `(vector '%%promise (cons 'eager obj))` を生成して返す。
2. **脱糖 (Desugaring)**:
   - `(delay-force expr)` $\to$ `(%%make-promise 'lazy (lambda () expr))`
   - `(delay expr)` $\to$ `(%%make-promise 'lazy (lambda () (%%make-promise 'eager expr)))`
3. **`force` のトランポリン展開とメモ化**:
   - `(force promise)` は非プロミスが渡された場合はそのまま返す。
   - プロミス内部セルが `'eager` の場合は即座にキャッシュ値を返す。
   - `'lazy` の場合はサンクを実行し、戻り値がプロミスであれば内容ペアをインプレースで更新し、元のプロミスへの参照共有を保ちながらループでトランポリン平坦化する。
   - 再入可能（re-entrant）な遅延自己参照においても同一値が安定してキャッシュされることを保証する。
4. **テストスイートの構築 (`ulisp/tests/test_promise.scm`)**:
   - `promise?` 型述語のテスト（正常値、非プロミス、ベクタ境界値）。
   - 基本的な遅延評価およびメモ化（副作用カウンターが 1 回のみ増加すること）。
   - `make-promise` による値とプロミスのラップ挙動。
   - `delay-force` による深層遅延ループ（5,000回以上の反復でスタック消費が定数空間であること）。
   - R7RS Section 4.2.5 規格書の再入可能自己参照プロミスの動作検証。
   - 遅延ストリーム（無限整数の生成、`stream-filter` による偶数フィルタリング）。
   - ネストした `(delay (delay 42))` の段階的評価。
5. **ビルドパイプライン統合・ドキュメント更新**:
   - `ulisp/Makefile`, `ulisp/bootstrap.sh`, `ulisp/test.sh`, `ulisp/test_c.sh` に `lib/promise.scm` を統合。
   - `make test`, `make test_c`, `make bootstrap` を実行し、全テスト通過と 3 段階ブートストラップのビット完全一致を検証。
   - `ulisp/docs/r7rs_specification_compliance.md` の Section 4.2.5 を ◎ に更新。

---

## 5. 完了条件 / Success Criteria (DoD)
- [x] `delay`, `force`, `delay-force`, `make-promise`, `promise?` が R7RS 仕様通りに動作すること
- [x] メモ化により、同一プロミスの複数回 `force` で副作用式が 1 度だけ評価されること
- [x] `delay-force` の反復実行でスタックオーバーフローが発生しないこと
- [x] x86-64 および Portable C の両バックエンドで 100% 動作すること
- [x] `make test`, `make test_c`, `make bootstrap` が 100% PASS すること
- [x] `ulisp/docs/r7rs_specification_compliance.md` の準拠状況が更新されていること

---

## 6. 完了報告 / Completion Notes
- **完了日**: 2026-10-18
- **検証実績**:
  - Native x86-64: `test.sh` (Step 0〜33, 32b, 33b, ブートストラップ3世代 diff 0) 全体正常終了。
  - Portable C: `test_c.sh` (Step 0〜14: 117 tests) 全体正常終了 (`-Wall -Wextra -Werror` 警告ゼロ)。
  - `make test_promise` および `make test_record` のスタンドアロン実行完全通過。
- **特記事項**:
  - Portable C バックエンドにおける `%idiv` 演算時の `%rdx` (剰余) 設定不備を修正し、`modulo` 演算が正確に動作するよう改修。
  - C バックエンド文字列リテラル配列の 8 バイト境界アライメント (`__attribute__((aligned(8)))`) を適用し、ポインタタグ判定の正確性を担保。
