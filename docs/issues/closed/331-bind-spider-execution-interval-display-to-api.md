---
ID: 331
種別: Feature
優先度: Medium
ステータス: Closed (Completed)
---

# [FEAT/ENH] Webコンソールにおけるスパイダー実行間隔表示の API・設定値動的連動 (ID: 331)

## 1. 概要 / Summary
`site/index.html`（804, 821, 838行目）におけるスパイダー実行間隔表示（「6時間ごと」「24時間ごと」）が静的な HTML として決め打ちされており、バックエンド設定値（`src/workflow/service.py`）と連動していない。
`/api/spiders/status` のレスポンスに `interval_seconds` を含め、`site/app.js` 側で動的に描画するように改修することで、実行間隔変更時に UI とバックエンドロジックが自動的に一致するアーキテクチャを確立した。

---

## 2. トレーサビリティ / Traceability
- 関連仕様: `site/index.html`, `site/app.js`, `src/spider/daemon/storage.py`, `src/workflow/service.py`
- 要求元: スパイダー自律定期実行の UI 整合性と運用透明性確保

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [storage.py](../../src/spider/daemon/storage.py): `DEFAULT_INTERVALS` 定義および `_build_spider_status` への `interval_seconds` 追加
- [x] [index.html](../../site/index.html): 実行間隔要素への `id="valSpiderInterval_<name>"` 付与
- [x] [app.js](../../site/app.js): `loadSpiderStatus()` における `interval_seconds` のフォーマットと動的描画
- [x] [test_enterprise_console_ui.py](../../tests/web/test_enterprise_console_ui.py): スパイダー実行間隔要素 ID の検証テスト追加
- [x] [test_spider_db_persistence.py](../../tests/spider/test_spider_db_persistence.py): `interval_seconds` アサーション追加

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/331-bind-spider-execution-interval-display-to-api`

1. **バックエンド API 拡張 (`src/spider/daemon/storage.py`)**:
   - `SpiderExecutionStorage.DEFAULT_INTERVALS`（`arxiv: 21600.0`, `cwe: 86400.0`, `kev_cve/cisa_kev: 21600.0`）を定義。
   - `_build_spider_status()` の戻り値 dict に `"interval_seconds": float` を含める。
2. **フロントエンド HTML マークアップ (`site/index.html`)**:
   - 各スパイダーカードの実行間隔 strong タグに `id="valSpiderInterval_arxiv"`, `id="valSpiderInterval_cwe"`, `id="valSpiderInterval_kev_cve"` を付与。
3. **フロントエンド JS 動的反映 (`site/app.js`)**:
   - `loadSpiderStatus()` 内で `info.interval_seconds` をチェックし、時間/日表記に変換して `valSpiderInterval_<key>` の textContent を更新。
4. **テスト追加 (`tests/web/test_enterprise_console_ui.py`, `tests/spider/test_spider_db_persistence.py`)**:
   - 各スパイダーの実行間隔要素 ID が HTML 内に存在することをアサートするテストを追加。

---

## 5. 完了条件 / Success Criteria (DoD)
- [x] `/api/spiders/status` の JSON レスポンスに `interval_seconds` が含まれること。
- [x] `site/index.html` 上の実行間隔テキスト要素に一意の ID が付与されていること。
- [x] `site/app.js` が API レスポンスの値に基づいて実行間隔を動的に描画すること。
- [x] UI および API の単体テストが 100% PASS すること。
- [x] 全品質ゲート（`make check_format`、`make static_analysis`、`pytest`）が 100% PASS すること。
