---
ID: 356
種別: Refactor
優先度: High
ステータス: Open (New)
---

# [FEAT/ENH] 柱 1: `site/dashboard.html` インラインスクリプトの全廃と `site/app.js` のドメイン別ファイル分離 (ID: 356)

## 1. 概要 / Summary
現在 `site/dashboard.html` には約 3,000 行に及ぶインライン `<script>` が存在し、セキュリティ（Content Security Policy: CSP の `unsafe-inline` 解除困難）および保守性のボトルネックとなっている。
また、`site/app.js`（約 2,100 行）にも検索・トレンド・スパイダー・テレメトリ等の全ドメインロジックが 1 ファイルに集中している。
外部ライブラリ（npm, Webpack等）を一切導入せず、純粋な Pure Vanilla JS の責務分離原則に基づき、インラインスクリプトを外部 `.js` ファイルへ抽出し、`site/app.js` をドメイン別モジュールに分割する。

---

## 2. トレーサビリティ / Traceability
- 関連 Issue:
  - [348-extract-graph-canvas-engine-from-dashboard.md](closed/348-extract-graph-canvas-engine-from-dashboard.md)
  - [352-integrate-scene-director-and-router-tab-lifecycle.md](closed/352-integrate-scene-director-and-router-tab-lifecycle.md)
  - [355-refactor-namespace-from-yuzora-to-application.md](355-refactor-namespace-from-yuzora-to-application.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [site/dashboard.html](../site/dashboard.html) (インラインスクリプトの外部化)
- [ ] [site/js/dashboard/](../site/js/dashboard/) (新規ディレクトリ: ダッシュボード操作・描画ロジック)
- [ ] [site/app.js](../site/app.js) (ドメイン別モジュールへの分割)
- [ ] [site/js/console/](../site/js/console/) (新規ディレクトリ: 検索・トレンド・スパイダー・テレメトリ等)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `refactor/356-eliminate-inline-scripts-and-modularize`

1. **`dashboard.html` インラインスクリプトの抽出**:
   - `site/js/dashboard/` ディレクトリを新設。
   - 以下の責務ごとに外部 JS ファイルへ抽出:
     - `graph-data-service.js`: API 通信、キャッシュ、データフェッチ
     - `graph-interaction.js`: ノード選択、ホバー、ドロワー開閉、フィルタリング
     - `graph-export-ui.js`: STIX/TTL/JSON-LD エクスポート UI
     - `dashboard-main.js`: 初期化とエントリポイント
   - `dashboard.html` 内の `<script>` を `<script src="..." defer></script>` に換装。
2. **`site/app.js` のドメイン別分割**:
   - `site/js/console/` ディレクトリを新設。
   - 検索、トレンド、スパイダー監視、システムテレメトリ、モーダルビューアを独立ファイルに分離。
   - `app.js` は各モジュールのオーケストレーション（エントリポイント）として軽量化。
3. **CSP 強化 & ゼロ外部依存維持**:
   - 外部バンドラー不要で、ブラウザから直接読み込み可能な Pure JS 形式を維持。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] `site/dashboard.html` から巨大なインライン `<script>` が全廃され、外部スクリプト参照になっていること。
- [ ] `site/app.js` のロジックがドメイン別に分離され、単一ファイルの肥大化が解消されていること。
- [ ] 全 175 件の Web 統合テストが 100% PASS すること。
- [ ] Closure Compiler によるコンパイルがエラー 0 件であること。
