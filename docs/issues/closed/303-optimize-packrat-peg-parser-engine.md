# Issue #303: Packrat PEG パーサーエンジンの包括的最適化（選択的メモ化・整数ビットパックキー化・ファサード LRU キャッシュ層）の実装

## 1. 基本情報
- **Issue ID**: `#303`
- **タイトル**: Packrat PEG パーサーエンジンの包括的最適化（選択的メモ化・整数ビットパックキー化・ファサード LRU キャッシュ層）の実装
- **ステータス**: `Closed (Completed)`
- **優先度**: `High`
- **種別**: `Optimization`
- **作成日**: 2026-09-16
- **完了日**: 2026-09-16
- **担当エージェント**: Systems Architect (SA) / Software Development (SWD) / Information Security Specialist (SEC) / QA Specialist (QA)
- **関連設計書**: [`DSN-25`](../../designs/DSN-25-pure_python_packrat_peg_parser_engine.md), [`DSN-05`](../../designs/DSN-05-database_engine_architecture.md), [`DSN-18`](../../designs/DSN-18-enterprise_multi_field_query_and_faceted_search.md)
- **対象ブランチ**: `feat/303-optimize-packrat-peg-parser-engine`

---

## 2. 目的と背景 (Context & Rationale)
本プロジェクトでは、DSN-25 仕様に則り Pure Python 完全自作の Packrat PEG 構文解析エンジンがデータベース（DQL, DML, DDL, 式）、検索エンジン、ナレッジグラフ、W3C Turtle の全域で中核パーサーとして本番稼働している。
しかしながら、プロファイリングの結果、以下の 3 つの重大な最適化余地が判明した：

1. **Packrat メモ化逆転現象**:
   - `Literal`, `CharClass`, `AnyChar`, `Empty`, `Regex` 等の終端記号（Terminals）は判定コストが極小（~10-20ns）であるにもかかわらず、メモ化テーブルへの辞書検索・タプル生成・格納コスト（~100ns）により、メモ化すること自体がオーバーヘッドとなっていた。
2. **タプル生成によるヒープアロケーション・GC 圧迫**:
   - `_eval_cached()` はルール評価毎に `(rule_id, pos)` タプルオブジェクトを生成しており、1 回のパースで数千〜数万個のタプルが生成・破棄され、Python GC への負荷となっていた。
3. **高頻度ファサード層における AST キャッシュの欠如**:
   - 同一クエリ（バッチ処理や Web API で反復実行される SQL クエリや検索式）であっても、呼び出し毎にゼロから構文木を再解析していた。

これらを解消するため、**プラン D（コアエンジンの選択的メモ化＆ビットパック整数キー化 ＋ ファサード層 Bounded LRU AST キャッシュ）** を実装し、コールドパースおよびウォームパースの両面において極大の性能向上を達成する。

---

## 3. セキュリティ・耐障害性分析 (Security & Threat Mitigation)
- **ReDoS / 構文解析 DoS 耐性**:
  - Bryan Ford POPL '04 準拠の Packrat PEG による線形時間 $O(N)$ 解析保証を厳格に維持。
  - `ParseContext` の入力長上限（`max_input_length=65536`）および最大再帰深度（`max_depth=500`）による DoS ガードを完全維持。
- **メモリリーク防止**:
  - ファサード層のキャッシュには境界付き LRU（`functools.lru_cache(maxsize=1024)`）を採用し、無制限キャッシュによるメモリ枯渇を根本排除。
  - キャッシュクリア API（`clear_sql_parser_caches()`, `clear_search_query_cache()`）を提供し、メモリ回収やテスト分離性を担保。
- **キャッシュ汚染・可変副作用の防止**:
  - 検索クエリ結果等のリスト返却に対しては、キャッシュ内部でイミュータブルな `tuple` として保持し、返却時に浅いコピー `list()` を生成して返却することで、呼び出し元による破壊的変更からキャッシュを隔離保護。

---

## 4. 実装フェーズと詳細タスク (Implementation Plan)

### Phase 1: コア PEG ランタイムの低レベル最適化 (`src/core/structures/peg.py`)
1. **単一整数ビットパックキー化**:
   - `ParseContext.memo`: `Dict[int, ParseResult[Any]]`
   - `ParseContext.in_progress`: `Set[int]`
   - キー生成: `key = (self.rule_id << 20) | pos`（単一 Python 整数。ヒープ上のタプル生成ゼロ化）。
