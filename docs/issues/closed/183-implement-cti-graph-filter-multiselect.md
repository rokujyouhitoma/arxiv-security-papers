---
ID: 183
種別: Feature
優先度: High
ステータス: Closed
---

# [FEAT/ENH] CTI Graph フィルター（Entity Type / Relation Type）複数同時選択（マルチセレクト）対応 (ID: 183)

## 1. 概要 / Summary

現在の `/dashboard?tab=graph` の「🛡️ CTI Graph (ATT&CK / CWE)」コントロールデッキにある
**Entity Type フィルター**（ATT&CK / CWE / Mitigation / All）および
**Relation Type フィルター**（Exploits / Mitigates / Discloses / Subclass / All）は、
ラジオボタン相当の排他的単一選択方式である。

ユーザーの要求により、**複数のフィルターを同時に選択できるマルチセレクト方式**に変更する。
- Entity Type: 例）ATT&CK + CWE を同時選択 → 両ノードタイプを表示
- Relation Type: 例）Exploits + Mitigates を同時選択 → 両エッジタイプを表示
- "All" ボタンは「全選択トグル」として機能する（すでに全選択なら全解除、未選択があれば全選択）
- 最低 1 つは常に選択状態を保つ（全解除は不可）
- 選択状態はビジュアルに CSS `--accent-*` バッジで反映される

---

## 2. トレーサビリティ / Traceability

- 関連資料: DSN-21 (Swiss Retro Minimalist Design System)、Issue #182 (CTI フィルタ CSS バッジ統一)、Issue #148 (Research Gaps Only フィルタ)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files

- [ ] [`site/dashboard.html`](../../site/dashboard.html) — フィルターボタン UI の JS ロジックおよび CSS 変更
- [ ] [`tests/web/test_dashboard_cti_graph.py`](../../tests/web/test_dashboard_cti_graph.py) — フィルターボタン DOM/JS ロジックのテスト更新
- [ ] [`tests/web/test_dashboard_graph_tab.py`](../../tests/web/test_dashboard_graph_tab.py) — 既存エッジリレーションフィルタのテスト互換確認

---

## 4. 実装方針 / Implementation Plan

Target Branch: `feat/183-cti-graph-filter-multiselect`

### 4.1 UI 変更 (`site/dashboard.html`)

#### Entity Type フィルター
1. JS 変数 `ctiEntityMode` (`'ATT&CK'|'CWE'|'all'`) を `Set<string> ctiEntityFilters` に変更
2. `filterCtiGraph()` 内のノード絞り込みロジックを `ctiEntityFilters.has(node.type)` または
   `ctiEntityFilters.has('all')` に変更
3. ボタンクリックハンドラ:
   - `'All'` クリック: 全選択トグル（`size === total` なら clear+add('all')、それ以外は全追加）
   - 個別クリック: `Set` への add/delete + 最低 1 件保持チェック + `'all'` の同期

#### Relation Type フィルター
1. JS 変数 `activeRelationFilter` (`string`) を `Set<string> activeRelationFilters` に変更
2. `filterCtiGraph()` 内のエッジ絞り込みを `activeRelationFilters.has(edge.relation)` または
   `activeRelationFilters.has('all')` に変更
3. ボタンクリックハンドラ: Entity Type と同様

#### CSS バッジ active 状態
- `.btn-filter.active` スタイルはそのまま維持
- `data-active="true"` 属性で複数ボタンが同時に active スタイル適用される

#### "All" ボタン同期ロジック
```
if (filters.size === individualOptions.length) {
    allButton.classList.add('active')
} else {
    allButton.classList.remove('active')
}
```

---

## 5. 完了条件 / Success Criteria (DoD)

- [x] Entity Type フィルターが複数同時選択可能で、グラフが正しく絞り込まれること
- [x] Relation Type フィルターが複数同時選択可能で、グラフが正しく絞り込まれること
- [x] "All" ボタンが全選択/全解除のトグルとして機能すること
- [x] 最低 1 つのフィルターが常に active であること（全解除不可）
- [x] CSS バッジ (`--accent-*`) が選択状態に応じて正しく反映されること
- [x] `tests/web/test_dashboard_cti_graph.py` が全 PASS すること
- [x] `make static_analysis` が 100% PASS すること
