---
ID: 317
種別: Feature / UX
優先度: High
ステータス: Closed
---

# [FEATURE/UX] ダッシュボード ナレッジグラフにおける選択ノードの動的非表示および一括再表示機能の実装 (ID: 317)

## 1. 概要 / Summary
`site/dashboard.html` のナレッジグラフ表示画面において、グラフ分析中に特定の不要なノード（ノイズや分析対象外のエンティティ・論文ノード）を一時的に非表示（Hide）にし、さらに非表示にした全ノードを一括で再表示（Unhide All）できる機能を実装した。

### 解決した課題
- 複雑なグラフや密度の高いネットワークにおいて、特定のハブノードや中間ノードを一時的に隠して背後の関係性を明確にしたいというニーズに対応。
- 既存のフィルター（エンティティ種別、最小次数、孤立ノード除外、LCC）とシームレスに連動し、ノード非表示に伴うエッジ接続数・孤立状態の変化を正しく自動再計算。

---

## 2. トレーサビリティ / Traceability
- 関連仕様: W3C HTML Canvas 2D Context, CTI Knowledge Graph Navigation Protocol
- 関連 Issue: [#316](316-fix-dashboard-canvas-zoom-scaling-and-physics-bounds.md), [#250](250-implement-louvain-community-detection-for-cti-graph.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [x] `site/dashboard.html`:
  - 状態管理: `hiddenNodeIds` (Set)
  - コア関数: `window.hideNode()`, `window.hideCurrentSelectedNode()`, `window.unhideAllNodes()`, `updateHiddenNodesUI()`
  - パイプライン連携: `applyCtiFilter()`, Context Mesh `applyContextMesh()` の最上流フィルタリング
  - UI 拡張: コールアウトパネル（`#btnHideSelectedNode`）、コントロールデッキ（`#btnUnhideAllNodes`, `#hiddenNodesCount`）
  - キーボードショートカット: `Delete`, `Backspace`, `x`（非表示）、`Shift+H`, `u`（再表示）
  - ヘルプドロワー: 操作ガイドへのキーバインド追記
- [x] `tests/web/test_dashboard_graph_tab.py`: 新規検証テスト `test_dashboard_node_hiding_and_unhiding` の追加
- [x] `docs/issues/README.md`: Issue 台帳の更新 (Closed へ移動)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/317-implement-node-hiding-and-unhiding-in-dashboard`

1. **状態管理 & コアロジック**:
   - `hiddenNodeIds = new Set();` を定義。
   - `hideNode(nodeId)` 実行時、選択状態を解除し、Egoフォーカス中心であればフォーカスを解除した上で、アクティブなグラフモードのフィルター関数を再呼出し。
   - `unhideAllNodes()` で全解除し、再描画。
2. **フィルターパイプライン最上流統合**:
   - `filteredNodes = filteredNodes.filter(n => !hiddenNodeIds.has(n.id));` を最上流で実行。
   - これにより、非表示ノードに接続するエッジが candidateEdges から自然に除外され、次数計算や孤立ノード判定が自動連動。
3. **UI/UX の追加**:
   - `#nodeCallout` に「👁️ このノードを非表示」ボタンを追加。
   - コントロールデッキのプリセット列に「👁️ 復元 (N)」ボタンを追加。非表示が0件のときは非表示、1件以上で表示。
   - ショートカットキー `Delete`, `Backspace`, `x`, `Shift+H`, `u` を実装。

---

## 5. 脅威分析およびセキュリティ要件 / Threat Modeling & Security
- **入力サニタイズ**: 非表示 ID の追加・判定はローカル Set による参照のみであり、DOM 挿入による XSS リスクは皆無。
- **メモリリーク防止**: グラフモード切替やデータ再フェッチ時にも整合性を維持。

---

## 6. 完了条件 / Success Criteria (DoD)
- [x] コールアウトパネルまたはキーボード（Delete, Backspace, x）で選択ノードが即座に非表示になること。
- [x] 非表示ノードに接続するエッジが連動して消去され、孤立ノードや次数フィルターが正しく再評価されること。
- [x] コントロールデッキの復元ボタンまたはキーボード（Shift+H, u）で非表示ノードが全件即座に再表示されること。
- [x] 非表示件数バッジがリアルタイムに更新されること。
- [x] ユニットテスト全件 PASS、品質ゲートが 100% PASS すること。
