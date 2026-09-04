---
ID: 140
種別: Feature
優先度: Medium
ステータス: Closed
---

# [FEAT/ENH] /dashboard tab=graph におけるエッジ接続数に応じたノード半径（Vertex Size）の面積比例スケーリング（R ∝ √(1+k)）の実装 (ID: 140)

## 1. 概要 / Summary
`http://localhost:8000/dashboard.html?tab=graph`（Knowledge & CTI Graph Dedicated Screen）において、各ノード（Vertex）の半径は現在クラスタ種別（`source: 14px`, `entity: 11px`, `CTI: 8px` 等）に基づく固定値として描画されている。
そのため、多数のエッジが集約する重要ハブノード（コア論文、主要な MITRE ATT&CK 手法、頻出 CWE 脆弱性）と、接続が少ない末端ノード（葉ノードや孤立ノード）の視覚的差異がつきにくく、ナレッジグラフのトポロジー構造や重要エンティティを直感的に把握することが難しかった。

本 Issue では、ユーザー提案の「エッジ数に応じた幾何スケーリング」のアイデアに基づき、情報可視化・グラフ理論におけるベストプラクティスである **面積比例スケーリングモデル（Area $\propto$ Degree、すなわち $R(k) = R_0 \cdot \sqrt{1 + k}$）** を採用・実装する。
これにより、接続エッジ数（次数 degree $k$）が増えるにつれてノードの面積が線形に拡大し、ハブノードが自然かつ美しく際立つエルゴノミックなグラフ可視化を実現する。

---

## 2. 数理モデル & UI/UX 設計 (Mathematical Model & UI/UX Design)

### 2.1 面積比例スケーリング式（Area-Proportional Scaling）
ノード $i$ の無向エッジ接続次数を $k_i = \text{deg}(v_i)$（自己ループ除外、インシデントエッジのユニーク数）としたとき、描画半径 $R(k_i)$ を以下の通り定義する：

$$R(k_i) = \min\left(R_{\max}, \max\left(R_{\min}, R_0 \cdot \sqrt{1 + k_i}\right)\right)$$

- **パラメータ設定**:
  - 基準半径 $R_0 = 5.5\text{px}$ （`source` クラスタの場合は起点強調のため $R_0 = 7.0\text{px}$）
  - 最小保証半径 $R_{\min} = 5.5\text{px}$（Retina/高解像度ディスプレイにおける視認性・クリック性の下限保証）
  - 最大上限半径 $R_{\max} = 28.0\text{px}$（巨大ハブによる画面占有・他ノード押し出しの防止）

### 2.2 次数ごとの半径・面積比較表

| 接続エッジ数 $k$ | ノード種別例 | 計算半径 $R(k)$ ($R_0=5.5$) | 相対面積比 ($A/A_0$) | 視覚効果 |
| :---: | :--- | :---: | :---: | :--- |
| **0** | 孤立ノード（未接続論文・エンティティ） | **5.5 px** | $1.0\times$ | 邪魔にならず軽快に描画 |
| **1** | 末端ノード（1つの親のみと接続） | **7.8 px** ($\approx 5.5\sqrt{2}$) | $2.0\times$ | ユーザー提案の $\sqrt{2}$ 倍増を完全充足 |
| **2** | 軽度接続ノード | **9.5 px** ($\approx 5.5\sqrt{3}$) | $3.0\times$ | 通常のエンティティ |
| **3** | 中度接続ノード | **11.0 px** ($= 5.5\sqrt{4} = 2 R_0$) | $4.0\times$ | 中核的な関連トピック |
| **5** | クラスタ中核ノード | **13.5 px** ($\approx 5.5\sqrt{6}$) | $6.0\times$ | クラスタの主役として認識可能 |
| **8** | 主要ハブノード | **16.5 px** ($= 5.5\cdot 3$) | $9.0\times$ | 遠景でも即座に視認可能 |
| **15** | 超主要ハブ（例: CWE-20, MITRE T1059）| **22.0 px** ($= 5.5\cdot 4$) | $16.0\times$ | 一目でナレッジグラフの中心と判明 |

### 2.3 物理シミュレーション & インタラクションとの整合
- **ヒットテスト（マウスホバー & クリック）**: ノードごとの $R(k_i)$ を判定半径として使用し、大きなノードほどクリックしやすく直感的な操作感を提供。
- **ホバー時ハイライト**: ホバー時は $R(k_i) + 4\text{px}$ の拡大円を描画。
- **Research Gap パルスリング**: $R(k_i) + 4\text{px} + \text{pulse}$ で同心円状にアニメーション。
- **インスペクタ表示**: ノード詳細（`.node-callout`）内に「接続エッジ数 (Degree): $k$ 本」を表示。

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [site/dashboard.html](../../site/dashboard.html)
  - `updateNodeRadii(nodes, edges)` 関数の実装
  - `currentGraphMode === 'context'` および `currentGraphMode === 'cti'` のノード更新時に各ノードの `radius` を $R(k) = R_0 \cdot \sqrt{1 + k}$ に動的設定
  - Canvas 描画ループ (`ctx.arc`)、ヒットテスト (`findNodeAt`)、パルス描画での追従
  - ノードインスペクタパネルでの次数（Degree）バッジ表示
- [x] [docs/designs/DSN-14-graph_engineering_dashboard.md](../designs/DSN-14-graph_engineering_dashboard.md)
  - Section 3.6 に「ノード半径の次数面積比例スケーリングモデル（Degree-Proportional Area Model）」の数理仕様を追記
- [x] [tests/web/test_dashboard_graph_tab.py](../../tests/web/test_dashboard_graph_tab.py)
  - エッジ次数計算、面積比例スケーリング式、クランプ処理、インスペクタ表示を網羅する自動テストの追加

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/140-scale-vertex-size-by-edge-degree`

1. **次数計算ロジックの実装**:
   - `edges` 配列を走査し、`Map<nodeId, degreeCount>` を作成。
   - 各ノードの `radius` を $R_0 \cdot \sqrt{1 + \text{degree}}$（`min: 5.5px`, `max: 28px`）として算定。
2. **モード切替・クエリフィルタ連動**:
   - 初期ロード時（Context Mesh）および CTI 探索モード切り替え時（CTI Mesh）、クエリ絞り込み（Gaps / CWE / EGO 探索）によるサブグラフ抽出時にも、現在表示中のエッジセットに基づいてリアルタイムにノードサイズを再計算。
3. **インスペクタパネルの機能強化**:
   - 選択されたノードのメタデータ欄に `Edges: ${n.degree || 0}` を表示。
4. **テスト & 品質ゲート検証**:
   - `pytest`、`make format`、`make static_analysis` の完全通過。

---

## 5. 完了条件 / Success Criteria (DoD)
- [x] エッジ数 0 のノードの半径が基準サイズ（5.5px）で描画されること。
- [x] エッジ数 1 のノードの半径が約 7.8px（$\approx 5.5 \times \sqrt{2}$）となり、エッジが増えるごとに面積が線形（半径が $\sqrt{1+k}$ 倍）で拡大すること。
- [x] CTI モードおよびクエリ絞り込み時にも動的にエッジ数が再計算され、ノード半径が整合して反映されること。
- [x] ノードのホバー判定・クリック判定が動的半径に正しく追従すること。
- [x] 新規単体テストを含むテストスイートが 100% PASS すること。
- [x] `make static_analysis`（Xenon Grade A, Mypy `--strict` 368 source files）が 0 エラーであること。
- [x] 相対パスリンクチェックにおいて違反が 0 件であること。
