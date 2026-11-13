---
ID: 814
種別: Feature
優先度: Medium
ステータス: Open (New)
---

# [FEAT/ENH] 143_backend_x86_peephole.scm の define-picopass 化と fuse-window-rules への移行 (ID: 814)

## 1. 概要 / Summary
Nanopass アーキテクチャ仕様書（DSN-33-01 Task 5.3）において、LIR ピープホール最適化（Pass 133）および x86 ネイティブピープホール最適化（Pass 143）は `define-picopass (InstWindow ...)` および `fuse-window-rules` スライディングウィンドウ走査への移行対象として設計された。
しかし先行する Issue #767 では Pass 128 (LIR 分岐融合) および Pass 133 (LIR ピープホール) のみが Picopass 化され、`ulisp/backend/143_backend_x86_peephole.scm` は手書きの `x86-peephole-step-window`（8 規則、約180行の手動走査ループ）のまま取り残されている。

本 Issue では、Pass 133 の実績ある `InstWindow` パターン整合DSLおよび `fuse-window-rules` を用いて、`143_backend_x86_peephole.scm` の全ピープホール規則を第一級 Picopass に移行する：
1. 8 つの x86 最適化規則（自己代入除去、往復レジスタ転送除去、XOR ゼロ初期化、直後ラベルへの冗長 jump 除去、アライメント越え jump 除去、LEA 統合、到達不能コード除去、Jump-to-Return 簡約）を個別の `define-picopass` に分解・定義。
2. `optimize-x86-peephole-insts` 手書きループを `(define-pass x86-peephole-pass : L_asm_x86 (ir) -> L_asm_x86 () (fuse-window-rules ...))` に置換。
3. Issue #769 で導入された Provenance Tracking（発火 Picopass 名追跡）および Auto-Bisect（ルール単位の自動二分探索デバッグ）の対象を x86 バックエンドまで完全拡大する。

---

## 2. トレーサビリティ / Traceability
- [DSN-33-01 Nanopass/Picopass DAG アーキテクチャ仕様書 Section 3.3 & 5.3](../designs/DSN-33-01-ulisp_pipeline_pass_nanopass_picopass_dag_architecture.md)
  - T3.3: LIR/マシン命令列向け fuse-window-rules スライディングウィンドウ走査および収束ドライバの実装
  - T5.3: LIR 分岐融合 (128)・ピープホール (133)・x86 ピープホール (143) の Picopass 化
- 関連 Issue:
  - [Issue #761 (fuse-window-rules 実装)](closed/761-implement-fuse-window-rules-for-lir-sliding-window.md)
  - [Issue #767 (LIR ピープホール Picopass 化)](closed/767-migrate-lir-peephole-to-picopass-and-dependency-dag.md)
  - [Issue #769 (Provenance Tracking & Auto-Bisect)](closed/769-implement-picopass-provenance-tracing-and-auto-bisect.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [ulisp/backend/143_backend_x86_peephole.scm](../../ulisp/backend/143_backend_x86_peephole.scm) (Picopass 規則化および fuse-window-rules 置換)
- [ ] [ulisp/tests/passes/test_143_backend_x86_peephole.scm](../../ulisp/tests/passes/test_143_backend_x86_peephole.scm) (個別 Picopass 規則の単体テスト検証)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/814-migrate-x86-peephole-to-picopass-and-fuse-window-rules`

1. **規則の分解と define-picopass 化**:
   - `rule-x86-self-mov-elim`: `(mov reg reg) -> ()`
   - `rule-x86-roundtrip-mov-elim`: `(mov r1 r2) (mov r2 r1) -> (mov r1 r2)`
   - `rule-x86-zero-xor`: `(mov reg 0) -> (xor reg reg)`
   - `rule-x86-jump-next-label`: `(jmp L1) (%label L1) -> (%label L1)`
   - `rule-x86-jump-p2align-next-label`: `(jmp L1) (%p2align _) (%label L1) -> (%p2align _) (%label L1)`
   - `rule-x86-lea-optimize`: `(mov r1 r2) (add r1 imm) -> (lea r1 (%disp imm r2))`
   - `rule-x86-unreachable-dce`: `(jmp L) / (ret)` 直後の不要命令除去
   - `rule-x86-jump-to-ret`: 直前 jump の ret 置換
2. **fuse-window-rules の適用**:
   - `x86-peephole-step-window` 手動走査を撤廃し、`define-pass` 内の `fuse-window-rules` で宣言的固定点走査に接続。
3. **検証**:
   - `make -C ulisp test_backend`, `make -C ulisp test_lir_suite`, `make -C ulisp bootstrap_verify` で既存の x86 出力およびバイナリ動作に回帰がないことを確認。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] `143_backend_x86_peephole.scm` 内の全 8 規則が `define-picopass` として個別に定義されていること。
- [ ] 手書きの `x86-peephole-step-window` が撤去され、`fuse-window-rules` による宣言的パス定義に置換されていること。
- [ ] x86 ピープホールの各 Picopass 規則の発火が Provenance Tracking（Issue #769）で記録可能であること。
- [ ] `make -C ulisp compiler` で `compiler.scm` が正常に再生成され、`make -C ulisp lint_sexpr` が通過すること。
- [ ] `make -C ulisp test_backend` および `make -C ulisp test_passes` が 100% PASS すること。
- [ ] `make -C ulisp bootstrap_verify` で Stage 2 と Stage 3 の bit-for-bit 不動点一致が確認されること。
- [ ] `make py_compile && make static_analysis` が 100% PASS すること。
- [ ] ドキュメント内のすべてのリンクが相対パスで記述されていること。
