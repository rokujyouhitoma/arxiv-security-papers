---
ID: 277
種別: Feature
優先度: Low
ステータス: Closed
---

# [FEAT/DATABASE] SQLite 完全互換化: ユーザー定義照合順序 (User-Defined Collation) 登録機構の実装 (ID: 277)

## 1. 概要 / Summary
SQLite C/Python API 仕様 ([sqlite.org/c3ref/create_collation.html](https://sqlite.org/c3ref/create_collation.html)) に準拠したユーザー定義照合順序（User-Defined Collation）の登録インターフェースを Pure Python SQL Engine (`src/database/sql/`) および PEP 249 Driver (`src/database/ipc/driver.py`) に実装する。
Python コールバック関数を用いて任意の言語・ロケール・ドメイン特化の文字列比較関数をエンジンへ動的登録可能にし、`ORDER BY ... COLLATE custom_collation` での柔軟なソートおよび条件比較を可能にする。

---

## 2. トレーサビリティ / Traceability
- 準拠仕様: [SQLite create_collation](https://sqlite.org/c3ref/create_collation.html)
- 関連設計書:
  - [DSN-05-01 SQL 構文仕様およびサポートマトリクス設計書](../designs/DSN-05-01-sql_syntax_and_specification_support_matrix.md)
  - [DSN-14 次世代データベースエンジン包括的アーキテクチャ設計書](../designs/DSN-14-next_gen_database_engine_architecture.md)

---

## 3. 脅威モデルとセキュリティ要件 / Threat Model & Security Requirements
- **No-eval 原則**:
  - コールバック登録および照合順序適用において `eval()` や `exec()` は一切使用せず、純粋な呼び出し可能オブジェクト（Callable）または functools.cmp_to_key を介して安全にディスパッチする。
- **例外安全性と DoS 耐性**:
  - ユーザー定義の比較関数が例外を送出した場合、クエリ実行全体をクラッシュさせずに適切にキャッチして `SQLExecutionError` としてハンドルする。
- **型安全性**:
  - 比較対象の値が None や数値等の非文字列型である場合、SQLite 互換の安全な文字列フォールバックまたは None セーフな比較を実施する。

---

## 4. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [src/database/sql/executor.py](../../src/database/sql/executor.py): `SQLExecutor.create_collation(name: str, callback: Optional[Callable[[str, str], int]])` の実装および `_collate_transform` / `_sort_and_paginate` でのカスタム比較関数キー対応
- [x] [src/database/ipc/driver.py](../../src/database/ipc/driver.py): `Connection.create_collation(name: str, callback: Optional[Callable[[str, str], int]])` の公開
- [x] [tests/database/sql/test_sql_engine.py](../../tests/database/sql/test_sql_engine.py): 単体テスト追加（カスタム照合順序の登録、ORDER BY COLLATE、逆順ソート、PEP 249 Connection 経由の動作確認）

---

## 5. 実装方針 / Implementation Plan
Target Branch: `feat/277-implement-sqlite-parity-user-defined-collation`

1. **`SQLExecutor` に照合順序レジストリを追加**:
   - `self.collations: Dict[str, Callable[[str, str], int]] = {}`
   - `create_collation(self, name: str, callback: Optional[Callable[[str, str], int]]) -> None`:
     - `callback is None` の場合は登録解除。
     - `name.upper()` で正規化して登録。
2. **`_sort_and_paginate` におけるカスタム照合順序の適用**:
   - `order_collate` が指定されており、かつ `self.collations` に存在する場合:
     - `functools.cmp_to_key` を用いたカスタムソートキー関数を生成し、`rows.sort(key=...)` に適用。
     - None や非文字列の比較境界値（SQLite では NULL が最小）を安全にハンドリング。
   - 標準照合順序 (`NOCASE`, `RTRIM`, `BINARY`) は従来どおり高速変換パスを維持。
3. **`Connection.create_collation` の委譲**:
   - `src/database/ipc/driver.py` の `Connection` クラスに `create_collation(name, callback)` を追加し、`self._executor.create_collation(name, callback)` へ転送。

---

## 6. 完了条件 / Success Criteria (DoD)
- [x] `executor.create_collation("reverse", lambda a, b: (a > b) - (a < b))` でカスタム照合順序を登録できること。
- [x] `SELECT * FROM tbl ORDER BY name COLLATE reverse` で登録関数に従ってソートされること。
- [x] `conn.create_collation(...)` 経由でも登録・利用可能なこと。
- [x] `tests/database/sql/test_sql_engine.py` にテストを追加し PASS すること。
- [x] `make format`, `make static_analysis`, `xenon` Rank A (<= 5), `mypy --strict` が PASS すること。

