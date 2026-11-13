---
ID: 770
種別: Feature
優先度: High
ステータス: Closed
完了日: 2026-11-13
---

# [FEAT/ENH] DSN-33-01 完全統合後の 3-Stage セルフホスティング不動点検証および速度・ヒープ削減ベンチマーク実証 (DSN-33-01 T6.3) (ID: 770)

## 1. 概要 / Summary

[[DSN-33-01] ULisp 階層型パス融合 ＆ DAG 最適化基盤設計書](../../designs/DSN-33-01-ulisp_pipeline_pass_nanopass_picopass_dag_architecture.md) の第 4.5 節（性能予測モデル）、第 9.2 節（タスク **T6.3**）、および第 9.3 節（品質ゲートとセルフホスティング不動点保証規準）に基づき、先行する Issue #753 〜 #769（Phase 1 〜 Phase 6.2）の全 Pass Fusion 成果物を包括統合する。

本 Issue は、`DSN-33-01` アーキテクチャロードマップ（全 18 タスク）の **最終完遂マイルストーン (T6.3)** である。
最新の全 4 階層パス体系（Nanopass / Picopass / Femtopass / Attopass）、Term DAG カタモルフィズム、LIR 命令依存 DAG 走査、用途別 Pipeline 宣言、および Provenance / Auto-Bisect 診断機構を包含した単一バンドル `ulisp/compiler.scm` を再生成し、以下の 3 大検証・実証を完遂する：

1. **3-Stage セルフホスティング完全不動点検証 (Fixed-Point Verification)**:
   - `ulisp/bootstrap.sh --modular`（5モジュール並列インクリメンタルビルド）およびモノリシック／分割リンクブートストラップを実行。
   - Stage 1 $\to$ Stage 2 $\to$ Stage 3 のコンパイル連鎖において、Stage 2 と Stage 3 の生成コード（アセンブリ `.s` および静的リンク ELF バイナリ）が 1 バイトの差異もなく完全一致（bit-for-bit identical）することを検証。
2. **コンパイル速度およびヒープ割り当て量の定量ベンチマーク実証**:
   - `--time-passes` プロファイラをセルフコンパイル（`compiler_entry.scm` および `test_all_passes_batch_runner.scm`）に対して実行。
   - DSN-33-01 第 4.5 節の性能予測モデル（コンパイル速度 2.0x 〜 4.0x 高速化、AST 再構築メモリ量 40% 〜 60% 削減）に対する実績値を計測・評価。
   - 主要 Pass（`pass-030-desugar`, `pass-050-cp0`, `pass-133-lir-peephole` 等）の実行時間（ms）、シェア率（%）、ヒープ割り当て量（KB）の内訳レポートを作成。
3. **仕様書・設計書への実測プロファイルデータの反映と品質ゲート完遂**:
   - `DSN-33-01` 第 4.5 節、第 9.2 節、および `ulisp/docs/spec_pipeline.md` に実測ベンチマーク数値を恒久記録。
   - リポジトリ品質ゲート（`make py_compile && make static_analysis`）を 0 エラーで完遂。

---

## 2. 背景と課題 / Background & Problem Analysis

`DSN-33-01` において策定された「Nanopass の粒度ジレンマ（きめ細かい言語検証の恩恵 vs 走査回数増大による $O(P \times N)$ の中間表現複製コスト）」を克服するため、以下の 5 大イノベーションが順次導入された：

1. **Phase 1〜2**: 言語階層の整理（`extends` 連鎖）と 4 階層パス体系（Nanopass / Picopass / Femtopass / Attopass）の確立（Issue #753〜#758）。
2. **Phase 3**: Frontend 脱糖パス群（`026`〜`029`）の単一走査融合（`pass-030-desugar`）と $O(1)$ Head-Tag ディスパッチ（Issue #759〜#761）。
3. **Phase 4**: IR 縮約規則（`050_cp0`）の Picopass 化と属性評価（`040_analysis` / `090_rtyper`）の Attopass 融合（Issue #762〜#764）。
4. **Phase 5**: ルール依存 DAG、HIR/MIR Term DAG カタモルフィズム、LIR 命令依存 DAG ピープホール（Issue #765〜#767）。
5. **Phase 6.1〜6.2**: 用途別パイプライン編成（`define-pipeline`）と発火来歴追跡・Auto-Bisect 診断基盤（Issue #768〜#769）。

