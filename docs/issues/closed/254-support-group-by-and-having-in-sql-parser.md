---
ID: 254
種別: Bug
優先度: High
ステータス: Closed
---

# [BUG] SQL Parser における GROUP BY / HAVING 句未対応によるテーブル名誤パースおよび dbshell 実行エラーの改修 (ID: 254)

## 1. 概要 / Summary
`manage.py dbshell` または `SQLExecutor` において、`GROUP BY` や `HAVING` 句を含む集計クエリを実行した際、SQL Parser (`src/database/sql/parser.py`) が `GROUP BY` および `HAVING` 句を構文要素として切り出さず、`FROM` 句のテーブル名の一部として誤認識する不具合が発生している。
その結果、テーブル名が `'cti_cwes GROUP BY cwe_id HAVING COUNT(*) > 1'` のようにパースされ、`Table does not exist` エラーでクエリが異常終了する。

### 再現手順 / Steps to Reproduce
1. 以下のコマンドを実行する:
   ```bash
   ./manage.py dbshell -c "SELECT cwe_id, COUNT(*) FROM cti_cwes GROUP BY cwe_id HAVING COUNT(*) > 1"
   ```
2. 以下のエラーが発生することを確認する:
   ```text
   SQL Error: Table 'cti_cwes GROUP BY cwe_id HAVING COUNT(*) > 1' does not exist
   ```

### 再現環境 / Environment
- OS / Env: Linux (Antigravity IDE runtime)
- Target Components:
  - `src/database/sql/ast.py`
  - `src/database/sql/parser.py`
  - `src/database/sql/executor.py`
  - `src/cli/commands/dbshell.py`

---

## 2. 影響範囲と関連ファイル / Scope and Affected Files

