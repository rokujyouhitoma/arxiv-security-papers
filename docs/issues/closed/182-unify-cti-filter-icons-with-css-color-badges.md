---
ID: 182
種別: Feature
優先度: Medium
ステータス: Closed
---

# [FEAT/UIUX] コントロールデッキ CTI フィルタボタングループにおける丸絵文字の排除および凡例準拠 CSS カラーバッジへの統一 (ID: 182)

## 1. 概要 / Summary
`dashboard.html` のコントロールデッキ（`.graph-control-deck`）内にある CTI フィルタボタングループ（`#ctiFilters`）において、ボタンラベルに付与されている OS 依存の丸絵文字（`🔵 Papers`, `🔴 ATT&CK`, `🟠 CWE`, `🟡 Precondition`, `🟢 Rule`, `🔷 PoC`, `🟣 Gap`）を排除し、凡例（`#ctiLegend` / `#contextLegend`）で確立したデザインシステムに準拠して、Canvas 実描画色と 100% 一致する CSS 円形カラーバッジ（`.filter-dot`）へと統一する。

これにより、OS やブラウザごとの絵文字フォントレンダリング差（発色・形状・ズレ）を完全解消し、エンタープライズ UI/UX として一貫した洗練されたビジュアルを提供する。

---

## 2. トレーサビリティ / Traceability
- **関連設計書**: [docs/designs/DSN-21-enterprise_design_system_and_unified_console.md](file:///workspace/arxiv-security-papers/docs/designs/DSN-21-enterprise_design_system_and_unified_console.md) (第4章 ナレッジグラフワークスペース設計, 第5章 メインコンテンツ標準コンポーネント)
- **関連 Issue**: 
  - Issue #181: CTI 凡例の単一 CSS カラーバッジ統一およびアスペクト比同期
  - Issue #140: ノード半径・色設計仕様

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [site/dashboard.html](file:///workspace/arxiv-security-papers/site/dashboard.html) (`#ctiFilters` ボタングループのマークアップおよび `.filter-dot` スタイル追加)
- [x] [tests/web/test_dashboard_cti_graph.py](file:///workspace/arxiv-security-papers/tests/web/test_dashboard_cti_graph.py) (フィルターボタンスタイルおよびマークアップ検証)
- [x] [docs/issues/README.md](file:///workspace/arxiv-security-papers/docs/issues/README.md) (Issue 台帳登録)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/182-unify-cti-filter-icons-with-css-color-badges`

1. **CSS スタイル `.filter-dot` の定義**:
   - `site/dashboard.html` 内のツールバーボタンスタイル部に `.filter-dot` を追加。
   ```css
   .filter-dot {
     display: inline-block;
     width: 8px;
     height: 8px;
     border-radius: 50%;
     border: 1px solid rgba(0, 0, 0, 0.25);
     margin-right: 5px;
     vertical-align: -0.5px;
     flex-shrink: 0;
   }
   .btn-tool.active .filter-dot {
     border-color: rgba(255, 255, 255, 0.7);
     box-shadow: 0 0 2px rgba(255, 255, 255, 0.5);
   }
   ```
2. **ボタンマークアップの絵文字置換**:
   - `#filterPaper`: `<span class="filter-dot" style="background-color: #3B82F6;"></span>Papers`
   - `#filterAttack`: `<span class="filter-dot" style="background-color: #EF4444;"></span>ATT&CK`
   - `#filterCwe`: `<span class="filter-dot" style="background-color: #F59E0B;"></span>CWE`
   - `#filterPrecondition`: `<span class="filter-dot" style="background-color: #EAB308;"></span>Precondition`
   - `#filterRule`: `<span class="filter-dot" style="background-color: #10B981;"></span>Rule`
   - `#filterPoc`: `<span class="filter-dot" style="background-color: #06B6D4;"></span>PoC`
   - `#filterGap`: `<span class="filter-dot" style="background-color: #8B5CF6;"></span>Gap`
3. **ボタンアクティブ時の視認性維持**:
   - ボタンが反転色（黒背景 `var(--border-dark)`、白文字）になった場合でも、`.filter-dot` の枠線と発色が美しく際立つよう調整。

---

## 5. 完了条件 / Success Criteria (DoD)
- [x] コントロールデッキの CTI フィルターボタン群から丸絵文字が排除され、Canvas 実色と合致する CSS カラーバッジが表示されること。
- [x] ボタンの通常時・ホバー時・アクティブ時においてカラーバッジが崩れず明瞭に視認できること。
- [x] 各フィルタークリック時のノード絞り込み機能（`setCtiFilter`）が正常に動作すること。
- [x] `make check_format` および `make static_analysis` がエラー 0 件で PASS すること。