これら一連の最適化により、コンパイラ内部の AST 走査回数は理論上 1/3 以下へ削減されたが、**「全機能を統合した最終バイナリが完全なセルフホスティング不動点（Fixed-Point）を維持しているか」**、および **「DSN-33-01 第 4.5 節で掲げた 2〜4 倍の高速化と 40〜60% のメモリ削減が実環境で達成されているか」** の包括的・決定的な実証測定が未実施であった。

本 Issue T6.3 の完遂をもって、ULisp の Pass Fusion アーキテクチャは正式に「設計・実装・自己複製検証・性能実証」の全サイクルを完結する。

---

## 3. 多角的視点レビュー / Multi-Agent Perspectives

本検証計画の策定にあたり、専門エージェント群による多角的検討を実施した：

- **Project Manager (PM)**:
  - DSN-33-01 ロードマップの最終タスク T6.3 として、プロジェクト全体の集大成となる品質ゲートを管理する。
  - 既存の全テストスイート（C99 ランタイム 143/143、Verifier 86/86、All Passes 39/39、Nanopass DSL 242/242、Tracer 48/48、Pass Manager 115/115）が 1 件の回帰もなく 100% PASS することを必須条件とする。
- **Systems Architect (SA)**:
  - 5 モジュール分割（`compiler_base`, `frontend_passes`, `lir_passes`, `backend_passes`, `compiler_driver`）および単一バンドル（`compiler.scm`）の双方において、Stage 2 と Stage 3 の生成コードが bit-for-bit で完全一致する不変不動点（Invariance Fixed-Point）をアーキテクチャ的に保証する。
- **Software Quality Assurance Specialist (SQA)**:
  - `--verify-ir`（Strict モード）を全結合テストに適用し、パス境界での言語スキーマ違反が 0 件であることを確認。
  - `--time-passes` による計測を複数回実行し、測定ジッター（外乱）を排除した中央値・安定値を採用する。
- **Software Development (SWD)**:
  - `ulisp/Makefile` の `compiler.scm` 依存関係が最新モジュール群を正しく反映していることを保証し、S式括弧チェッカー（`lint_sexpr`）を全 173 ファイルに対してパスさせる。
- **IT Specialist (Programming Languages & Compilers / PLC)**:
  - コンパイル速度向上とヒープ削減のメカニズム（Pass Fusion による中間 cons セル生成抑止、$O(1)$ Head-Tag ディスパッチによるルール探索短縮、Term DAG メモ化による同一部分木再帰スキップ）を定量的データに基づいて理論値と比較・分析する。
- **IT Strategist (STR)**:
  - 実測されたベンチマーク成果を `DSN-33-01` 設計書および公式ドキュメント `spec_pipeline.md` に反映し、次期並行性ランタイム（Synapse OSAL / Safepoint）基盤への移行に向けた確固たる技術的裏付けとする。
- **Systems Auditor (AUD)**:
  - ドキュメント内の全ハイパーリンクが相対パス規約に厳格に従っているか検査し、絶対パス（`/workspace/...` や `/root/...`）の混入を 0 件に抑止する。
- **IT Service Manager (SM)**:
  - 3-Stage セルフホスティングブートストラップが 35 秒以内（目標 10〜20 秒台）で完了し、継続的インテグレーション（CI）環境でのビルド安定性を確保する。

---

## 4. セキュリティ・堅牢性設計 / Security & Threat Modeling

コンパイラセルフホスティングおよびベンチマーク計測における堅牢性・セキュリティ要件：

