---
ID: 304
種別: Feature
優先度: High
ステータス: Open (In Progress)
---

# [FEAT] Packrat PEG ランタイムの直接・間接左再帰 (Left Recursion) およびカット演算子 (Cut Operator) の実装 (ID: 304)

## 1. 概要 / Summary
DSN-25 仕様の Packrat PEG パーサーエンジンにおいて、Bryan Ford の古典的 PEG が抱える「左再帰規則の記述制限」を解消するため、Warth et al. (PEPM '08) のアルゴリズムに基づく直接・間接左再帰 (Left Recursion) のシード成長 (Seed Growing) 機構を実装する。
併せて、確定した構文選択肢からの不要なバックトラックを遮断し、エラー特定精度を劇的に向上させるカット演算子 (`Cut` / `^` / `↑`) を実装する。

---

## 2. トレーサビリティ / Traceability
- 関連設計書: [`DSN-25`](../designs/DSN-25-pure_python_packrat_peg_parser_engine.md)
- 関連学術論文: Alessandro Warth et al., "Packrat Parsers Can Support Left Recursion" (PEPM '08)
- 関連 Issue: [#303](closed/303-optimize-packrat-peg-parser-engine.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [`src/core/structures/peg.py`](../../src/core/structures/peg.py)
- [x] [`tests/core/test_peg_left_recursion.py`](../../tests/core/test_peg_left_recursion.py)
- [x] [`tests/core/test_peg_cut_and_resilient.py`](../../tests/core/test_peg_cut_and_resilient.py)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/304-left-recursion-and-cut-operator`

1. **Warth 式左再帰シード成長 (`src/core/structures/peg.py`)**:
   - `ParseContext.lr_detected: Set[int]` による再帰キー検出。
   - `Parser._eval_cached`: `key in ctx.in_progress` 検出時に初期失敗シードを返却し基底ケースを探索。
   - `Parser._grow_lr_seed`: 基底ケース成功後、当該位置以降の依存メモを段階的にパージしながら最長マッチまで固定小数点ループを実行。
2. **カット演算子 (`Cut` / `^`) (`src/core/structures/peg.py`)**:
   - `ParseResult.committed: bool` フラグの導入。
   - `Cut(Parser[None])` によるコミット状態のセット。
   - `Sequence.parse_at`: コミット後の失敗を `committed=True` として上位へ伝搬。
   - `Choice.parse_at`: 選択肢が `committed` 失敗した場合は後続代替案を破棄し即座に失敗を返却。
   - 二項演算子 `p1 ^ p2` による `Sequence(p1, Cut(), p2)` 簡易構文の提供。
3. **数学的結合性と相互左再帰の検証**:
   - 減算演算子の左結合性（`10 - 3 - 2 = 5`）および複合演算子（加減乗除・括弧）の自動検証。

---

## 5. 完了条件 / Success Criteria (DoD)
- [x] 直接左再帰ルール（`Expr <- Expr '+' Term / Term`）が正しくパースされ左結合 AST を構築すること。
- [x] 相互左再帰ルール（`A <- B / 'x'`, `B <- A 'y'`）が正しくパースされること。
- [x] `Cut()` 演算子により外側 Choice のバックトラックが正しく遮断されること。
- [x] `^` 演算子による `Cut` シーケンス記述が機能すること。
- [x] `tests/core/test_peg_left_recursion.py` (4 tests) が 100% PASS すること。
- [x] 循環的複雑度 $CC \le 4$ (Xenon Grade A) および型安全性が維持されていること。
