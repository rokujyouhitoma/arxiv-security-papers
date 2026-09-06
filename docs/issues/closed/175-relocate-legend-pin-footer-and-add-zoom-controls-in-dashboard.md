---
ID: 175
種別: Feature
優先度: High
ステータス: Closed (Completed)
---

# [FEAT/ENH] dashboard.html における CTI 凡例の左上再配置、スクロール不要なフッター常時表示化、およびキャンバスズーム倍率表示・コントロールボタン (+/-) の実装 (ID: 175)

## 1. 概要 / Summary

本 Issue は、`/dashboard.html`（Knowledge & CTI Graph 専用画面）における操作性と可視性を大幅に向上させるため、UI/UX & Documentation Designer エージェントが主導し、Systems Architect (SA)、IT Strategist (ST)、Project Manager (PM) との緊密な多角連携のもとで実施する UI/UX・レイアウト刷新タスクである。

ユーザーからのフィードバックおよび要件定義に基づき、以下の 4 点の機能改善・UI 再配置を実施する：

1. **「CTI Entity & Relation」凡例（Cluster Legend）の左上再配置**:
   - 現在 Canvas の左下（`bottom: 12px; left: 12px;`）に表示されている「Cluster Classification / CTI Entity & Relation」凡例パネル（`#contextLegend`）を、**Canvas の左上（Top-Left）**へ移動・再配置する。
   - 上部コントロールデッキの表示/非表示（Issue 174 で実装された折りたたみ機能）やフローティングボタンとの重なり・干渉を完全に防ぎ、視認性を維持した美しい絶対配置・グラスモルフィズムスタイルを実現する。

2. **フッターの常時表示化（スクロール不要で画面最下部に固定・常時可視化）**:
   - 現在、グローバルフッター（`<footer class="console-footer">`）はページ縦スクロールの最下端に配置されており、画面縦幅が狭い場合やノート PC 等では縦スクロールしないと表示されない。
   - レイアウト構造（`display: flex; flex-direction: column; height: 100vh; overflow: hidden;`）を精緻化し、上部ヘッダー（48px）、中央 Canvas ワークスペース（可変伸縮 flex: 1）、および下部フッター（36px）をブラウザの Viewport 内に 100% 収める。
   - これにより、**スクロール不要でフッターのシステムステータス・同期情報が常時画面最下部に表示される**状態を実現する。

3. **Canvas ズーム倍率表示（%）およびズームコントロール（＋/ー/リセット）ボタンの新設**:
   - 現在、マウスホイールによって Canvas の拡大・縮小（ズームイン/ズームアウト: 0.25x 〜 4.0x）が可能であるが、現在の倍率が何パーセントなのか視覚的に把握できない。
   - 通常初期状態（`scale = 1.0`）を **100%** として、現在のズーム倍率をリアルタイムにバッジ表示（例: `100%`, `125%`, `75%`）するズームインジケーターを新設する。
   - さらに、マウスホイール操作だけでなく、直感的にクリック操作可能な **`+` (Zoom In: +15%)**、**`-` (Zoom Out: -15%)**、および **`⟲` (Zoom Reset: 100% & 視点リセット)** コントロールボタン群を Canvas 上のコントロールオーバーレイとして設置する。
   - キーボードショートカット（`+`/`=` で拡大、`-` で縮小、`0` で 100% リセット）にも対応し、アクセシビリティを強化する。

4. **フッターおよび CTI Entity & Relation 要素へのチップヒント（ツールチップ）完全実装**:
   - 画面最下部のフッター内要素（ISO/OKF 準拠バッジ、最終同期時刻、Reset Physics ボタン、Inject Node ボタン、Back to Console リンク）に、それぞれの役割や状態を明解に説明するグラスモルフィック・チップヒント（`data-tooltip`, `data-tooltip-pos="top"`）を付与する。
   - 「CTI Entity & Relation」および「Cluster Classification」凡例パネル内の全アイテム（`:Paper`, `:AttackTechnique`, `:CWE`, `:DefenseMechanism`, 各関係性エッジ `EXPLOITS`, `MITIGATES` 等、折りたたみボタン）にチップヒント（`data-tooltip`, `data-tooltip-pos="right"`）を付与する。
   - CSS に `[data-tooltip-pos="right"]` スタイル（右側展開用矢印・吹き出し位置）を追加し、凡例が左上へ配置された場合でも画面端で見切れず美しく吹き出しが表示されるようにする。

---

## 2. トレーサビリティ / Traceability

- **起因 Issue**: 
  - [174-enable-canvas-scrolling-and-fix-clipping-in-dashboard.md](closed/174-enable-canvas-scrolling-and-fix-clipping-in-dashboard.md) (Canvas スクロール、コントロールデッキ表示切替)
  - [166-implement-glassmorphic-tooltips-and-graph-uiux-guide.md](closed/166-implement-glassmorphic-tooltips-and-graph-uiux-guide.md) (操作ガイド、UI/UX 認知負荷軽減)
  - [170-unify-dashboard-header-with-index-and-retain-graph-only.md](closed/170-unify-dashboard-header-with-index-and-retain-graph-only.md) (ヘッダー統一・Graph 専用画面化)
