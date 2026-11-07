---
ID: 770
種別: Feature
優先度: High
ステータス: Open (New)
---

# [FEAT/ENH] DSN-33-01 完全統合後の 3-Stage セルフホスティング不動点検証および速度・ヒープ削減ベンチマーク実証 (DSN-33-01 T6.3) (ID: 770)

## 1. 概要 / Summary

[[DSN-33-01] ULisp 階層型パス融合 ＆ DAG 最適化基盤設計書](../designs/DSN-33-01-ulisp_pipeline_pass_nanopass_picopass_dag_architecture.md) の第 4.5 節（性能予測モデル）、第 9.2 節（タスク **T6.3**）、および第 9.3 節（品質ゲートとセルフホスティング不動点保証規準）に基づき、Issue #753 〜 #769（T1.1 〜 T6.2）の全成果物を統合した単一バンドル `ulisp/compiler.scm` を再生成し、3-Stage セルフホスティングブートストラップの完全不動点一致（Stage 2 と Stage 3 のバイナリ・アセンブリ `diff` ゼロ）を検証するとともに、`--time-passes` プロファイラを用いてコンパイル速度向上およびヒープメモリ消費削減効果を定量実証する。

---

## 2. トレーサビリティ / Traceability

- 関連設計書:
  - [[DSN-33] ULISP 包括設計仕様書](../designs/DSN-33-ulisp_underlying_x86_native_aot_compiler_architecture_specification.md) (第 5 章: 3段階セルフホスティングブートストラップ連鎖と不動点検証)
  - [[DSN-33-01] ULisp 階層型パス融合 ＆ DAG 最適化基盤設計書](../designs/DSN-33-01-ulisp_pipeline_pass_nanopass_picopass_dag_architecture.md) (第 4.5 節, 第 9.2 節 タスク **T6.3**, 第 9.3 節)
- 依存関係:
  - 先行 Issue: [Issue #753](closed/753-consolidate-define-language-files-and-establish-extends-chain.md) 〜 [Issue #769](769-implement-picopass-provenance-tracing-and-auto-bisect.md) (T1.1 〜 T6.2 全タスク)
  - 後続 Issue: なし（`DSN-33-01` ロードマップ完遂マイルストーン）

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files

- [ ] [ulisp/compiler.scm](../../ulisp/compiler.scm)
- [ ] [ulisp/Makefile](../../ulisp/Makefile)
- [ ] [ulisp/bootstrap.sh](../../ulisp/bootstrap.sh)
- [ ] [ulisp/docs/spec_pipeline.md](../../ulisp/docs/spec_pipeline.md)
- [ ] [docs/designs/DSN-33-01-ulisp_pipeline_pass_nanopass_picopass_dag_architecture.md](../designs/DSN-33-01-ulisp_pipeline_pass_nanopass_picopass_dag_architecture.md)

---

## 4. 実装方針 / Implementation Plan

Target Branch: `feat/770-verify-self-hosting-and-pass-fusion-benchmarks`

1. **`compiler.scm` バンドルの再生成と 3-Stage ブートストラップ不動点検証**:
   - `ulisp/Makefile` のバンドルターゲットを実行して最新のモジュール群から `ulisp/compiler.scm` を生成する。
   - `bootstrap.sh` により Stage 1 $\to$ Stage 2 $\to$ Stage 3 をビルドし、`diff -u stage2.s stage3.s`（および ELF バイナリ比較）が 0 バイト差分で完全一致することを検証する。
2. **コンパイル速度・ヒープ割り当て量の定量計測**:
   - `--time-passes` を有効化して `compiler.scm` 自身のセルフコンパイルおよびベンチマークスイートを実行し、各 Pass（特に `pass-030-desugar`, `pass-050-cp0`, `pass-133-lir-peephole`）の実行時間（ms）とヒープ割り当て量（KB）を計測し、`DSN-33-01` 第 4.5 節および `ulisp/docs/spec_pipeline.md` に実測値を記録する。

---

## 5. 完了条件 / Success Criteria (DoD)

- [ ] 3-Stage セルフホスティングブートストラップが完走し、Stage 2 と Stage 3 の出力が 100% 完全一致（Fixed-Point）すること。
- [ ] `--verify-ir`（Strict モード）有効下で全ユニットテスト・結合テスト（x86-64 / AArch64 / C99）が 100% PASS すること。
- [ ] `--time-passes` による実測プロファイルレポートが `DSN-33-01` に記録され、`make verify_quality` がエラー 0 件で PASS すること。

