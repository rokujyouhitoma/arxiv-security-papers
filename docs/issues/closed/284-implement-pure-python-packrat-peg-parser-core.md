---
ID: 284
種別: Feature
優先度: High
ステータス: Closed (Completed)
---

# [FEAT/ENH] 純粋 Python 製汎用 Packrat PEG (Parsing Expression Grammar) コアランタイム基盤の実装 (DSN-25 Phase 1) (ID: 284)

## 1. 概要 / Summary
設計仕様書 [DSN-25](../designs/DSN-25-pure_python_packrat_peg_parser_engine.md) に基づき、ゼロ外部依存の純粋 Python による汎用 Packrat PEG (Parsing Expression Grammar) コアランタイム基盤 (`src/core/structures/peg.py`) を新規開発する。
本基盤は、順序付き選択 (`/`)、連接、0回以上/1回以上反復、省略可能、肯定/否定先読み、正規表現マッチング、遅延評価・相互再帰解決 (`RuleRef`)、およびセマンティックアクション (`.map()`) の各コンビネータを提供する。
また、Packrat メモ化キャッシュによる線形時間 $O(N)$ のパース計算量保証、最長一致到達位置追跡 (Max-Position Tracking) による行・列番号・期待トークン付きエラー診断、最大再帰深度ガード (`max_depth=500`) および最大入力長ガード (`max_input_length=65536`) による DoS/ReDoS 対策を内蔵する。

---

## 2. トレーサビリティ / Traceability
- 設計書: [DSN-25-pure_python_packrat_peg_parser_engine.md](../designs/DSN-25-pure_python_packrat_peg_parser_engine.md) (第3章、第4章、第7章、第8章)
- 関連標準: Bryan Ford (2004) "Parsing Expression Grammars: A Recognition-Based Syntactic Foundation", "Packrat Parsing: Simple, Powerful, Lazy, Linear Time"
- 前提成果物: [src/core/structures/__init__.py](../../src/core/structures/__init__.py)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [src/core/structures/peg.py](../../src/core/structures/peg.py) (Packrat PEG コアランタイム基盤の新規作成)
- [x] [src/core/structures/__init__.py](../../src/core/structures/__init__.py) (公開エクスポートの追加)
- [x] [tests/core/test_peg.py](../../tests/core/test_peg.py) (Packrat PEG 単体テスト・計算量検証・エラー診断・DoS防御テスト)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/284-packrat-peg-parser-core`

1. **基本データ構造とコンテキスト設計**:
   - `ParseResult[T]`: `success: bool`, `value: Optional[T]`, `next_pos: int`, `error_msg: Optional[str]`, `error_pos: int` を保持。
   - `ParseContext`: 入力文字列 `text`、メモ化テーブル `memo: Dict[Tuple[int, int], ParseResult[Any]]`、`max_pos: int`、`expected_tokens: Set[str]`、再帰深度カウンター `depth: int`、最大深度 `max_depth: int = 500`、最大入力長 `max_input_length: int = 65536`、左再帰・循環再帰検知 `in_progress: Set[Tuple[int, int]]`。
   - `PEGSyntaxError`: 行番号・列番号（1-indexed）・スニペット・期待トークン一覧を成形した人間可読メッセージを生成。
2. **コンビネータクラス群の実装 (`Parser[T]`)**:
   - `Parser[T]` (抽象基底クラス): `parse(text: str) -> T`, `parse_at(ctx: ParseContext, pos: int) -> ParseResult[T]`, `map(fn: Callable[[T], R]) -> Parser[R]`
   - `Empty()`: 空文字列（常にマッチ、0文字消費）
   - `Literal(expected: str)`: 文字列完全一致
   - `Regex(pattern: str, flags: int = 0)`: 正規表現マッチング
   - `Seq(*parsers: Parser[Any])`: 連接コンビネータ（`+` 演算子によるフラット化サポート）
   - `Choice(*parsers: Parser[Any])`: 順序付き選択コンビネータ（`/` 演算子によるフラット化サポート）
   - `Repetition(parser: Parser[T], min_count: int = 0)`: 0回以上 (`ZeroOrMore`) / 1回以上 (`OneOrMore`) 反復
   - `Optional(parser: Parser[T])`: 省略可能 (`Opt`)
   - `Predicate(parser: Parser[Any], is_positive: bool = True)`: 肯定先読み (`AndPred`) / 否定先読み (`NotPred`)
   - `RuleRef(name: str)`: 遅延参照・相互再帰解決（`define(parser: Parser[T])`）
3. **Packrat メモ化キャッシュと線形時間保証**:
   - 各パーサーインスタンスの一意な `rule_id` と `pos` をキーとしてメモ化テーブルを管理。
   - バックトラック発生時の冗長パースを $O(1)$ で解消し、$O(N)$ 線形時間を達成。
4. **セキュリティ・エラーハンドリング**:
   - 入力長超過時は即座に `ValueError`。
   - 再帰呼び出し時に `depth > max_depth` または `in_progress` 検知で `PEGSyntaxError`。
   - 最長到達位置（`max_pos`）での期待トークン追跡により的確なエラー位置と候補を表示。
5. **品質ゲート遵守**:
   - `mypy --strict` 準拠、全関数 Xenon Cyclomatic Complexity Rank A (<= 4)。

---

## 5. 完了条件 / Success Criteria (DoD)
- [x] `src/core/structures/peg.py` が新規作成され、全コンビネータ・メモ化・エラー追跡・セキュリティガードが完備されていること
- [x] `src/core/structures/__init__.py` に全コンビネータがエクスポートされていること
- [x] `tests/core/test_peg.py` において、全コンビネータ、算術式パーサー、相互再帰、エラー位置特定、線形時間 $O(N)$ 検証、最大再帰制限が 100% PASS すること
- [x] `make check_format` および `make static_analysis` (mypy strict, Xenon Rank A) が 100% PASS すること

