---
ID: 625
種別: Feature
優先度: High
ステータス: Open (New)
---

# [FEAT/OPT] ULisp x86-64 ネイティブバックエンド Phase 2: System V AMD64 レジスタ引数受渡し呼出規約（Register-Based Calling Convention）の導入 (ID: 625)

## 1. 概要 / Summary
Pure C -O2 パリティ達成に向けた第 2 フェーズとして、**スタック経由の引数受渡し（Stack-Spilling Calling Convention）を撤廃し、System V AMD64 ABI に準拠したレジスタ引数受渡し**を導入する。

現状の ULisp コンパイラでは、すべての関数引数がスタックフレーム（`[rsp - 40]` 等）を経由して渡されており、1 回の関数呼出し毎に最低 4〜6 回のメモリストア・ロード（`sub rsp, 40` / `mov [rsp - 40], rax` / `add rsp, 40`）が多発している。
これにより、L1D キャッシュの帯域を著しく浪費し、IPC（1サイクルあたり実行命令数）の低下を招いている。

本 Phase 2 では、第 1 引数〜第 6 引数を汎用レジスタ（`rdi`, `rsi`, `rdx`, `rcx`, `r8`, `r9`）で直接受渡しする呼出規約を確立し、スタックアクセスオーバーヘッドを撲滅する。

---

## 2. トレーサビリティ / Traceability
- **親ロードマップ & 先行 Phase**:
  - [624-phase1-direct-known-function-calls.md](624-phase1-direct-known-function-calls.md) (Phase 1: 既知関数の直接呼出)
- **後続 Phase Issues**:
  - [626-phase3-interprocedural-unboxing-and-raw-int64-arithmetic.md](626-phase3-interprocedural-unboxing-and-raw-int64-arithmetic.md) (Phase 3: S-RTyper 連携アンボックス演算)
  - [627-phase4-loop-rotation-tail-call-jmp-and-global-regalloc.md](627-phase4-loop-rotation-tail-call-jmp-and-global-regalloc.md) (Phase 4: ループ回転・末尾JMP・レジスタ割付とCパリティ検証)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [ulisp/lir/124_lir_call_abi.scm](../../ulisp/lir/124_lir_call_abi.scm) (Pass 124: レジスタ呼出規約とスタックスロットの割当て)
- [ ] [ulisp/lir/130_lir.scm](../../ulisp/lir/130_lir.scm) (Pass 130: 引数レジスタの LIR 命令表現)
- [ ] [ulisp/backend/140_backend_x86_64.scm](../../ulisp/backend/140_backend_x86_64.scm) (Pass 140: `rdi, rsi, rdx, rcx, r8, r9` 引数渡しアセンブリ出力)
- [ ] [ulisp/benchmarks/BASELINE.md](../../ulisp/benchmarks/BASELINE.md) (Phase 2 適用後の実行時間記録)

---

## 4. 具象的改善アプローチ / Technical Approach
1. **呼出規約の標準化**:
   - 引数 1〜6: `rdi`, `rsi`, `rdx`, `rcx`, `r8`, `r9` を順に割り当て。
   - 7 引数以降: 従来どおりスタックにスピル。
   - 戻り値: `rax`（多値の場合は第 2 戻り値を `rdx` に格納可能）。
2. **関数プロローグ／エピローグの軽量化**:
   - スタック操作（`sub rsp, N`）を引数受渡しの都度行わず、フレーム全体で一括アラインメント調整。
   - リーフ関数ではスタック確保そのものをスキップ。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] 6 引数以内の関数呼出しにおいて、スタック退避を行わず `rdi, rsi` 等のレジスタ経由で引数が受け渡されること。
- [ ] `fib 30` の実行時間が Phase 1 完了時点からさらに短縮され、< 5.0 ms（Pure C に対し 1.3x 圏内）に到達すること。
- [ ] `ack 3 7` の実行時間が < 7.0 ms（Pure C に対し 2.0x 圏内）に到達すること。
- [ ] 全テストスイートが 100% PASS すること。
