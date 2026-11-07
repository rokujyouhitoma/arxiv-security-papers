---
ID: 769
種別: Feature
優先度: Medium
ステータス: Open (New)
---

# [FEAT/ENH] 発火 Picopass 名の来歴追跡 (Provenance Tracking) トレーサと Rule-level Auto-Bisect 自動二分探索デバッグの実装 (DSN-33-01 T6.2) (ID: 769)

## 1. 概要 / Summary

[[DSN-33-01] ULisp 階層型パス融合 ＆ DAG 最適化基盤設計書](../designs/DSN-33-01-ulisp_pipeline_pass_nanopass_picopass_dag_architecture.md) の第 7.2 節（来歴追跡と細粒度 AST Diff）、第 7.3 節（ルール単位の自動二分探索デバッグ）、およびタスク **T6.2** に基づき、以下の2つの高度な診断・自己修復支援機能を実装する：

1. **Picopass 発火来歴追跡（Provenance Tracking）と細粒度 AST Diff**:
   - Nanopass 内で Picopass が発火してノードが書き換えられた際、「どの Nanopass の、どの Picopass ルール名（例: `desugar-all :: rule-desugar-letrec`）が発火したか」を記録し、トレース出力および下流エラー診断（`compiler_diagnostics`）に表示する。
2. **Rule-level Auto-Bisect（ルール単位の自動二分探索 / Delta Debugging）**:
   - 個別の Picopass を名前単位で有効・無効化する API（`disable-picopass!`, `enable-picopass!`, `picopass-enabled?`）を実装する。
   - さらに、与えられた候補ルールリストとテスト述語関数 `(test-fn)` に対して二分探索を自動実行し、不具合を引き起こしている最小の Picopass ルールを特定する `(auto-bisect-picopasses candidate-rules test-fn)` を実装する。

---

## 2. トレーサビリティ / Traceability

- 関連設計書:
  - [[DSN-33-01] ULisp 階層型パス融合 ＆ DAG 最適化基盤設計書](../designs/DSN-33-01-ulisp_pipeline_pass_nanopass_picopass_dag_architecture.md) (第 7.2 節, 第 7.3 節, 第 8.4 節, 第 9.2 節 タスク **T6.2**)
- 依存関係:
  - 先行 Issue: [Issue #767 (T5.3: LIR ピープホールの Picopass 化)](767-migrate-lir-peephole-to-picopass-and-dependency-dag.md), [Issue #768 (T6.1: define-pipeline 用途別編成)](768-implement-define-pipeline-for-aot-repl-and-check-modes.md)
  - 後続 Issue: [Issue #770 (T6.3: 3-Stage セルフホスティング不動点検証)](770-verify-stage3-self-hosting-fixed-point-and-benchmark-pass-fusion.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files

- [ ] [ulisp/compiler/nanopass_meta.scm](../../ulisp/compiler/nanopass_meta.scm)
- [ ] [ulisp/compiler/pass_manager.scm](../../ulisp/compiler/pass_manager.scm)
- [ ] [ulisp/tests/test_nanopass_tracer.scm](../../ulisp/tests/test_nanopass_tracer.scm)
- [ ] [ulisp/tests/test_pass_manager.scm](../../ulisp/tests/test_pass_manager.scm)

---

## 4. 実装方針 / Implementation Plan

Target Branch: `feat/769-picopass-provenance-and-auto-bisect`

1. **Picopass 単位の有効・無効化と発火カウンタ・来歴ログの実装**:
   - `*disabled-picopasses*` リストと `*picopass-firing-log*` を `nanopass_meta.scm` に設ける。
   - `fuse-rules` / `fuse-window-rules` のディスパッチ実行時に `(picopass-enabled? rule-name)` を確認し、発火時にはルール名と変更前後のノード断片を来歴ログへ記録する。
   - `nanopass-display-ast-diff` 出力時に、そのパス内で発火した Picopass ルール名と発火回数の内訳も併せて表示する。
2. **Delta Debugging 二分探索エンジン `auto-bisect-picopasses` の実装**:
   - ルールリスト $R = [r_1, \dots, r_n]$ を前半 $R_1$ と後半 $R_2$ に分割し、`disable-picopass!` で片方ずつ無効化して `(test-fn)` を評価することで、$O(\log_2 n)$ ステップで原因ルール $r_k$ を特定して返す関数を実装する。

---

## 5. 完了条件 / Success Criteria (DoD)

- [ ] `--trace-passes` 実行時に、パス名だけでなく発火した個別 Picopass ルール名と発火回数がトレース表示されること。
- [ ] `disable-picopass!` によって特定の Picopass 規則のみをピンポイントで無効化できること。
- [ ] 意図的にバグを含むダミー最適化 Picopass を混ぜたテストにおいて、`auto-bisect-picopasses` がそのバグルール1個を正確に二分探索で特定できること（`test_pass_manager.scm` / `test_nanopass_tracer.scm` で検証）。

