---
ID: 637
種別: Feature
優先度: High
ステータス: Open (New)
---

# [FEAT] Nanopass コンパイラにおける二層プレーン分離パス (split-planes-pass) の実装 (ID: 637)

## 1. 概要 / Summary
[DSN-37] Phase 3 Task 3.1 に基づき、uLisp 多段 Nanopass コンパイラにおいて、外側のコントロールプレーン（R7RS）AST と内側の並列計算プレーン（Synapse-Core）AST を境界で分離する `split-planes-pass` を実装する。
`spawn-task` や `with-channel` を検知し、適切なコンパイルパイプラインへルーティングする。

---

## 2. トレーサビリティ / Traceability
- 設計仕様書: [DSN-37: Synapse 二層分離型並行処理基盤 ＆ AOT コンパイルパイプライン包括的アーキテクチャ設計書](../designs/DSN-37-synapse_dual_plane_concurrent_runtime_architecture.md#145-phase-3-nanopass-コンパイラ統合--fbip) (第 12.1 節 split-planes-pass、第 14.5 節 Task 3.1)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] `ulisp/passes/pass_split_planes.scm` (新規: Nanopass プレーン分離パス)
- [ ] `tests/passes/test_pass_split_planes.scm` (新規: プレーン分離 AST テスト)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/637-nanopass-split-planes-pass`

1. **構文マッチング**:
   - `(spawn-task body ...)` 形式の S 式をキャプチャ。
2. **境界キャプチャ変数解析**:
   - `body` 内で参照されている外側の自由変数を列挙。
   - 各変数の型を推論し、「即値渡し（レジスタコピー）」または「複合型（ディープコピー）」のマーキングを付与。
3. **AST 変換**:
   - 外側にはタスク生成と境界サニタイズ呼び出しを行うコードを生成。
   - 内側の `body` は Synapse-Core 専用の厳格な AST（`L_synapse_core`）として切り出し。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] `spawn-task` 式が検知され、境界サニタイズ呼び出しコードが外側 AST に生成されること
- [ ] 内側式が独立した Synapse-Core 中間表現として分離されること
- [ ] 通常の R7RS コードの Nanopass パイプラインにリグレッションが発生しないこと