### コア SQL エンジン (Domain-Agnostic)
- [x] [ast.py](file:///workspace/arxiv-security-papers/src/database/sql/ast.py): `SelectStatement` データクラスに `group_by: List[str]` および `having: Optional[str]` フィールドを追加
- [x] [parser.py](file:///workspace/arxiv-security-papers/src/database/sql/parser.py):
  - `_extract_having_clause(clean_sql: str) -> Tuple[str, Optional[str]]` の新設
  - `_extract_group_by_clause(clean_sql: str) -> Tuple[str, List[str]]` の新設
  - `_parse_single_select` における抽出パイプラインの順序是正 (`LIMIT` → `ORDER BY` → `HAVING` → `GROUP BY` → `WHERE` → `FROM`)
- [x] [executor.py](file:///workspace/arxiv-security-papers/src/database/sql/executor.py):
  - `_group_and_aggregate_rows(rows: List[Dict[str, Any]], stmt: SelectStatement) -> List[Dict[str, Any]]` の実装 (`COUNT(*)`, `SUM`, `AVG`, `MIN`, `MAX`)
  - `_filter_having_rows(rows: List[Dict[str, Any]], having_expr: str) -> List[Dict[str, Any]]` の安全な条件評価実装 (No-eval)
  - `_exec_select` パイプラインへのグルーピング・HAVING 統合
- [x] [tests/database/sql/test_sql_engine.py](file:///workspace/arxiv-security-papers/tests/database/sql/test_sql_engine.py): `GROUP BY` / `HAVING` の各種集計パターンの単体テスト追加

### ガバナンス・台帳
- [x] [docs/issues/README.md](file:///workspace/arxiv-security-papers/docs/issues/README.md): Issue 台帳のステータス更新 (`Closed`)

---

## 3. 根本原因分析 (RCA) / Root Cause Analysis

1. **SQL Parser の句抽出順序と欠落**:
   - `src/database/sql/parser.py` の `_parse_single_select()` では、末尾から順に `LIMIT` (`_extract_limit_clause`), `ORDER BY` (`_extract_order_by_clause`), `WHERE` (`_extract_where_clause`) を切り出して除去する。
   - しかし、`GROUP BY` と `HAVING` の抽出ロジックが実装されていないため、`WHERE` の有無にかかわらず `FROM` 以降の文字列全体に `GROUP BY cwe_id HAVING COUNT(*) > 1` が残留する。
2. **テーブル名マッチングの過剰貪欲一致**:
   - `re.match(r"^SELECT\s+(.+?)\s+FROM\s+(.+)$", clean_sql)` により、`group(2)` に `cti_cwes GROUP BY cwe_id HAVING COUNT(*) > 1` が渡される。
   - `_parse_from_and_joins()` はこれをテーブル識別子として扱い、`TableRef(name='cti_cwes GROUP BY cwe_id HAVING COUNT(*) > 1')` を生成する。
3. **SQLExecutor のルックアップ失敗**:
   - カタログ登録テーブル名（`cti_cwes`）と一致しないため、存在しないテーブルとしてエラー送出に至る。

---

## 4. セキュリティ脅威分析 & 設計制約 (STRIDE & Hardening)

- **Threat: Code Injection via HAVING expression (Tampering / Elevation of Privilege)**:
  - `HAVING` 句の条件式（例: `COUNT(*) > 1` や `avg_score <= 4.5`）を評価する際、Pythonの組み込み `eval()` や `exec()` は絶対に使用してはならない（AST Sandbox 規約違反）。
  - **対策**: 単純な二項比較式を正規表現または安全なトークン分割で抽出し、演算子 (`=`, `!=`, `<>`, `>`, `<`, `>=`, `<=`) と数値・文字列リテラルのみを許可するセキュアパーサー (`_eval_having_condition`) を実装する。
- **Threat: ReDoS / Resource Exhaustion (Denial of Service)**:
  - 不正な多重ネストの正規表現による ReDoS を防ぐため、正規表現はシンプルな線形パターンに限定する。
- **Constraint: Clean Architecture**:
  - `src/database` にドメイン固有ロジック（`cwe_` や `cti_` 等のテーブル名決め打ち）を含めず、あらゆるテーブルで汎用的に動作する SQL エンジン機能として実装する。
- **Constraint: Xenon CC Rank A (<= 5)**:
  - 各抽出・集計・フィルタ関数を単一責務の小さな関数に分割し、循環的複雑度を 5 以下に抑える。

---

## 5. 実装方針 / Implementation Plan
Target Branch: `fix/254-support-group-by-and-having-in-sql-parser`

### 5.1 AST の拡張 (`src/database/sql/ast.py`)
`SelectStatement` に以下を追加:
```python
@dataclass
class SelectStatement(SQLStatement):
    ...
    group_by: List[str] = field(default_factory=list)
    having: Optional[str] = None
```

### 5.2 SQL Parser の抽出パイプライン拡張 (`src/database/sql/parser.py`)
1. **`_extract_having_clause(clean_sql: str) -> Tuple[str, Optional[str]]`**:
   - `re.search(r"\s+HAVING\s+(.+)$", clean_sql, re.IGNORECASE)` で `HAVING` 句を抽出し、前方文字列と切り離す。
2. **`_extract_group_by_clause(clean_sql: str) -> Tuple[str, List[str]]`**:
   - `re.search(r"\s+GROUP\s+BY\s+(.+)$", clean_sql, re.IGNORECASE)` で `GROUP BY` 句を抽出。カンマ区切りでカラム名のリストを生成。
3. **抽出パイプラインの順序是正 (`_parse_single_select`)**:
   ```python
   clean_sql, limit_val = self._extract_limit_clause(clean_sql)
   clean_sql, order_by, order_desc = self._extract_order_by_clause(clean_sql)
   clean_sql, having_raw = self._extract_having_clause(clean_sql)
   clean_sql, group_by_cols = self._extract_group_by_clause(clean_sql)
   clean_sql, where_raw = self._extract_where_clause(clean_sql)
   ```
   これにより、`select_m.group(2)` には純粋なテーブル名および JOIN 句のみが残る。

### 5.3 SQL Executor の集約・HAVING 処理 (`src/database/sql/executor.py`)
1. **`_group_and_aggregate_rows(rows: List[Dict[str, Any]], stmt: SelectStatement) -> List[Dict[str, Any]]`**:
   - `stmt.group_by` の各カラム値からタプルキーを生成し、グループ化（辞書ベース）。
   - 各グループに対して集計プロジェクションを実行:
     - `COUNT(*)`, `COUNT(1)`: `len(group_rows)`
     - `SUM(col)`, `AVG(col)`, `MIN(col)`, `MAX(col)`: 数値集約
     - グループ化キーカラム: そのまま出力
     - その他非集約カラム: グループの先頭レコードの値を代表値として採用
2. **`_filter_having_rows(rows: List[Dict[str, Any]], having_expr: str) -> List[Dict[str, Any]]`**:
   - `having_expr` を安全にパース（例: `COUNT(*) > 1` $\rightarrow$ 左辺: `COUNT(*)`, 演算子: `>`, 右辺: `1`）。
   - 型変換（数値比較または文字列比較）を行い、条件に合致するグループ行のみを抽出。
3. **`_exec_select` の統合**:
   - `filtered_rows = self._filter_select_rows(current_rows, stmt.where_clauses)` の直後で、`stmt.group_by` が存在する場合に集約と HAVING フィルタを適用。

---

## 6. 完了条件 / Success Criteria (DoD)

- [x] `./manage.py dbshell -c "SELECT cwe_id, COUNT(*) FROM cti_cwes GROUP BY cwe_id HAVING COUNT(*) > 1"` がエラーにならず、重複なし（0 rows）または正常な集計結果を返すこと。
- [x] `SelectStatement` においてテーブル名が正しく `cti_cwes` として認識され、`group_by=['cwe_id']`, `having='COUNT(*) > 1'` が AST に保持されること。
- [x] `COUNT(*)`, `COUNT(1)`, `SUM`, `AVG`, `MIN`, `MAX` を用いた `GROUP BY` および `HAVING` の集約テストが `tests/database/sql/test_sql_engine.py` に追加され全件 PASS すること。
- [x] `eval` や `exec` を使わない安全な条件評価が徹底されていること（No-eval principle）。
- [x] `src/database` にドメイン固有ロジックを含めず、完全な汎用インフラストラクチャとして実装されていること。
- [x] `make format`, `make static_analysis` (xenon CC Rank A <= 5, mypy --strict), `make test` が 100% PASS すること。
