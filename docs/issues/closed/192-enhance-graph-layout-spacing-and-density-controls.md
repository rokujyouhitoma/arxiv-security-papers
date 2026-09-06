---
ID: 192
種別: Feature / UIUX
優先度: Medium
ステータス: Closed
Created At: 2026-09-06T18:08:32+09:00
Closed At: 2026-09-06T18:14:00+09:00
---

# [FEAT/UIUX] グラフ可視化におけるノード密集の解消と間隔最適化（物理斥力・ばね長動的スケーリング・衝突回避・UI密度制御の実装） (ID: 192)

## 1. 概要 / Summary

Web ダッシュボード（`/dashboard tab=graph`）において、Vertex（ノード）同士の物理的距離が近すぎる（＝Edge のばね自然長が短く、斥力が弱い）ため、ノードやエッジが密集して関係性の把握やラベルの視認性が低下している。特に「📐 Schema View」では 16 種類のメタモデルクラスと 30 本以上のオブジェクトプロパティが集中するため、ノードが固まりやすい。

本改修では、物理シミュレーションパラメータ（ばね自然長 $L_\text{SPRING}$、クーロン斥力 $K_\text{REPULSION}$、中心引力 $K_\text{CENTER}$）のモード別動的最適化、ノード間最小分離距離を保証する衝突回避（Collision Detection）アルゴリズムの導入、およびユーザーが画面上で間隔を自由に調整できる「ノード間隔（Spacing）スライダー」を実装し、ゆったりと見やすいグラフレイアウトを実現する。

---

## 2. 密集解消のための多角的解決策 (Proposed Solutions)

1. **物理シミュレーションパラメータの動的スケーリング (距離の拡張)**:
   - 現状の固定値（$L_\text{SPRING} = 80.0$, $K_\text{REPULSION} = 2200.0$）から、モードとノード数に応じた動的スケーリングへ改修。
   - **Schema View**: $L_\text{SPRING} = 175.0$（従来の2倍以上）、$K_\text{REPULSION} = 9000.0$、$K_\text{CENTER} = 0.0025$ に拡張し、画面全体を広く使ったパノラマ配置を実現。
   - **CTI Graph**: ノード数 $N$ に応じて動的に $\text{springLength} = \max(90, \min(200, 1600 / \sqrt{N}))$ で伸縮。
2. **ノード衝突回避（Hard Collision Detection / Minimum Separation Force）**:
   - クーロン斥力に加え、ノード間距離が $r_u + r_v + 34\sim 48\text{px}$ 未満となった場合に強力な反発ベクトルを発生させ、ノードの重なり・密集を物理的に排除。
3. **UI 操作デッキへの「ノード間隔（Spacing）スライダー」追加**:
   - コントロールデッキ内に `SPACING: 0.6x 〜 2.2x` のレンジスライダーを設置。ユーザーがリアルタイムに好みの間隔へ伸縮可能にする。
4. **Schema View 初期配置（Circular Layout）の半径拡張**:
   - 初期展開時の円形半径を `Math.min(width, height) * 0.42` へ拡大し、最初から適度に開いた状態でシミュレーションを開始。
5. **ズーム・自動センタリング（Fit-to-Screen）のサポート**:
   - ノード間隔を広げても画面外に見切れないよう、全体バウンディングボックスに応じた自動フィット表示を最適化。

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [site/dashboard.html](../../site/dashboard.html) (物理シミュレーション変数、stepPhysics衝突回避、applySchemaGraph初期半径、コントロールデッキUIスライダー)
- [x] [tests/web/test_dashboard_html.py](../../tests/web/test_dashboard_html.py) (間隔設定・衝突回避ロジック・UIコントロールの回帰テスト)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/192-enhance-graph-layout-spacing-and-density-controls`

1. **物理パラメータのモード別分離**:
   - `getPhysicsParams()` を定義し、`currentGraphMode === 'schema'` の場合は広域パラメータ（$L=175, K_\text{rep}=9000, K_\text{center}=0.0025$）、CTI モードの場合は密度最適化パラメータを返却。
2. **ノード衝突回避ステップの実装**:
   - `stepPhysics()` 内で全ノードペアに対し最小距離（$r_u + r_v + \text{minSeparationBase} \times \text{spacingMultiplier}$）をチェックし、侵入時に幾何学的押し戻しを適用。
3. **コントロールデッキへの Spacing スライダー配置**:
   - デッキ内にノード間隔スライダー（ID: `spacingSlider`）を追加し、変更時に `L_SPRING` と `K_REPULSION` に乗数を適用して滑らかにシミュレーション。
4. **品質ゲート検証**:
   - `make build_js`, `pytest tests/web/test_dashboard_html.py`, `make check_format`, `make static_analysis` の全パスを確認。

---

## 5. 完了条件 / Success Criteria (DoD)
- [x] Schema View において、ノード間エッジ長が従来の約2倍（約175px）に広がり、ノード同士の過密が解消されること。
- [x] ノード同士が一定距離以下に近づかない衝突回避（Separation Force）が機能すること。
- [x] コントロールデッキにノード間隔スライダーが設置され、ユーザー操作によりリアルタイムにグラフが伸縮すること。
- [x] 単体テストおよび JavaScript コンパイル（Closure Compiler）が 100% PASS すること。
- [x] `make check_format` および `make static_analysis` がエラー0件で通過すること。
