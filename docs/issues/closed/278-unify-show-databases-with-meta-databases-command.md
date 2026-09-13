---
ID: 278
種別: Bug
優先度: Medium
ステータス: Closed
---

# [BUG/DB] `SHOW DATABASES;` と `.databases` の返却結果が乖離している (ID: 278)

## 1. 概要 / Summary

`manage.py dbshell` において、同じ「データベース一覧」を意図する 2 つのコマンドが全く異なる結果を返す。

- **`.databases`（メタコマンド）**: `settings.py` の `DATABASES` 設定から `get_database_scopes()` で構築したスコープ一覧を返す。実際の運用スコープ（`arxiv_security_db`, `cti_catalog_db`, `graph_db`, `analytics_db`）が正しく表示される。
- **`SHOW DATABASES;`（SQL文）**: `SQLExecutor.known_databases` を参照するが、起動時はこのフィールドが空のため、ハードコードされたフォールバック値 `["default_db", "main"]` が返される。これらは実際には存在しない仮想名称である。

### 実際の出力差異

```
# .databases
+---------------------+--------+-----------------------------------------------------+
| Database Scope      | Tables | Description                                         |
+---------------------+--------+-----------------------------------------------------+
| * all               | 19     | All federated databases and scopes                  |
|   arxiv_security_db | 3      | Core arXiv Papers & Plain-text Virtual Tables       |
|   cti_catalog_db    | 7      | MITRE ATT&CK & CTI Catalog (MultiTable VDB)         |
|   graph_db          | 2      | Security Knowledge Graph & SKO (MultiTable VDB)     |
|   analytics_db      | 5      | Telemetry, Trends & Strategic KPIs (MultiTable VDB) |
+---------------------+--------+-----------------------------------------------------+

# SHOW DATABASES;
+------------+
| Database   |
+------------+
| default_db |
| main       |
+------------+
```

### 再現手順 / Steps to Reproduce

1. `manage.py dbshell` を起動
2. `.databases` を実行 → 正しいスコープ一覧が表示される
3. `SHOW DATABASES;` を実行 → `default_db`, `main` というダミー値が返る

### 再現環境 / Environment

- OS / Env: Linux (arxiv-security-papers workspace)
- File: `src/cli/commands/dbshell.py`, `src/database/sql/executor.py`

---

## 2. 影響範囲と関連ファイル / Scope and Affected Files

- [ ] [`src/database/sql/executor.py`](../../src/database/sql/executor.py) — `_exec_show_databases()` および `SQLExecutor.__init__()` の `known_databases` 初期化
- [ ] [`src/cli/commands/dbshell.py`](../../src/cli/commands/dbshell.py) — `_meta_databases()` が参照する `DATABASE_SCOPES`
- [ ] [`src/settings.py`](../../src/settings.py) — `get_database_scopes()` の定義

---

## 3. 根本原因分析 (RCA) / Root Cause Analysis

**情報源の二重管理（設計上の非統合）** が根本原因。

| コマンド | 情報源 | 登録タイミング |
|---|---|---|
| `.databases` | `settings.py::get_database_scopes()` | アプリ起動時（静的） |
| `SHOW DATABASES;` | `SQLExecutor.known_databases` | `ATTACH DATABASE` 実行時（動的） |

`SQLExecutor` は初期化時に `known_databases={}` で起動し、`settings.py` のスコープ情報は一切注入されない。`_exec_show_databases()` が `known_databases` を参照しても空のため、ハードコードのフォールバック `["default_db", "main"]` が返る。

---

## 4. 暫定対処と恒久対策 / Workaround & Permanent Fix

* **暫定対処 (Workaround)**: ユーザーは `.databases` を使う（`SHOW DATABASES;` は信頼しない）。
* **恒久対策 (Permanent Fix)**: 以下のいずれか（またはその組み合わせ）：
  1. **Option A**: `SQLExecutor` 初期化時に `settings.get_database_scopes()` から `known_databases` を自動注入し、`SHOW DATABASES;` が設定スコープを返すようにする。
  2. **Option B**: `_exec_show_databases()` が `known_databases` に加えて `settings.get_database_scopes()` もマージして返すよう修正する（エンジン層に settings 依存が入る問題あり）。
  3. **Option C（推奨）**: `SQLExecutor` の `known_databases` コンストラクタ引数に、`dbshell` 起動時に `settings.get_database_scopes()` を渡すよう `_meta_databases` の上位コンテキストで注入する（Clean Architecture を維持しつつ解決）。

---

## 5. 実装方針 / Implementation Plan

Target Branch: `fix/278-unify-show-databases-with-settings-scopes`

1. `src/cli/commands/dbshell.py` の `SQLExecutor` 生成箇所で `known_databases=get_database_scopes()` を渡す（または `dbshell` 初期化フローで注入）。
2. `src/database/sql/executor.py` の `_exec_show_databases()` のフォールバック `["default_db", "main"]` を削除し、`known_databases` が空の場合は空リストを返すよう修正。
3. `SHOW DATABASES;` の結果に「Database Scope」列の説明文（Description）を追加することも検討（オプション）。

---

## 6. 完了条件 / Success Criteria (DoD)

- [x] `SHOW DATABASES;` の結果が `.databases` のスコープ一覧（`all`, `arxiv_security_db`, `cti_catalog_db`, `graph_db`, `analytics_db`）と同等の内容を返す。
- [x] `ATTACH DATABASE` で動的に追加した DB も `SHOW DATABASES;` に反映される（既存動作の維持）。
- [x] フォールバックの `["default_db", "main"]` ダミー値が除去されている。
- [x] `make format`, `make static_analysis`, `make test` が全通過する。
- [x] `PRAGMA database_list;` との整合性も確認済み。
