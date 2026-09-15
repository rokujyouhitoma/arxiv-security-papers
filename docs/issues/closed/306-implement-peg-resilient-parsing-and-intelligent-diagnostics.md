---
ID: 306
種別: Feature
優先度: High
ステータス: Open (In Progress)
---

# [FEAT] 耐障害構文解析 (Resilient Parsing) および高度構文診断ヒューリスティクス (Intelligent Diagnostics) の実装 (ID: 306)

## 1. 概要 / Summary
Web UI や CLI 等のリアルタイム入力環境において、構文エラーが発生しても即座にクラッシュ・中断せず、パニックモード同期（Panic Mode Synchronization）により後続の正常なトークン・文を継続解析して部分 AST を回収する耐障害構文解析 API (`parse_resilient`) を実装する。
併せて、未終了文字列クォートや括弧（丸括弧・角括弧・波括弧）の不整合・不均衡を自動検出し、人間が直感的に修正箇所を特定できる高度構文診断ヒューリスティクス (`_diagnose_syntax_anomaly`) を提供する。

---

## 2. トレーサビリティ / Traceability
- 関連設計書: [`DSN-25`](../designs/DSN-25-pure_python_packrat_peg_parser_engine.md)
- 関連 Issue: [#303](closed/303-optimize-packrat-peg-parser-engine.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [`src/core/structures/peg.py`](../../src/core/structures/peg.py)
- [x] [`tests/core/test_peg_cut_and_resilient.py`](../../tests/core/test_peg_cut_and_resilient.py)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/306-peg-resilient-parsing-and-diagnostics`

1. **高度構文診断ヒューリスティクス (`src/core/structures/peg.py`)**:
   - `_check_unclosed_quotes`: エスケープ文字を考慮したシングル/ダブルクォートの開始位置・行・列のピンポイント検出。
   - `_check_unmatched_brackets`: スタックを用いた括弧の対応検証（未終了括弧・余分な閉じ括弧・括弧種別不一致の特定）。
   - `PEGSyntaxError`: `hint` フィールドを追加し、エラー出力時に診断理由（`Diagnosis: ...`）を明示。
2. **パニックモード耐障害構文解析 (`src/core/structures/peg.py`)**:
   - `Parser.parse_resilient(text, sync_tokens)`: エラー発生位置から同期トークン（`;`, `\n`, `,`, `)`, `]` 等）を探索し、後続の空白をスキップして再同期。
   - 部分 AST の値と収集された構文エラーリスト `Tuple[Optional[T], List[PEGSyntaxError]]` を安全に返却。
3. **回帰テストと挙動検証**:
   - 不完全な入力、壊れた SQL、不一致括弧に対する診断出力の完全一致検証。

---

## 5. 完了条件 / Success Criteria (DoD)
- [x] `_check_unclosed_quotes` が未終了クォートの開始位置を正確に診断すること。
- [x] `_check_unmatched_brackets` が開き括弧の欠落・閉じ括弧の過多を正確に診断すること。
- [x] `parse_resilient` が構文エラーを収集しながら同期トークン以降の有効ノードを抽出すること。
- [x] `tests/core/test_peg_cut_and_resilient.py` (6 tests) が 100% PASS すること。
- [x] 循環的複雑度 $CC \le 4$ (Xenon Grade A) および型安全性が 100% PASS すること。
