---
ID: 638
種別: Feature
優先度: High
ステータス: Open (New)
---

# [FEAT] アフィン線形所有権静的検査パス (check-affine-types) および自動 RAII Drop の実装 (ID: 638)

## 1. 概要 / Summary
[DSN-37] Phase 3 Task 3.2 に基づき、Synapse-Core 内部構文木において、変数が複数回消費（Use-After-Move）されていないか、および禁止構文（`set!`, `call/cc` 等）が含まれていないかを静的検証する `check-affine-types` パスを実装する。
未消費のままスコープを離脱する線形変数に対しては、自動的に解放コード（RAII Drop）を AST 末尾に注入する。

---

## 2. トレーサビリティ / Traceability
- 設計仕様書: [DSN-37: Synapse 二層分離型並行処理基盤 ＆ AOT コンパイルパイプライン包括的アーキテクチャ設計書](../designs/DSN-37-synapse_dual_plane_concurrent_runtime_architecture.md#145-phase-3-nanopass-コンパイラ統合--fbip) (第 4.3 節 線形型理論、第 12.2 節 check-affine-types、第 14.5 節 Task 3.2)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] `ulisp/passes/pass_check_affine.scm` (新規: アフィン線形型検査パス)
- [ ] `tests/passes/test_pass_check_affine.scm` (新規: 線形性静的エラー検証テスト)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/638-nanopass-check-affine-types`

1. **禁止構文の排除**:
   - `set!`, `set-car!`, `set-cdr!`, `call/cc` の出現を検知した場合、ファイル名と行番号を付けて即座にコンパイルエラーを出力。
2. **線形型環境（Type Environment）による使用カウント**:
   - 変数が関数引数やチャネル送信式に渡された時点で「消費済み（Consumed）」とマーク。
   - 同一スコープ内で再度その変数を参照しようとした場合、「Use-After-Move」エラーを報告。
3. **スコープ末尾での自動 RAII Drop コード生成**:
   - スコープ離脱時に未消費のまま残っている線形変数に対し、オブジェクト破棄コードを注入。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] 二重使用コード（Use-After-Move）に対して正確な診断メッセージ付きでコンパイル拒絶すること
- [ ] `set!` や `call/cc` を含むコードをコンパイルエラーとすること
- [ ] 正常な線形コードが通過し、未消費変数に対する Drop コードが正しく生成されること

