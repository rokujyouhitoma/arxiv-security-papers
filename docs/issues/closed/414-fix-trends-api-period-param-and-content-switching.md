---
ID: 414
種別: Bug
優先度: High
ステータス: Closed
完了日: 2026-10-03
---

# [BUG] Webコンソール /api/trends における period パラメータ未反映およびサマリー切り替え不全の解消 (ID: 414)

## 1. 概要 / Summary
Web コンソール「階層別エグゼクティブサマリー & トレンド分析 (`http://localhost:8000/?tab=trends#/trends`)」において、「一か月分 (03_monthly)」「四半期 (04_quarterly)」「通期総括 (05_annual)」の各ボタンをクリックしても、常に同じ月次サマリーのコンテンツが表示されてしまう不具合が発生していた。

### 再現手順 / Steps to Reproduce
1. Web サーバーを起動 (`make run_web`)
2. ブラウザで `http://localhost:8000/?tab=trends#/trends` を開く
3. 「四半期 (04_quarterly)」または「通期総括 (05_annual)」ボタンをクリックする
4. 表示されるタイトルが常に「月次エグゼクティブサマリー (03_monthly)」のままとなり、四半期・通期のサマリーが表示されない

### 再現環境 / Environment
- OS: Linux
- Components: `src/web/gateway/handlers.py`, `src/mcp/papers_server.py`, `site/app.js`

---

## 2. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [src/web/gateway/handlers.py](../../src/web/gateway/handlers.py): `/api/trends` ハンドラーにおける `period` パラメータ抽出と `full_content=True` 伝搬
- [x] [src/mcp/papers_server.py](../../src/mcp/papers_server.py): `_get_trend_summary_files` での全階層 (`per_run`, `daily`, `monthly`, `quarterly`, `annual`) マッピング対応
- [x] [site/app.js](../../site/app.js): `period-btn` クリック時の `fetchTrends(activePeriod)` 呼び出しと URL パラメータ連携
- [x] [tests/web/test_web_server.py](../../tests/web/test_web_server.py): 期間別サマリー取得の検証テスト

---

## 3. 根本原因分析 (RCA) / Root Cause Analysis
1. `src/web/gateway/handlers.py` の `handle_trends` メソッドにおいて、リクエストクエリパラメータ `query_params` から `period`（`monthly`, `quarterly`, `annual` 等）を取得しておらず、常に `handle_get_latest_trends({"limit": limit})` のみを呼び出していた。
2. `handle_get_latest_trends` 内部では `period = args.get("period", "monthly")` とフォールバックされるため、フロントエンドでどの期間ボタンを押しても、常に `03_monthly` の最新ファイル（`monthly_*.md`）が返されていた。
3. さらに、`handle_get_latest_trends` は `full_content: True` が指定されない場合、デフォルトで `max_chars=4000` でコンテンツを切り詰めて返却していたため、Webコンソールでの一覧表示が途中で途切れる要因となっていた。

---

## 4. 暫定対処と恒久対策 / Workaround & Permanent Fix
* **暫定対処 (Workaround)**: なし
* **恒久対策 (Permanent Fix)**: 
  - `src/web/gateway/handlers.py` の `handle_trends` で `period = query_params.get("period", ["monthly"])[0]` を抽出し、ホワイトリスト判定（`per_run`, `daily`, `monthly`, `quarterly`, `annual`）を行った上で、`full_content=True` を付与して `handle_get_latest_trends({"period": period, "full_content": True, "limit": limit})` に渡す。
  - `src/mcp/papers_server.py` の `_get_trend_summary_files` に全 5 階層のディレクトリマッピング（`01_per_run`, `02_daily`, `03_monthly`, `04_quarterly`, `05_annual`）を追加し、将来の拡張にも備える。

---

## 5. 実装方針 / Implementation Plan
Target Branch: `fix/414-trends-period-param`

1. **`src/web/gateway/handlers.py`**:
   - `handle_trends` で `period` をクエリパラメータから抽出し、安全なホワイトリストチェックを実施。
   - `handle_get_latest_trends` への呼び出し引数に `period` および `full_content: True` を指定。
2. **`src/mcp/papers_server.py`**:
   - `period_prefix_map` に `"per_run": "01_per_run"`, `"daily": "02_daily"` を追加。
3. **テスト検証**:
   - `tests/web/test_web_server.py` に `period=monthly`, `period=quarterly`, `period=annual` の差分レスポンス検証テストを追加。

---

## 6. 完了条件 / Success Criteria (DoD)
- [x] `/api/trends?period=monthly` で `monthly_*.md` の内容が返ること
- [x] `/api/trends?period=quarterly` で `quarterly_*.md` の内容が返ること
- [x] `/api/trends?period=annual` で `annual_*.md` の内容が返ること
- [x] `full_content=True` により 4,000 文字制限で切り詰められず、サマリー全文が返却されること
- [x] `make test` および `make static_analysis` が PASS すること