2. **選択的メモ化 (Selective Memoization)**:
   - `Parser.memoize: ClassVar[bool] = True`
   - 終端記号（`Empty`, `Literal`, `Regex`, `AnyChar`, `CharClass`）で `memoize: ClassVar[bool] = False`。
   - `_eval_cached`: `if not self.memoize:` の場合は直接 `self.parse_at(ctx, pos)` を呼出。
3. **循環・深度チェックのメソッド分離**:
   - `_check_recursion_guards(ctx, pos, key)` に分離し、循環的複雑度 $CC \le 4$ (Xenon Grade A) を死守。

### Phase 2: SQL サブシステム ファサード LRU キャッシュ層 (`src/database/sql/`)
1. **`src/database/sql/expr_parser.py`**:
   - モジュールシングルトン `_GLOBAL_EXPR_AOT_PARSER`。
   - `@lru_cache(maxsize=1024)` による `parse_sql_expr(text: str)` のキャッシュ化。
   - `clear_sql_expr_cache()` の実装。
2. **`src/database/sql/dql_parser.py`**:
   - `@lru_cache(maxsize=1024)` による `parse_dql(text: str)` のキャッシュ化。
   - `clear_dql_cache()` の実装。
3. **`src/database/sql/dml_parser.py`**:
   - `@lru_cache(maxsize=1024)` による `parse_dml(text: str)` のキャッシュ化。
   - `clear_dml_cache()` の実装。
4. **`src/database/sql/ddl_parser.py`**:
   - `@lru_cache(maxsize=1024)` による `parse_ddl(text: str)` のキャッシュ化。
   - `clear_ddl_cache()` の実装。
5. **`src/database/sql/parser.py`**:
   - モジュールシングルトン `_GLOBAL_SQL_PARSER`。
   - `@lru_cache(maxsize=1024)` による `parse_sql(sql_query: str)` のキャッシュ化。
   - 全サブシステム一括クリア関数 `clear_sql_parser_caches()` の提供。
6. **`src/database/sql/__init__.py`**:
   - `clear_sql_parser_caches` の公開。

### Phase 3: 検索クエリパーサー キャッシュ統合 (`src/search/query/query_parser.py`)
1. `_cached_aot_search_parse(cleaned: str) -> Tuple[QueryClause, ...]`:
   - `@lru_cache(maxsize=1024)`
2. `QueryParser.parse`:
   - キャッシュタプルから `list()` を生成して返却（キャッシュ汚染防止）。
3. `clear_search_query_cache()` の実装。

### Phase 4: ベンチマーク・検証・ドキュメント更新
1. `tests/database/test_sql_subsystems_benchmark.py`:
   - コールドパース（キャッシュクリア状態）とウォームパース（キャッシュ有効状態）の比較テスト追加。
2. `docs/designs/DSN-25-pure_python_packrat_peg_parser_engine.md`:
   - セクション 7.6「Packrat PEG エンジン包括的最適化（選択的メモ化・ビットパック整数キー・Bounded LRU キャッシュ）」追記。

---

## 5. 完了条件 (Definition of Done)
- [x] コアランタイム `src/core/structures/peg.py` で単一整数ビットパックキー化および選択的メモ化が動作していること。
- [x] 終端記号（`Empty`, `Literal`, `Regex`, `AnyChar`, `CharClass`）のメモ化がバイパスされていること。
- [x] `parse_sql`, `parse_sql_expr`, `parse_dql`, `parse_dml`, `parse_ddl`, `QueryParser.parse` に Bounded LRU キャッシュが組み込まれていること。
- [x] キャッシュクリア API（`clear_sql_parser_caches()`, `clear_search_query_cache()`）が提供され、正常に機能すること。
- [x] `tests/core/` (105 tests) が 100% PASS すること。
- [x] `tests/search/` (108 tests) および `tests/database/` (428 tests) が 100% PASS すること。
- [x] コールド・ウォーム時の性能改善がベンチマークテストで定量検証されること。
- [x] `make check_format` (flake8 0 errors)、`make static_analysis` (xenon Grade A $CC \le 4$, mypy --strict 0 errors) が 100% PASS すること。
- [x] 設計書 `DSN-25` に最適化アーキテクチャが反映されていること。
