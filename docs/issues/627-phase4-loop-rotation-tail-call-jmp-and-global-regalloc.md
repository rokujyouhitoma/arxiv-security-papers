---
ID: 627
種別: Feature
優先度: High
ステータス: Open (New)
---

# [FEAT/OPT] ULisp x86-64 ネイティブバックエンド Phase 4: ループ回転・末尾呼出し JMP 最適化・大域レジスタ割り付けと Pure C パリティ検証 (ID: 627)

## 1. 概要 / Summary
Pure C -O2 パリティ達成に向けた最終フェーズとして、**ループ回転（Loop Rotation）、自己末尾呼出しの単純 JMP 展開、汎用レジスタ（Callee-saved）への大域レジスタ割り付け（Global Register Allocation）**を導入し、全 6 大ベンチマークにおいて Pure C -O2 パリティ比率 1.0x〜1.5x を実証・完遂する。

現状、`loop 10M` のような単純な末尾再帰であっても、ループ内でのスタックアクセスや、冗長な条件分岐ジャンプが存在する。
本 Phase 4 では、中間変数を Callee-saved レジスタ（`rbx`, `r12`, `r13`, `r14`, `r15`）にピン留め・割り付けし、自己末尾再帰をプロローグ/エピローグなしの単一高速ループブロックへ回転・低減する。
さらに、最適化適用後の全ベンチマークを 30 反復測定し、公式正典ベースライン（`ulisp/benchmarks/BASELINE.md`）を更新する。

---

## 2. トレーサビリティ / Traceability
- **先行 Phase Issues**:
  - [624-phase1-direct-known-function-calls.md](624-phase1-direct-known-function-calls.md) (Phase 1: 既知関数の直接呼出)
  - [625-phase2-system-v-register-based-calling-convention.md](625-phase2-system-v-register-based-calling-convention.md) (Phase 2: System V レジスタ引数呼出規約)
  - [626-phase3-interprocedural-unboxing-and-raw-int64-arithmetic.md](626-phase3-interprocedural-unboxing-and-raw-int64-arithmetic.md) (Phase 3: S-RTyper 連携アンボックス演算)
- **正典仕様書 & 成果物**:
  - [ulisp/benchmarks/BASELINE.md](../../ulisp/benchmarks/BASELINE.md) (正典性能ベースライン測定レポート)
  - [outputs/benchmarks/canonical_baseline.json](../../outputs/benchmarks/canonical_baseline.json)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [ulisp/lir/132_lir_braun_ssa.scm](../../ulisp/lir/132_lir_braun_ssa.scm) (Pass 132: Braun SSA 形式に基づくレジスタ割付け最適化)
- [ ] [ulisp/lir/133_lir_peephole.scm](../../ulisp/lir/133_lir_peephole.scm) (Pass 133: LIR ピープホール最適化とループ回転)
- [ ] [ulisp/backend/140_backend_x86_64.scm](../../ulisp/backend/140_backend_x86_64.scm) (Pass 140: リーフフレーム省略、`.p2align 4` ループ境界整列)
- [ ] [ulisp/benchmarks/BASELINE.md](../../ulisp/benchmarks/BASELINE.md) (全 Phase 完了後の正典ベースライン更新)
- [ ] [ulisp/benchmarks/verify_regression.py](../../ulisp/benchmarks/verify_regression.py) (回帰監視基準値の追随更新)

---

## 4. 具象的改善アプローチ / Technical Approach
1. **自己末尾呼出しの直接ジャンプ化 (Tail Call as Direct Jump)**:
   - 関数の自己再帰呼び出しをスタック調整を伴わない単純な `jmp .L_loop_head` に展開。
2. **大域レジスタ割り付け (Global Register Allocation)**:
   - ループ誘導変数やアキュムレータを `rbx, r12, r13, r14` に配置。
3. **ループ境界アライメント**:
   - ループ先頭ラベル直前に `.p2align 4` を挿入し、キャッシュライン跨ぎによる命令フェッチストールを防止。
4. **Pure C -O2 パリティ測定と検証**:
   - `make -C ulisp bench_baseline` で 30 回反復測定し、目標パリティ比率（1.0x〜1.5x）の達成を確認。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] `loop 10M` の実行時間が 2.0 ms 未満に短縮されること。
- [ ] `Fibonacci (fib 30)` の実行時間が Pure C -O2 に対し **1.1x 圏内（< 4.3 ms）** を達成すること。
- [ ] `Ackermann (ack 3 7)` の実行時間が Pure C -O2 に対し **1.5x 圏内（< 5.1 ms）** を達成すること。
- [ ] `ulisp/benchmarks/BASELINE.md` が最新の計測結果で更新され、改善の履歴と分析が明記されること。
- [ ] `make test` および `make py_compile static_analysis` がエラー 0 件で通過すること。