1. **Trusting Trust 攻撃・自己複製汚染の完全排除**:
   - Stage 2 と Stage 3 の生成バイナリ・アセンブリが完全一致（Fixed-Point）することにより、コンパイラ自身が出力コードに未定義の副作用やバックドアを混入させない決定論的コンパイル（Deterministic Compilation）を担保。
2. **スタック・ヒープ境界防御**:
   - セルフコンパイル実行時における巨大 AST 走査（`compiler_entry.scm` は数千行規模）において、再帰カタモルフィズムがコールスタック溢れ（Stack Overflow）を起こさず、末尾再帰・ループへの局所再帰最適化が正しく機能していることを検証。
3. **プロファイラ計時・メモリ計測の例外安全性**:
   - `current-time-monotonic-us` および `current-heap-alloc-bytes` による計測フックが、コンパイルエラーや例外発生時にも `dynamic-wind` により安全にクリーンアップされ、メモリリークや未初期化状態を残さないこと。

---

## 5. 影響範囲と対象ファイル / Scope and Affected Files

### 対象ソースコード・ビルドスクリプト
- [ulisp/compiler.scm](../../ulisp/compiler.scm) (最新モジュール群から完全再生成)
- [ulisp/Makefile](../../ulisp/Makefile) (ビルド・検証・ベンチマークターゲット確認)
- [ulisp/bootstrap.sh](../../ulisp/bootstrap.sh) (3-Stage ブートストラップ不動点検証)
- [ulisp/bin/ulisp-boot](../../ulisp/bin/ulisp-boot) (検証済み Stage 3 バイナリでのシード更新)

### 設計書・仕様書ドキュメント
- [docs/designs/DSN-33-01-ulisp_pipeline_pass_nanopass_picopass_dag_architecture.md](../../designs/DSN-33-01-ulisp_pipeline_pass_nanopass_picopass_dag_architecture.md) (第 4.5 節・第 9 節のベンチマーク実測値反映)
- [ulisp/docs/spec_pipeline.md](../../ulisp/docs/spec_pipeline.md) (Pass Fusion 実行プロファイルおよび実測データ追記)
- [docs/issues/README.md](README.md) (Issue 台帳更新)

---

## 6. 実装方針と段階的計画 / Implementation Plan

Target Branch: `feat/770-verify-self-hosting-and-pass-fusion-benchmarks`

- [x] **Phase 1: `compiler.scm` バンドル再生成と S式構文検証**
  - `make -C ulisp compiler.scm` を実行し、Issue #753 〜 #769 の全変更を取り込んだ最新の単一統合ソースを生成。
  - `make -C ulisp lint_sexpr` を実行し、全 173 個の Scheme ファイル（ライブラリ＋コンパイラ＋テスト）で括弧の完全整合（100% balanced）を確認。
- [x] **Phase 2: 3-Stage セルフホスティング完全不動点検証 (Fixed-Point Verification)**
  - `bash ulisp/bootstrap.sh --modular` を実行し、全 5 モジュール（`compiler_base`, `frontend_passes`, `lir_passes`, `backend_passes`, `compiler_driver`）について Stage 2 と Stage 3 の生成アセンブリ（`stage2_*.s` vs `stage3_*.s`）の `diff` が 0 バイトであることを確認。
  - 生成された Stage 3 バイナリにより Smoke Test（42 出力）が正常動作することを確認。
  - `ulisp/bin/ulisp-boot` シードバイナリを不動点確認済み Stage 3 バイナリで同期更新。
- [x] **Phase 3: 包括的テストスイートによる後退（回帰）ゼロ検証**
  - 以下の全テストスイートを実行し、全件 PASS を確認：
    - `make -C ulisp test_c` (C99 ランタイムプリミティブテスト: 143/143 PASS)
    - `make -C ulisp test_verifier` (Nanopass / IR Invariant Verifier: 86/86 PASS)
    - `make -C ulisp test_nanopass` (Nanopass DSL / Fusion / Redispatch: 242/242 PASS)
    - `make -C ulisp test_all_passes` (全 39 Nanopass 1:1 単体テスト: 39/39 PASS)
    - `make -C ulisp test_pass_manager` (Pass Manager, Pipeline, Auto-Bisect: 115/115 PASS)
