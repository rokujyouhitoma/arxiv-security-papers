---
ID: 393
種別: Bug
優先度: High
ステータス: Closed
---

# [BUG/SEC] スパイダー手動トリガーのUI即時フィードバック実装および実行ログ台帳カラム整合性の修正 (ID: 393)

## 1. 概要 / Summary
Webコンソールの「🕷️ スパイダー自律実行 & 定期クローラー監視」画面において、「⚡ 今すぐ実行 (Manual Trigger)」ボタンを押下しても、画面上の見た目やステータスが一切変化せず、ユーザーから見て「実行されない」ように見える不具合が発生していた。

調査の結果、バックエンドでは非同期スレッドにより正常にスパイダー（`arxiv`, `cwe`, `kev_cve`）が起動・実行・完了していたものの、以下の重大な問題が存在することが判明した：
1. **UIフィードバックの欠如**: ボタン押下時にボタン自体のローディング表示（disabled化・テキスト変更）やトースト通知、ステータスバッジの即時更新が行われないため、操作が無視されたように感じられる。
2. **実行ログ台帳 (`spider_execution_logs`) のカラム整合性不整合**: `SpiderExecutionStorage` の SQL 文で一部カラムのみを指定した結果、自作 Pure-Python DB (PyDB) のテーブル定義（10カラム）との間でカラムのインデックスマッピングにズレが生じ、`status` が `null` になったりカラム値が入れ替わってステータスバッジが正しく遷移しない。
3. **PyDB の UPDATE 実行時におけるプレースホルダーバインド不整合**: `src/database/sql/executor.py` の `_compute_update_assignments` において、`stmt.raw_assignments` が存在する場合に `_bind_assignments` された具体値を無視して `_extract_field_value(eval_ctx, "?")` が実行され、値が全て `None` に上書きされる不具合が存在した。

### 再現手順 / Steps to Reproduce
1. Webコンソール (`site/index.html` または `http://localhost:8000/`) を開く。
2. 「🕷️ スパイダー自律実行 & 定期クローラー監視」タブ（または該当セクション）へ移動する。
3. 「📄 arXiv Security Spider」の「⚡ 今すぐ実行 (Manual Trigger)」をクリックする。
4. ボタンの見た目やカードのステータスバッジが `IDLE` のまま変化せず、リクエストが受理されたかどうかのフィードバック（トーストやスピナー）が表示されない。

### 再現環境 / Environment
- ブラウザ / Web Console (`site/index.html`, `site/app.js`)
- Web Gateway API (`src/web/gateway/handlers.py`)
- Spider Daemon Storage (`src/spider/daemon/storage.py`)
- データベース: 自作 Pure-Python Vector DB (`outputs/database/spider_execution.vdb`, `src/database/sql/executor.py`)

---

## 2. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [site/app.js](file:///workspace/arxiv-security-papers/site/app.js): `triggerSpider()` でのボタンローディング状態制御、トースト通知、カードステータスの即時更新
- [x] [site/app-min.js](file:///workspace/arxiv-security-papers/site/app-min.js): Closure Compiler によるバンドルコンパイル
- [x] [src/spider/daemon/storage.py](file:///workspace/arxiv-security-papers/src/spider/daemon/storage.py): `record_start` / `record_finish` における全カラム明示形式への統一と PyDB レコード整合性修正
- [x] [src/database/sql/executor.py](file:///workspace/arxiv-security-papers/src/database/sql/executor.py): UPDATE 実行時のプレースホルダーバインド値優先適用の修正
- [x] [tests/spider/test_spider_db_persistence.py](file:///workspace/arxiv-security-papers/tests/spider/test_spider_db_persistence.py): カラム整合性およびステータス永続化の単体テスト

---

## 3. 根本原因分析 (RCA) / Root Cause Analysis
1. **フロントエンドのイベントハンドラにおけるリアクティブ制御の欠如**:
   - `triggerSpider(spiderName)` では、`appApiClient.post('/api/spiders/trigger', ...)` を呼び出しているが、クリックされたボタン要素の参照を保持しておらず、ボタンの属性変更（`disabled = true`, `textContent = '⏳ 実行中...'`）やトースト通知が実装されていなかった。
2. **PyDB の DML 実行におけるカラム部分指定時のマッピング不整合**:
   - `storage.py` の `record_start` では `REPLACE INTO spider_execution_logs (job_id, spider_name, status, started_at, params) VALUES (?, ?, 'RUNNING', ?, ?)` と5カラムのみ指定していたが、テーブルには10カラム存在するため、PyDB の低レイヤー実行エンジンが未指定カラムに NULL を詰める際のオフセットやインデックス位置がずれてしまい、クエリ結果の `status` が `null` となってフロントエンドのバッジ更新（`RUNNING`）が阻害されていた。
3. **PyDB の UpdateStatement における raw_assignments 評価バグ**:
   - `src/database/sql/executor.py` の `_compute_update_assignments` で、`raw_assignments` に入っている式 `?` を直接レコードからルックアップしようとして `None` が返され、`UPDATE` 文でバインドされた正常値が `None` で上書きされていた。

---

## 4. 恒久対策 / Permanent Fix
1. `SpiderExecutionStorage` の SQL 文をテーブル定義に適合する全カラム明示形式（`ALL_COLUMNS_SQL`）に改修し、PyDB 上で各カラムが正確なインデックスに格納されるようにした。
2. `src/database/sql/executor.py` の `_compute_update_assignments` において、`expr == "?"` かつ `col in stmt.assignments` の場合はバインド値 `stmt.assignments[col]` を最優先で適用するよう修正した。
3. `site/app.js` の `triggerSpider` にクリックしたボタンの無効化・スピナーアニメーション・トースト通知・即時 `RUNNING` バッジ更新を実装し、Closure Compiler 適合の JSDoc アノテーションに準拠させて `site/app-min.js` を再生成した。

---

## 5. 完了条件 / Success Criteria (DoD)
- [x] `SpiderExecutionStorage` で登録されたレコードの `status` が `RUNNING` および `SUCCESS` / `FAILED` として正しく取得できること。
- [x] 「⚡ 今すぐ実行 (Manual Trigger)」ボタンを押下した際、ボタンがローディング表示になり、トースト通知が表示され、バッジが即座に `RUNNING` に切り替わること。
- [x] 手動トリガー後に `/api/spiders/status` および `/api/spiders/history` に正しいデータが反映されること。
- [x] `make format`, `make static_analysis`, `make test` がエラー0件で全てパスすること。
