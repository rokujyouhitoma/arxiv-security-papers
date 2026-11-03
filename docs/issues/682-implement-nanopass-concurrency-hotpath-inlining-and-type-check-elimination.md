---
ID: 682
種別: Feature
優先度: Medium
ステータス: Open (New)
---

# [FEAT/ENH] Nanopass コンパイラによる並行ホットプリミティブのネイティブインライン展開と型検査除去 (ID: 682)

## 1. 概要 / Summary
Synapse 並行処理基盤（[DSN-37](../designs/DSN-37-synapse_dual_plane_concurrent_runtime_architecture.md)）におけるマイクロタスク実行遅延（現在 244 ns/task）をさらに極小化するため、AOT Nanopass コンパイラフレームワーク（`lib/ulisp/concurrency/passes/`）を活用したコンパイル時最適化を導入する。
アフィン線形型検査（`check-affine-types`）によって安全性が静的に証明されたコード領域において、ランタイムの冗長な型検査（`%io-uring-assert-type!`, `record?` 等）を消去するとともに、頻出プリミティブ（`arena-alloc!`, `channel-send!`, `task-yield!`）の関数呼び出しプロローグ/エピローグを排除し、直接アセンブリ命令列へインライン展開する。

---

## 2. トレーサビリティ / Traceability
- 関連設計書: [DSN-37 Synapse Dual-Plane Concurrent Runtime Architecture](../designs/DSN-37-synapse_dual_plane_concurrent_runtime_architecture.md) (Phase 4 / Phase 8)
- 関連評価書: [Synapse Concurrency Benchmark Suite](../benchmarks/concurrency_evaluation.md)
- 先行 Issue: [Issue #638: check-affine-types パス](closed/638-implement-nanopass-check-affine-types-and-raii-drop.md), [Issue #637: split-planes パス](closed/637-implement-nanopass-split-planes-pass.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [ulisp/lib/ulisp/concurrency/passes/pass_check_affine.scm](../../ulisp/lib/ulisp/concurrency/passes/pass_check_affine.scm)
- [ ] [ulisp/lib/ulisp/concurrency/passes/pass_fbip.scm](../../ulisp/lib/ulisp/concurrency/passes/pass_fbip.scm)
- [ ] [ulisp/compiler_passes.scm](../../ulisp/compiler_passes.scm) (インライン展開ルールの追加)
- [ ] [tests/concurrency/test_pass_check_affine.scm](../../tests/concurrency/test_pass_check_affine.scm)
- [ ] [benchmarks/concurrency/bench_microtasks.scm](../../benchmarks/concurrency/bench_microtasks.scm)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/682-nanopass-concurrency-hotpath-inlining-and-type-check-elimination`

1. **静的型情報に基づくランタイムチェック除去**:
   - `check-affine-types` パスで検証済みのチャネル・アリーナ操作について、AOT 中間表現 (LIR) 生成時に防御的型アサーション式を安全に除去。
2. **ホットパスインライン展開パスの実装**:
   - `arena-alloc!`（バンプポインタ加算 2 命令）および `task-yield!`（セーフポイント判定 1 命令）を呼び出し側コードに直接展開。
3. **ベンチマークスループット検証**:
   - 関数呼び出しオーバーヘッドをゼロにすることで、10 万マイクロタスクスループットを 409 万 tasks/sec から 600 万 tasks/sec 以上へと引き上げる。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] アフィン型検査 PASS 済みの式において不要な動的型アサーションが除去されること。
- [ ] ホットプリミティブが中間表現レベルでインライン展開されること。
- [ ] 全 Nanopass テスト群（`test_pass_split_planes`, `test_pass_check_affine`, `test_pass_fbip`）が 100% PASS すること。
- [ ] ベンチマークにおけるスループット向上（マイクロタスク遅延 < 200 ns/task）が確認されること。
- [ ] 絶対パスリンクが 0 件であり、全内部リンクが相対パスであること。