- **関連規約・標準**:
  - `AGENTS.md` (UI/UX & Documentation Designer, SA, ST, PM 多角合意原則)
  - Pure-Python & Vanilla JS 原則（外部 CDN・重厚フレームワーク依存ゼロ）
  - W3C Web Content Accessibility Guidelines (WCAG) 2.1 (ズーム操作のキーボード・UI コントロール提供)

---

## 3. 多角エージェント連携審議 (SA / ST / UIUX / PM)

| エージェント | 視点・検証内容 | 合意事項 |
| :--- | :--- | :--- |
| **UI/UX & Documentation Designer (主導)** | 凡例の左上配置における視線誘導（Z-pattern / F-pattern）、ズームコントローラーのグラスモルフィズム配置、および直感的な 100% 倍率バッジ設計。 | 凡例を左上（`top: 12px; left: 12px;`）に移動。ズームコントローラーは Canvas の右下または右上に配置し、凡例やノードコールアウトカード（右側ドッキング）とのレイアウト衝突を回避。 |
| **Systems Architect (SA)** | Viewport 全体（100vh）の CSS Flexbox / Grid 収束、Canvas リサイズイベント（`ResizeObserver` / `resizeCanvas()`）の整合性、およびフッター固定時の Canvas 再描画パフォーマンス。 | `html, body { height: 100vh; overflow: hidden; }` を適用し、`body` を `flex-direction: column` で構成。ワークスペースを `flex: 1`、Canvas コンテナを `flex: 1; min-height: 0;` とすることで、スクロールなしでフッターが常時最下部に美しくフィット。 |
| **IT Strategist (ST)** | 経営・分析オペレーターが大型モニターやラップトップで操作する際の CTI インテリジェンス可読性およびズーム倍率の明確化によるプレゼンテーション性向上。 | 100% を基準としたリアルタイム % 表示により、分析画面のスクリーンショット共有時やブリーフィング時の再現性が向上。 |
| **Project Manager (PM)** | 既存機能（デッキ折りたたみ `D`、ヘッダー折りたたみ `H`、ドラッグパン、クエリコンソール）への後退（回帰）ゼロ保証、および品質ゲート通過。 | 既存テストスイートおよび新規 UI 要素・キーボードショートカットのテストを網羅し、Triple Quality Gate（Format, Static Analysis, Tests）の 100% 達成をマイルストーンとする。 |

---

## 4. 影響範囲と関連ファイル / Scope and Affected Files

- [x] [site/dashboard.html](site/dashboard.html)
  - `.cluster-legend`（`#contextLegend` / `#ctiLegend`）の CSS 配置を `bottom: 14px` から `top: 14px; left: 14px;` に変更。
  - `html, body` および `.graph-workspace`, `.canvas-container` の高さを 100vh Flexbox に最適化し、フッター（`footer`）を画面最下部にスクロール不要で常時固定表示。
  - `[data-tooltip-pos="right"]` の CSS 定義（矢印・吹き出しスタイリング）を追加。
  - CTI 凡例および Context Mesh 凡例の各アイテム（`:Paper`, `:AttackTechnique`, `:CWE`, `:DefenseMechanism`, 各リレーションエッジ）への `data-tooltip` チップヒント付与。
  - フッター内要素（規格準拠バッジ、同期時刻、Reset Physics ボタン、Inject Node ボタン、Back to Console リンク）への `data-tooltip` チップヒント付与。
  - Canvas ズームインジケーター（`#zoomLevelBadge`）およびコントロールボタン群（`btnZoomIn`, `btnZoomOut`, `btnZoomReset`）の HTML/CSS 追加。
  - JS ズームコントロール関数（`zoomCanvasBy()`, `resetZoom()`, `updateZoomBadge()`）の実装。
  - マウスホイールイベント時のリアルタイム % 表示連動、およびキーボードショートカット（`+`, `-`, `0`）のハンドラー追加。
  - ヘルプガイドドロワーへの操作キー（`+ / -: ズームイン / アウト`, `0: 100% 等倍リセット`）の追記。
- [x] [tests/web/test_dashboard_graph_tab.py](tests/web/test_dashboard_graph_tab.py)
  - 凡例の左上配置スタイル、フッターの常時表示レイアウト、ズームインジケーターおよびズームボタンの存在・動作検証テストの追加。
  - フッターおよび CTI 凡例要素へのチップヒント（`data-tooltip`）および `[data-tooltip-pos="right"]` スタイルの検証テスト追加。
- [x] [tests/web/test_dashboard_html.py](tests/web/test_dashboard_html.py)
  - HTML 構造・レイアウト回帰テスト。