- [x] **Phase 4: `--time-passes` による速度・ヒープ削減定量ベンチマーク測定**
  - セルフコンパイル時（`compiler_entry.scm`）および大規模テスト実行時において `--time-passes`（`ULISP_TIME_PASSES=1`）を有効化し、Pass ごとの実行時間（ms）、シェア率（%）、ヒープ割り当て量（KB）を実測。
  - Pass Fusion 適用前後の比較を行い、以下の主要 Pass の効果を定量化：
    - `pass-030-desugar` (旧 026〜029 の 4 パス統合効果)
    - `pass-050-cp0` (Term DAG カタモルフィズムによる同一部分木再帰スキップ効果)
    - `pass-133-lir-peephole` (命令依存 DAG による非隣接 Store-Reload 統合効果)
  - DSN-33-01 第 4.5 節の性能予測モデル（2.0x〜4.0x 高速化、40%〜60% ヒープ削減）との対比評価レポートを作成。
- [x] **Phase 5: 設計書・公式ドキュメントの更新と品質ゲート検証**
  - `docs/designs/DSN-33-01-ulisp_pipeline_pass_nanopass_picopass_dag_architecture.md`:
    - 第 4.5 節「性能の定量的予測モデル」に実測結果テーブルを追記。
    - 第 9.2 節タスク T6.3 の完了を記録。
  - `ulisp/docs/spec_pipeline.md`:
    - Pass Fusion による最適化後の最新プロファイル結果を反映。
  - リポジトリ品質ゲート（`make py_compile && make static_analysis`）の 100% 適合を確認。
  - Issue ファイルを `docs/issues/closed/` へ移動し、`docs/issues/README.md` を更新。

---

## 7. 完了条件 / Success Criteria (DoD)

1. **3-Stage セルフホスティング不動点完全一致**:
   - `ulisp/bootstrap.sh --modular` を実行し、全 5 モジュールにおいて `diff -u build/stage2_*.s build/stage3_*.s` が 0 バイト差分で完全一致（bit-for-bit identical）すること。
   - ブートストラップ所要時間が 35 秒以内（目標 10〜20 秒台）に完了すること。
2. **包括的ユニット・統合テスト 100% PASS**:
   - `test_c` (143/143), `test_verifier` (86/86), `test_nanopass` (242/242), `test_all_passes` (39/39), `test_pass_manager` (115/115) の全 625 アサーション／テストが 1 件のエラー・スキップもなく PASS すること。
3. **Pass Fusion 性能ベンチマークの定量実証**:
   - `--time-passes` プロファイル結果において、融合パス（`pass-030-desugar`, `pass-050-cp0`, `pass-133-lir-peephole`）の実行時間およびヒープ消費量が計測され、中間表現走査オーバーヘッド削減が数値で実証されていること。
4. **仕様書・設計書への恒久記録**:
   - `DSN-33-01` 第 4.5 節および `ulisp/docs/spec_pipeline.md` に実測データが反映されていること。
5. **リポジトリ品質ゲート 100% 適合**:
   - `make py_compile && make static_analysis` が 0 エラーで合格すること。
   - すべての Markdown ファイル内のリンクが相対パス規約に厳格に従っていること（絶対パス 0 件）。

---

## 8. 検証プロトコル / Verification Protocol

```bash
# 1. S式構文およびバンドルの整合性検証
make -C ulisp lint_sexpr
make -C ulisp compiler.scm

# 2. 3-Stage セルフホスティング不動点検証
bash ulisp/bootstrap.sh --modular

# 3. 包括テストスイート実行
make -C ulisp test_c
make -C ulisp test_verifier
make -C ulisp test_nanopass
make -C ulisp test_all_passes
make -C ulisp test_pass_manager

# 4. パス実行時間・ヒープ消費プロファイル計測
make -C ulisp test_profiler

# 5. リポジトリ品質ゲート検証
make py_compile && make static_analysis
```
