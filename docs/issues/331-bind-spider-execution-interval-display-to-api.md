---
ID: 331
種別: Feature
優先度: Medium
ステータス: Open (New)
---

# [FEAT/ENH] Webコンソールにおけるスパイダー実行間隔表示の API・設定値動的連動 (ID: 331)

## 1. 概要 / Summary
`site/index.html`（818, 835, 852行目）におけるスパイダー実行間隔表示（「6時間ごと」「24時間ごと」）が静的な HTML として決め打ちされており、`src/workflow/service.py`（33-53行目）の実装値と連動していない。
`/api/spiders/status` のレスポンスに `interval_seconds` を含め、`site/app.js` 側で動的に描画するように改修することで、実行間隔変更時に UI とバックエンドロジックが自動的に一致するアーキテクチャを確立する。

---

## 2. トレーサビリティ / Traceability
- 関連仕様: `site/index.html`, `site/app.js`, `src/spider/daemon/storage.py`, `src/workflow/service.py`
- 要求元: スパイダー自律定期実行の UI 整合性と運用透明性確保

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [index.html](../../site/index.html)
- [ ] [app.js](../../site/app.js)
- [ ] [storage.py](../../src/spider/daemon/storage.py)
- [ ] [handlers.py](../../src/web/gateway/handlers.py)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/331-bind-spider-execution-interval-display-to-api`

1. `/api/spiders/status` エンドポイント（`SpiderExecutionStorage._build_spider_status` または `handlers.py`）の各スパイダー情報に `interval_seconds` フィールドを追加。
2. `site/index.html` の静的な「6時間ごと」等のハードコード表示をプレースホルダー化。
3. `site/app.js` の `renderSpiderStatus()` にて `interval_seconds` から人間可読な文字列表記（例: 21600s → "6時間ごと"、86400s → "24時間ごと"）を生成し、DOM へ動的反映。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] `/api/spiders/status` の JSON レスポンスに `interval_seconds` が含まれること。
- [ ] `site/index.html` 上の実行間隔テキストが API レスポンスの値に基づいて動的に描画されること。
- [ ] 間隔設定変更時に UI 表示が自動的に追従すること。
- [ ] UI および API の単体テストが 100% PASS すること。
