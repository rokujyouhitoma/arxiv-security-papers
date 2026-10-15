---
ID: 526
種別: Feature
優先度: Medium
ステータス: Closed (Completed)
完了日: 2026-10-16
---

# [FEAT/ENH] Mytkowicz 測定バイアス排除機構と動的命令数差分テスト基盤 (DSN-35) の統合 (ID: 526)

## 1. 概要 / Summary
コーネル大学 CS 6120 (Lesson 1 & Mytkowiczら ASPLOS 2009 / brench) の実証的評価理論に基づき、継続的性能評価基盤（DSN-35）を高度化する。
最適化パスの評価において、コードリンク順序やスタックオフセットの偶然によるキャッシュヒット（Placement Bias）を排除するため、全関数およびループヘッダへの 16-byte アライメント（`.p2align 4`）強制、テストハーネス起動時の環境変数長パディング（4KB 固定化）を導入する。さらに、単なる Wall-clock 経過時間のみならず Linux `perf stat` 連携による動的命令カウント（Dynamic Instruction Count）と分岐ミス数の直接計測を可能にし、成熟 Scheme 処理系（Chez Scheme / Chibi Scheme / Gauche）との完全一致を自動検証する差分テスト基盤（Differential Testing）を CI に配備する。

---

## 2. トレーサビリティ / Traceability
- **関連設計書**:
  - [DSN-35: 継続的性能評価基盤 設計仕様書 (第6章 Mytkowicz 測定バイアス排除)](../designs/DSN-35-ilisp_ulisp_aot_jit_continuous_benchmarking_framework.md)
  - [DSN-33: ULISP 包括設計仕様書](../designs/DSN-33-ulisp_underlying_x86_native_aot_compiler_architecture_specification.md)
- **関連先行 Issue**:
  - Issue #515: ILisp・ULisp AOT・ULisp JIT 3種実行系性能評価および継続的ベンチマーク基盤の構築
  - Issue #478: chibi-scheme 公式 R7RS 適合性テストスイートの 100% 完全合格化

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [tools/benchmark_ilisp_ulisp.py](../../tools/benchmark_ilisp_ulisp.py) (環境変数パディング、`perf stat` 連携、命令カウント取得)
- [x] [ulisp/passes/07_backend_x86_64.scm](../../ulisp/passes/07_backend_x86_64.scm) (関数・ループヘッダへの `.p2align 4` 強制)
- [x] [ulisp/passes/07_backend_aarch64.scm](../../ulisp/passes/07_backend_aarch64.scm) (AArch64 向け命令アライメント)
- [x] [tools/differential_test_ulisp.py](../../tools/differential_test_ulisp.py) (新規作成: Chez/Chibi/Gauche 差分テストランナー)
- [x] [ulisp/Makefile](../../ulisp/Makefile) (`make bench_perf`, `make diff_test` ターゲット追加)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/526-ulisp-mytkowicz-bias-elimination-and-differential-testing`

1. **アライメントパディングとスタック統一の強制**:
   - x86-64 バックエンドのエミッタにおいて、すべての手続きラベルおよびループヘッダ直前に `.p2align 4` を明示的に出力。
   - ベンチマーク実行スクリプト `benchmark_ilisp_ulisp.py` において、`execve` 実行時に `BENCHMARK_ENV_PAD` 等で環境変数合計長を 4096 バイトに固定化。
2. **ハードウェア性能カウンタ（`perf stat`）の統合**:
   - `--perf` オプションにより、`instructions:u`, `branch-misses:u`, `L1-icache-load-misses` を取得し、`outputs/benchmarks/latest.json` に構造化記録。
3. **差分テスト（Differential Testing）フレームワークの実装**:
   - `tools/differential_test_ulisp.py` を作成し、Gabriel ベンチマーク等の S 式コードを ULisp ネイティブと他処理系で並行実行して出力・終了コードの一致を自動判定。

---

## 5. 完了条件 / Success Criteria (DoD)
- [x] バックエンド生成アセンブリに関数・ループの 16 バイトアライメントが正確に出力されること。
- [x] `make -C ulisp bench_perf` により、動的実行命令数（Instructions）の測定結果がレポートに出力されること。
- [x] 差分テストにおいて、Chez Scheme / Chibi Scheme との出力一致率が 100% であること。
