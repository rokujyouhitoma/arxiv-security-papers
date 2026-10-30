---
ID: 640
種別: Feature
優先度: High
ステータス: Open (New)
---

# [FEAT] Nanopass ループバックエッジ・プロローグ Fuel 判定注入パス (inject-fuel-checks) の実装 (ID: 640)

## 1. 概要 / Summary
[DSN-37] Phase 3 Task 3.4 に基づき、Synapse-Core 内の全関数のプロローグおよびループバックエッジ（`label` への後方ジャンプ）に Fuel 減算・枯渇判定コードを自動注入する `inject-fuel-checks` パスを実装する。
手動の `yield` 呼び出しに依存しない強プリエンプションを AOT コンパイラ層で保証する。

---

## 2. トレーサビリティ / Traceability
- 設計仕様書: [DSN-37: Synapse 二層分離型並行処理基盤 ＆ AOT コンパイルパイプライン包括的アーキテクチャ設計書](../designs/DSN-37-synapse_dual_plane_concurrent_runtime_architecture.md#145-phase-3-nanopass-コンパイラ統合--fbip) (第 7.2 節 Fuel 減算プリエンプション、第 12.4 節 inject-fuel-checks、第 14.5 節 Task 3.4)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] `ulisp/passes/pass_inject_fuel.scm` (新規: Fuel 注入パス)
- [ ] `tests/passes/test_pass_inject_fuel.scm` (新規: Fuel 注入コード検証テスト)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/640-nanopass-inject-fuel-checks`

1. **関数プロローグへの注入**:
   - 関数エントリポイント直後に `(if (<= (task-fuel current-task) 0) ...)` を挿入。
2. **ループバックエッジの検出と注入**:
   - `(loop ...)` または `(goto label)` 等の後方ジャンプ命令を検知し、ジャンプ直前に Fuel デクリメントと条件分岐を挟み込む。
3. **分岐予測最適化**:
   - Fuel が 0 以下になる頻度は極めて低いため、uLisp バックエンドで Unlikely 分岐としてレイアウトし、パイプラインフラッシュを最小化。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] 生成された LIR / アセンブリに Fuel 減算と条件付き yield が漏れなく挿入されていること
- [ ] Fuel 注入による純粋ループの実行速度低下が許容範囲内（5% 未満）に収まること
- [ ] 無限ループコードを AOT コンパイルして実行した際、正常に yield が発動すること

