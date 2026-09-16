---
ID: 311
種別: Feature / Enhancement
優先度: High
ステータス: Closed
---

# [FEAT] Packrat PEG ランタイムにおける期待トークン（Expected Tokens）追跡と高度構文エラー診断基盤の実装 (ID: 311)

## 1. 概要 / Summary
Packrat PEG パーサーエンジン（`src/core/structures/peg.py`）は、入力テキストの最深到達位置（`max_pos`）と行・列番号、未閉じ引用符の検出、耐障害リカバリ等を備えている。
しかし、文法規則がマッチしなかった地点で「何が期待されていたか」（`expected one of [...]`）を動的に収集・要約する機構が不十分であり、開発者やユーザー、IDE/LSP が構文エラーの根本原因を特定する際に推測が必要となっていた。

本タスクでは、Bryan Ford '04 仕様に準拠した純粋 Python Packrat PEG ランタイムに **Expected Tokens / Rules 追跡エンジン** を組み込み、最深マッチ失敗地点（`max_pos`）において試行されたリテラル（`Literal`）、正規表現トークン（`Regex`）、文字クラス（`CharClass`）、およびルール参照（`RuleRef`）を追跡・要約し、`PEGSyntaxError` の診断メッセージに自動統合した。さらに、Levenshtein 編集距離による Typo 診断ヒント機能（`Did you mean 'SELECT' instead of 'SELCT'?`）を実装した。

---

## 2. トレーサビリティ / Traceability
- 関連設計書: [`DSN-25`](../../designs/DSN-25-pure_python_packrat_peg_parser_engine.md)
- 関連 Issue: [#306](306-implement-peg-resilient-parsing-and-intelligent-diagnostics.md), [#304](304-implement-left-recursion-and-cut-operator-in-peg.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [x] `src/core/structures/peg.py` (`ParseContext` に expected 追跡、`PEGSyntaxError` に `expected` 属性、Levenshtein による Typo 診断ヒント機能を追加)
- [x] `tests/core/test_peg_expected_tokens.py` (新規テストスイート 5件 PASS)
- [x] 全既存テストの互換性維持（`tests/core/` 128件 全件 100% PASS）

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/311-peg-expected-tokens-and-syntax-diagnostics`

1. **`ParseContext` への expected 追跡機構の統合**:
   - `ParseContext` に `expected_tokens: Set[str]` を保持。
   - `_is_ignorable_expected_token` により内部空白等をフィルタリング、`_humanize_token` で正規表現キーワードを自然言語キーワードに正規化。
   - `pos == self.max_pos` で試行されたシンボルを収集、`pos > self.max_pos` で最深到達位置を更新しリセット。
2. **`PEGSyntaxError` の診断強化**:
   - `PEGSyntaxError` に `expected: Tuple[str, ...]` フィールドを追加。
   - 期待トークン一覧を整形表示。
   - Levenshtein 距離（`_levenshtein`）による入力単語と期待トークンの類似度判定および Typo サジェストヒント生成（`Did you mean '...' instead of '...'?`）を統合。
3. **品質検証**:
   - 循環的複雑度 $CC \le 4$（Xenon Grade A）、`mypy --strict` 100% PASS。
   - ユニットテスト全件 PASS。

---

## 5. 完了条件 / Success Criteria (DoD)
- [x] `ParseContext` が最長到達位置 `max_pos` で期待されていたトークン・規則名を過不足なく追跡すること。
- [x] `PEGSyntaxError` が `expected` タプルを保持し、エラーメッセージに整形表示されること。
- [x] 既存の `PEGSyntaxError` 捕捉ロジックおよび下位互換性が 100% 維持されること。
- [x] `xenon Grade A` ($CC \le 4$)、`mypy --strict`、および既存・新規全テストが 100% PASS すること。
