---
ID: 271
種別: Feature
優先度: Medium
ステータス: Closed
---

# [FEAT/DATABASE] SQLite 完全互換化: VACUUM INTO 'filename' オンラインバックアップの実装 (ID: 271)

## 1. 概要 / Summary
SQLite 3.27.0+ 公式仕様 ([sqlite.org/lang_vacuum.html#vacuuminto](https://sqlite.org/lang_vacuum.html#vacuuminto)) に準拠した `VACUUM INTO 'filename'` 構文を Pure Python SQL Engine (`src/database/sql/`) に実装する。
稼働中のアクティブデータベースを排他ロックすることなく、指定されたターゲットファイルパスへ一貫性のあるクリーンなスナップショット（コンパクション済み完全コピー）を出力できるようにする。
これにより、無停止オンラインバックアップ、データベースの複製、および外部への安全なデータエクスポートを実現する。

構文例:
```sql
-- 1. 全テーブルのオンラインバックアップ
VACUUM INTO 'backup.db';

-- 2. 特定テーブル/スキーマのバックアップ
VACUUM accounts INTO 'accounts_backup.db';
```

---

## 2. セキュリティ & アーキテクチャ脅威分析 (STRIDE / No-eval 原則)
- **改ざん防止 & パストラバーサル防御 (Tampering / Information Disclosure 防御)**:
  - バックアップ先ファイルパス `into_file` において、`..` を含むパストラバーサルやシステム領域への不正出力を検証・防止。相対パスおよび許可ディレクトリ外への無制限な書き込みを安全にハンドリング。
- **既存ファイル上書き防止 (Safety / DoS 防御)**:
  - SQLite 仕様に従い、宛先ファイルが既に存在する場合は `SQLExecutionError("cannot VACUUM - target file already exists")` を送出して既存データの誤消去を防止。
- **アトミック書き込み (Atomicity / Fault Tolerance)**:
  - 一時ファイル（`.tmp`）にスナップショットを生成し、全テーブルおよびスキーマの書き出し完了後にアトミックにリネーム（`os.replace`）することで、バックアップ途中のクラッシュや破損ファイルの残存を防止。
- **循環的複雑度 (Cyclomatic Complexity) 統制**:
  - バックアップ実行エンジン `_exec_vacuum_into(into_file, target_table)`、テーブル複製ヘルパー、および既存ファイル検証ヘルパーを責務分離し、全関数で Xenon Rank A ($\le 5$) を厳格順守。

---

## 3. トレーサビリティ / Traceability
- 準拠仕様: [SQLite VACUUM INTO](https://sqlite.org/lang_vacuum.html#vacuuminto)
- 関連設計書:
  - [DSN-05-01 SQL 構文仕様およびサポートマトリクス設計書](../designs/DSN-05-01-sql_syntax_and_specification_support_matrix.md)
  - [DSN-14 次世代データベースエンジン包括的アーキテクチャ設計書](../designs/DSN-14-next_gen_database_engine_architecture.md)

---

## 4. 影響範囲と関連ファイル / Scope and Affected Files
- [src/database/sql/ast.py](../../src/database/sql/ast.py):
  - `VacuumStatement`: `target_table: Optional[str] = None`, `into_file: Optional[str] = None`（既存定義の確認・維持）
- [src/database/sql/parser.py](../../src/database/sql/parser.py):
  - `_parse_vacuum_stmt`: `VACUUM [target_table] [INTO 'filename']` の複合指定パターンに完全対応
- [src/database/sql/executor.py](../../src/database/sql/executor.py):
  - `_exec_vacuum`: `stmt.into_file` が指定された場合に `_exec_vacuum_into` へディスパッチ
  - `_exec_vacuum_into`: 宛先ファイルの存在チェック、ターゲット SQLEngine / MultiTableVDB インスタンスの生成、全テーブル定義 (DDL) およびデータ行の複製、アトミックフラッシュ
- [tests/database/sql/test_sql_engine.py](../../tests/database/sql/test_sql_engine.py):
  - 単体テスト（通常 VACUUM, VACUUM INTO による完全バックアップ生成, バックアップ先 DB の復元クエリ照会, 既存ファイル存在時のエラーハンドリング）追加

---

## 5. 実装方針 / Implementation Plan
Target Branch: `feat/271-implement-sqlite-parity-vacuum-into`

1. **パーサー改善 (`src/database/sql/parser.py`)**:
   - `_parse_vacuum_stmt`: `r"^VACUUM(?:\s+([a-zA-Z0-9_]+))?(?:\s+INTO\s+['\"](.*?)['\"])?$"` または柔軟な正規表現により、テーブル名指定および `INTO 'filename'` の単独・同時指定を正確に抽出。
2. **エグゼキューター拡張 (`src/database/sql/executor.py`)**:
   - `_exec_vacuum_into(stmt, role)`:
     1. `into_file` のパス検証。既にファイルが存在すれば `SQLExecutionError: cannot VACUUM - target file already exists` を送出。
     2. 新しい `SQLEngine(storage_path=into_file)`（または適切なストレージインスタンス）を初期化。
     3. バックアップ対象テーブルの DDL（`raw_sql` や `CREATE TABLE` 構造）を新エンジンで実行。
     4. 各テーブルのメタデータ・ベクトル行を新エンジンへ一括コピー。
     5. バックアップ先 DB を保存し、結果辞書 `{"command": "VACUUM", "status": "ok", "into": into_file, "target": tgt}` を返却。
3. **テスト & 品質検証**:
   - `tests/database/sql/test_sql_engine.py` に `test_vacuum_into_lifecycle` を追加。
   - 生成されたバックアップファイルを新たな SQLExecutor で開き、テーブルと行が完全に復元されていることを検証。
   - `make format`, `make static_analysis` (Rank A, mypy --strict) の 100% PASS を確認。

---

## 6. 完了条件 / Success Criteria (DoD)
- [x] `VACUUM INTO 'backup.db'` が構文エラーなく正常に実行されること。
- [x] 指定パスに新しいデータベースファイルが生成され、全テーブルのスキーマおよびデータが複製されていること。
- [x] バックアップファイルから別の SQLExecutor で全データが正常に SELECT 照会できること。
- [x] 既に存在するファイルパスを `INTO` に指定した場合に `SQLExecutionError` となること。
- [x] `tests/database/sql/test_sql_engine.py` に単体・統合テストを追加し PASS すること。
- [x] `make format`, `make static_analysis` (Rank A, mypy --strict) が PASS すること。
