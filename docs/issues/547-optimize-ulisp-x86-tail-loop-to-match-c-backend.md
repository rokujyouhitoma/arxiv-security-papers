---
ID: 547
種別: Feature
優先度: High
ステータス: Open (New)
---

# [FEAT/ENH] ULisp x86における末尾再帰ループ (loop 10M) の高速化（ループヘッダ回転・直結バックワード分岐・アンローリング） (ID: 547)

## 1. 概要 / Summary
最新ベンチマーク実測において、ULisp x86 の末尾再帰ループ（`loop 10M`）は Issue #546（インプレース引数シャッフル）により 22.88 ms から **4.79 ms**（Chez Scheme 64.59 ms 比で約13.5倍高速）へと劇的に改善された。

しかしながら、Portable C バックエンド（GCC -O2 経由）の実測値 **0.59 ms** と比較すると約 8 倍の開きが存在する。この要因を分析したところ、以下のマイクロアーキテクチャ上の非効率性が判明した：
1. **二重ジャンプの存在（ループヘッダ反転・ローテーションの未適用）**:
   現状の x86 出力はループ先頭で `cmp; jne .L_else; jmp .L_end; .L_else: add; add; jmp .L_cont_entry` となっており、1反復あたり `jne` と無条件 `jmp` の計2回の分岐命令を実行している。標準的なコンパイラ最適化（Loop Inversion / Do-While Rotation）を適用すれば、ループ末尾の単一 `jne .L_loop` のみで反復可能となる。
2. **ループアンローリング（Loop Unrolling）の欠如**:
   GCC -O2 ではループ体が 4〜8 倍に展開され、IPC（Instructions Per Cycle）が最大化されているのに対し、ULisp x86 は 1 反復ごとに分岐予測・命令デコード境界を跨いでいる。
3. **命令列の最適化（`inc` / `add` のスケジューリングとパイプライン並列性）**:
   累積器加算とカウンタ更新のスケジューリング最適化。

本 Issue では、x86-64 バックエンドおよび LIR 最適化において「ループヘッダ回転（Loop Rotation）」および「局所ループアンローリング」を導入し、ULisp x86 のループ実行性能を ULisp C（0.59 ms）と同等または上回るサブミリ秒（< 1.0 ms）水準へと引き上げる。

---

## 2. トレーサビリティ / Traceability
- 実測ベンチマーク表: [ulisp/docs/PORTABLE_BUILD_GUIDE.md](../../ulisp/docs/PORTABLE_BUILD_GUIDE.md) 第6章
- 関連Issue:
  - [closed/544-implement-loop-variable-register-allocation.md](closed/544-implement-loop-variable-register-allocation.md) (ループ変数レジスタ割付)
  - [closed/545-implement-condition-branch-flag-fusion.md](closed/545-implement-condition-branch-flag-fusion.md) (条件分岐融合)
  - [closed/546-implement-in-place-tail-loop-argument-shuffle-optimization.md](closed/546-implement-in-place-tail-loop-argument-shuffle-optimization.md) (インプレース末尾引数シャッフル)
- 測定スクリプト: [tools/benchmark_portable_guide.py](../../tools/benchmark_portable_guide.py)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [ulisp/passes/06_lir.scm](../../ulisp/passes/06_lir.scm) (ループ反転・ブロック配置・アンローリング LIR 最適化)
- [ ] [ulisp/passes/07_backend_x86_64.scm](../../ulisp/passes/07_backend_x86_64.scm) (単一バックワード条件分岐への還元・コード配置アライメント)
- [ ] [ulisp/tests/passes/test_inplace_shuffle.scm](../../ulisp/tests/passes/test_inplace_shuffle.scm) (回帰テスト)
- [ ] [tools/benchmark_portable_guide.py](../../tools/benchmark_portable_guide.py) (性能検証スクリプト)
- [ ] [ulisp/docs/PORTABLE_BUILD_GUIDE.md](../../ulisp/docs/PORTABLE_BUILD_GUIDE.md) (測定結果更新)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/547-optimize-ulisp-x86-tail-loop-to-match-c-backend`

1. **ループヘッダ回転（Loop Rotation / Inversion）**:
   - 末尾再帰関数のエントリー直後にループ本体へ飛び、本体末尾に `cmp rbx, limit; jne .L_loop_body` を配置する do-while 形式へのブロック再編成。
   - 1 反復内の無条件ジャンプ `jmp .L_cont_entry` を完全に消去し、1反復あたり単一のバックワード条件分岐（Backward Branch）のみに削減。
2. **小規模ループアンローリング（2x / 4x Unrolling）の検討・導入**:
   - 静的ストライド（ステップ 1）かつ固定境界値のホットループに対し、2〜4 回の反復を展開して命令並列性を引き出す。
3. **性能ベンチマーク検証**:
   - `loop 10M` において 4.79 ms から 0.5〜1.0 ms への高速化を実測検証。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] `loop 10M` において、反復ごとの無条件ジャンプが排除され、単一バックワード条件分岐で反復すること。
- [ ] 1000万回反復（`loop 10M`）の所要時間が 4.79 ms から大幅に短縮（目標: 1.0 ms 以下、ULisp C 0.59 ms に肉薄・同等）すること。
- [ ] 既存の全テストスイート（`test_loop_reg`, `test_branch_fusion`, `test_inplace_shuffle`）が 100% PASS すること。
- [ ] [ulisp/docs/PORTABLE_BUILD_GUIDE.md](../../ulisp/docs/PORTABLE_BUILD_GUIDE.md) の実測比較表が最新測定結果で更新されること。