- [x] [docs/issues/README.md](docs/issues/README.md)
  - Issue 175 の台帳登録。

---

## 5. 実装方針 / Implementation Plan

Target Branch: `feat/175-relocate-legend-pin-footer-and-add-zoom-controls-in-dashboard`

1. **凡例パネル（`.cluster-legend`）の左上再配置 & チップヒント付与**:
   - `site/dashboard.html` 内の `.cluster-legend` の CSS を修正：
     ```css
     .cluster-legend {
       position: absolute;
       top: 14px;
       left: 14px;
       bottom: auto; /* 左下指定の解除 */
       overflow: visible;
       ...
     }
     ```
   - CSS に `[data-tooltip-pos="right"]`（`::before`, `::after`）を追加。
   - `#ctiLegend` および `#contextLegend` の全アイテム、トグルボタンに `data-tooltip` と `data-tooltip-pos="right"` を設定。

2. **フッターの常時表示化（スクロール不要 Viewport レイアウト）& チップヒント付与**:
   - `html, body` の高さを `height: 100vh; overflow: hidden;` に設定。
   - `header.console-header`: 固定高 48px（折りたたみ時は 0px）。
   - `.graph-workspace`: `flex: 1; display: flex; flex-direction: column; min-height: 0; overflow: hidden;`。
   - `.canvas-container`: `flex: 1; position: relative; min-height: 0; overflow: hidden;`。
   - `footer`: `flex-shrink: 0; height: 36px; overflow: visible;`（画面最下部にスクロールなしで常時固定描画）。
   - フッター内の各ボタン・リンク・情報バッジに `data-tooltip` と `data-tooltip-pos="top"` を付与。
   - `resizeCanvas()` がウィンドウリサイズやヘッダー/デッキ折りたたみ時にコンテナの正確な高さを検知して Canvas をリサイズ。

3. **ズームインジケーター & コントロールボタン群の実装**:
   - Canvas オーバーレイとしてズームコントロールパネル（`.canvas-zoom-controls`）を右下（`bottom: 14px; right: 14px;`）に新設：
     - `[ - ]` ボタン (`id="btnZoomOut"`, `data-tooltip="グラフを縮小 (Shortcut: -)"`)
     - ズーム倍率バッジ (`id="zoomLevelBadge"`, テキスト: `100%`, `data-tooltip="クリックで100%にリセット (Shortcut: 0)"`)
     - `[ + ]` ボタン (`id="btnZoomIn"`, `data-tooltip="グラフを拡大 (Shortcut: +)"`)
     - `[ ⟲ ]` リセットボタン (`id="btnZoomReset"`, `data-tooltip="ズーム倍率と視点を100%初期位置にリセット (Shortcut: 0)"`)
   - JS 状態更新ロジック：`updateZoomBadge()`, `zoomCanvasBy(factor)`, `resetZoom()`。
   - マウスホイールイベント内でも `updateZoomBadge()` を呼び出し、リアルタイム同期。
   - キーボードショートカット（`+`, `-`, `=`, `0`）対応。

4. **テスト作成 & 品質検証**:
   - `tests/web/test_dashboard_graph_tab.py` に検証テストを追加。
   - `make check_format`, `make static_analysis`, `make test` の Triple Quality Gate を実行し、全件 PASS を確認。

---

## 6. 完了条件 / Success Criteria (DoD)

- [x] 「CTI Entity & Relation」凡例パネルが Canvas の左上（Top-Left）に正しく配置され、表示/非表示（最小化）トグルが正常に機能すること
- [x] フッター（`footer`）が画面最下部にスクロール不要で常時表示され、ブラウザの縦スクロールバーを操作しなくても常時可視・固定されていること
- [x] CTI 凡例および Context Mesh 凡例の各ノード種別・エッジ関係性にホバーした際、適切な解説チップヒント（ツールチップ）が表示されること
- [x] フッターの各ボタン（Reset Physics, Inject Node）、リンク（Back to Console）、および同期ステータスにホバーした際、チップヒントが表示されること
- [x] Canvas 上に現在のズーム倍率が「100%」等のパーセント表記でリアルタイムに表示されること
- [x] ズーム操作用コントロールボタン（`+` 拡大、`-` 縮小、`⟲` リセット）が機能し、クリックでズームイン・ズームアウト・等倍復帰できること
- [x] マウスホイールによるズーム時にもズーム倍率バッジがリアルタイムに更新されること
- [x] キーボードショートカット（`+` / `-` / `0`）でズーム操作およびリセットができること
- [x] ヘッダー折りたたみ（`H`）、デッキ折りたたみ（`D`）操作時でもレイアウトやズーム倍率、フッター位置が崩れないこと
- [x] 単体・結合テストスイートおよび品質ゲート（`make check_format`, `make static_analysis`, `make test`）が 100% PASS すること

