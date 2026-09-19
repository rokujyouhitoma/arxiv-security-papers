---
ID: 353
種別: Refactor
優先度: Medium
ステータス: Open (New)
---

# [FEAT/ENH] `StateStore` & `HierarchicalStateMachine`: フロントエンド状態一元管理と検索・操作ステートチャート統合 (ID: 353)

## 1. 概要 / Summary
`site/app.js` では `appStateStore` が導入されているものの、`currentOffset`, `currentLimit`, `activeTag`, `currentSearchResults` などの変数が依然としてローカルの `let` 変数として散在しており、UIとの同期漏れや重複更新の原因となっている。
また、検索中フラグやキャンバス操作状態が複数の boolean で管理されている。
これらを `site/js/frameworks/store.js` の `StateStore` に一元集約し、さらに `site/js/frameworks/hsm.js` の `HierarchicalStateMachine` (HSM) による厳格な状態遷移（Statecharts）を導入する。

---

## 2. トレーサビリティ / Traceability
- 関連 Issue:
  - [342-implement-statestore-pubsub-reactive-store.md](closed/342-implement-statestore-pubsub-reactive-store.md)
  - [343-port-hsm-core-to-frontend-state-governance.md](closed/343-port-hsm-core-to-frontend-state-governance.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [site/app.js](../site/app.js) (ローカル変数の集約、HSM 状態マシンの適用)
- [ ] [site/dashboard.html](../site/dashboard.html) (キャンバス操作状態 HSM)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `refactor/353-centralize-state-store-and-hsm`

1. **`StateStore` への状態集約**:
   - `activeTag`, `activePeriod`, `currentLimit`, `currentOffset`, `totalHits`, `results` をすべて `appStateStore` の state ツリーに格納。
   - UI は `appStateStore.subscribe(key, listener)` で更新。
2. **`HierarchicalStateMachine` の導入**:
   - 検索ステートマシン:
     - `SearchState`: `Idle` → `Validating` → `Fetching` → `Success` / `Error`
   - 不正な状態遷移（例: フェッチ完了前の二重リクエスト、エラー中の不正レンダリング）をガード。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] `site/app.js` の主要状態変数が `StateStore` で一元管理されていること。
- [ ] 検索フローが HSM 経由で遷移し、競合や二重実行が防止されること。
- [ ] 回帰テスト全件 PASS、Closure Compiler コンパイル 0 エラー。
