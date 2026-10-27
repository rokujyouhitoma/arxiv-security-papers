---
ID: 621
種別: Feature
優先度: High
ステータス: Closed (Completed)
---

# [FEAT/ENH] コンパイラ Nanopass 実行時間・メモリ消費プロファイラ（--time-passes）の実装 (ID: 621)

## 1. 概要 / Summary
ULisp はフロントエンド（マクロ展開・脱糖・解析）、LIR（最適化・SSA・ピープホール）、バックエンド（コード生成）にわたり 30 以上の独立した Nanopass で構成されている。現在、全体のコンパイル所要時間は外部コマンド（`time` 等）で計測できるものの、各 Nanopass がどれだけの時間（ミリ秒/マイクロ秒）とメモリ（ヒープ cons アロケーション・アリーナ消費バイト数）を消費しているかの詳細な内訳を観測する機能が存在しない。

本 Issue では、コンパイラドライバおよび Pass Manager に `--time-passes`（または環境変数 `ULISP_BENCH_PASSES=1` / S式ディレクティブ `(!time-passes)`）オプションを本格実装する。これにより、各パスの実行時間、割合（%）、累積時間、およびメモリ消費量を整形テーブル形式で標準エラー出力へ表示可能にし、コンパイル速度のボトルネック特定と Pass 融合（Pass Fusion）の定量的指針を提供する。

---

## 2. ガバナンス・専門エージェント多角レビュー / Governance & Reviews

本 Issue は、16 専門エージェントフレームワークに基づき、以下の重点専門領域からの設計レビューを統合して策定された。

- **IT Specialist (Programming Languages & Compilers / PLC)**:
  - LLVM の `-ftime-report` / GCC の `-ftime-report` に相当する階層的 Nanopass プロファイラ仕様を策定。
  - フロントエンド、LIR 中間最適化、バックエンド（Pass 140/150/160）を同一の測定フレームワーク下で均一にプロファイリングするフック機構を設計。
  - 計測自体のオーバーヘッド（測定プローブの歪み）を最小化するため、無効時はゼロコスト（フラグ1個の短絡評価）とし、有効時も高精度タイマー・ヒープポインタ差分取得のみの軽量設計を規定。
- **Systems Architect**:
  - `ulisp/compiler/pass_manager.scm`（パス統御）および `ulisp/compiler/driver.scm`（CLI・環境変数ハンドリング）に責務を分離。
  - セルフホスティング環境（ゼロ libc フリースタンディング x86-64 ネイティブバイナリ）とブートストラップ環境（Gauche / Chibi / ILisp）双方で破綻なく動作する高精度タイマーフォールバック基盤を構築。
- **Software Quality Assurance Specialist (SQA)**:
  - `--time-passes` 有効時と無効時で、コンパイル結果の生成バイナリ・AST（アセンブリコード）がビット単位で完全一致（Differential Equivalence）することを検証条件に指定。
  - プロファイラ出力のパース整合性、合計時間と各パス合計の誤差（< 5%）、および回帰防止テスト（`test_pass_profiler.sh`）を策定。
- **Information Security Specialist**:
  - タイマー取得および環境変数パースにおける権限昇格・メモリ破壊・境界外読み取り脆弱性（CWE-125/CWE-787）の混入防止を検証。
  - プロファイル情報の出力先を標準エラー出力（fd 2）に限定し、パイプラインの後続ツール（アセンブラ等）への標準出力混入（CWE-209）を防止。
- **Project Manager (PM)**:
  - Issue 620（ベンチマークスイート修復）および Issue 623（正典性能ベースライン測定）との依存関係を整理し、Nanopass 単位のボトルネック特定を先行完了させる開発ロードマップを承認。

---

## 3. トレーサビリティ / Traceability
- **正典仕様書**:
  - [DSN-33 (ULisp 包括設計仕様書)](../designs/DSN-33-ulisp_underlying_x86_native_aot_compiler_architecture_specification.md) (第 2 章 パイプライン設計、第 8 章 観測性仕様)
  - [ULisp パイプライン・Nanopass 詳細仕様書](../../ulisp/docs/spec_pipeline.md)
  - [ULisp R7RS 準拠状況リファレンス](../../ulisp/docs/ref_r7rs_compliance.md)
- **関連 Issue**:
  - Issue #586: [Nanopass Framework DSL Phase 4: パイプライン統御・AST Diff トレーサの実装](closed/586-nanopass-framework-phase4-pipeline-observability-diff-trace-and-verifier-hooks.md)
  - Issue #590: [ULisp コンパイラ層の物理分離（Frontend/Nanopass メタコンパイラ層と Backend/低レベルコード生成層の分離）](closed/590-physical-layer-separation-of-frontend-and-backend.md)
  - Issue #598: [統一 Pass Manager の導入によるパイプライン制御・最適化レベルスケジューリングの一元化](closed/598-implement-unified-compiler-pass-manager.md)
  - Issue #608: [Nanopass・モジュール単位の完全分割コンパイル（.o）および増分ビルド基盤の実装](closed/608-implement-modular-separate-compilation-and-incremental-build.md)
  - Issue #620: [ベンチマークスイートの修復および make bench 自動計測ハーネスの確立](closed/620-repair-benchmark-suite-and-establish-automated-bench-harness.md)
  - Issue #622: [実行時 GC 統計プロファイル（ULISP_GC_STATS）および Linux perf ハードウェアカウンタ連携基盤の実装](622-implement-runtime-gc-stats-and-perf-hardware-counter-integration.md)
  - Issue #623: [ULisp 正典性能ベースライン測定レポート（BASELINE.md）の策定](623-establish-canonical-performance-baseline-and-continuous-monitoring.md)

---

## 4. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [ulisp/compiler/pass_manager.scm](../../ulisp/compiler/pass_manager.scm) (高精度タイマー・ヒープアロケーション差分計測・プロファイリング状態管理・レポート整形出力)
- [x] [ulisp/compiler/driver.scm](../../ulisp/compiler/driver.scm) (`--time-passes`, `ULISP_BENCH_PASSES` の受付、バックエンドコード生成パスの計測包含、最終レポート呼出し)
- [x] [ulisp/lib/posix.scm](../../ulisp/lib/posix.scm) (Linux x86-64 syscall 228 `sys_clock_gettime` による高精度モノトニックタイマー手続き)
- [x] [ulisp/lib/port.scm](../../ulisp/lib/port.scm) (*stderr-port* および標準エラー出力ルーチン)
- [x] [ulisp/lib/gc.scm](../../ulisp/lib/gc.scm) (gc-current-heap-bytes ヒープポインタ取得)
- [x] [ulisp/compiler/helpers.scm](../../ulisp/compiler/helpers.scm) (フォールバック定義およびエラーポート解決)
- [x] [ulisp/tests/test_pass_profiler.sh](../../ulisp/tests/test_pass_profiler.sh) (新規: `--time-passes` および `ULISP_BENCH_PASSES=1` 動作・出力整合性検証テスト)
- [x] [ulisp/Makefile](../../ulisp/Makefile) (`test_profiler` ターゲットの追加および `test` スイートへの組み込み)
- [x] [docs/issues/621-implement-compiler-pass-timing-and-memory-profiler.md](621-implement-compiler-pass-timing-and-memory-profiler.md) (本仕様書)
- [x] [docs/issues/README.md](README.md) (Issue 台帳のステータス更新)

---

## 5. 脅威分析とセキュリティ要件 / Threat Modeling & Security Requirements

コンパイラプロファイラの実装に伴う新たなシステムコール呼出し、環境変数読み取り、および標準エラー出力制御に関して、STRIDE / CWE 観点での脅威分析を実施する。

| 脅威分類 (STRIDE / CWE) | 脅威シナリオ | 影響度 | 対策要件 (Mitigation Requirements) |
| :--- | :--- | :---: | :--- |
| **情報漏洩 / 意図しない出力混入 (CWE-209 / CWE-532)** | プロファイル結果が標準出力（stdout）に出力され、`ulisp < src.scm > out.s` でアセンブラにゴミデータが渡りビルドが破壊される。 | High | プロファイル結果は必ず標準エラー出力（fd 2 または `*stderr-port*`）へのみ出力する。標準出力への影響を厳密に遮断する。 |
| **境界外メモリ破壊 (CWE-125 / CWE-787)** | Linux syscall 228 (`sys_clock_gettime`) に渡す `struct timespec` 用バッファがスタック/ヒープ境界外を指し、SEGV またはメモリ破壊が発生する。 | Critical | 16 バイト固定の静的整列セル（cons cell または専用メモリ領域）を事前確保し、安全なアンタグドポインタ渡しを徹底する。 |
| **サービス拒否 / 整数オーバーフロー (CWE-190 / DoS)** | マイクロ秒・ナノ秒単位の累積時間計算において 64 ビット符号付き整数のオーバーフローが発生し、負の時間や無限ループが発生する。 | Medium | 秒数とナノ秒数を分離して正規化加算を行い、マイクロ秒（μs）およびミリ秒（ms）への換算時に除算・剰余を安全に処理する。 |
| **環境変数不正解釈 (CWE-20)** | 悪意ある環境変数 `ULISP_BENCH_PASSES` に巨大な文字列や特殊文字が設定された場合にバッファオーバーランが発生する。 | Low | 単一文字プレフィックス比較（`=1` / `'t'` / `'y'`）のみを安全に判定し、不正な値は無視して安全側に倒す。 |

---

## 6. 実装方針 / Implementation Plan
Target Branch: `feat/621-implement-compiler-pass-timing-and-memory-profiler`

### 6.1 高精度モノトニックタイマーとメモリ計測機構
1. **Linux x86-64 高精度タイマー (`sys_clock_gettime`)**:
   - `CLOCK_MONOTONIC` (= 1) を引数とする syscall 228 を利用。
   - `struct timespec`（16バイト: `tv_sec` 8バイト, `tv_nsec` 8バイト）の格納領域として、`*timespec-buf-cell*` を確保。
   - マイクロ秒単位の整数値を返す `(current-time-monotonic-us)` を実装。
   - ブートストラップ環境（Gauche / Chibi / ILisp）では `(current-jiffy)` / `(jiffies-per-second)` または `(sys-gettimeofday)` へ自動フォールバック。
2. **ヒープアロケーション計測 (`current-heap-alloc-bytes`)**:
   - ネイティブ実行時: `ulisp_gc_state` の free_ptr オフセットまたはアロケーションカウンタから現在消費バイト数を取得。
   - 各パス実行前後の差分 `(- bytes1 bytes0)` を計算し、パス固有の cons/メモリ消費量（KB）として記録。

### 6.2 Pass Manager フックとバックエンド計測の統合
1. **プロファイリング状態データ構造**:
   - パスごとに以下の 4 要素レコードを記録：
     `(list pass-id pass-name elapsed-us alloc-bytes)`
2. **`run-single-pass` の拡張**:
   - `(pipeline-time-passes?)` が有効な場合、各パス実行直前と直後にタイマーおよびヒープポインタを取得し、累積時間・メモリ消費量を記録。
3. **バックエンドパス（Pass 140/150/160）の包含**:
   - 現在 `compile-backend` が `run-pass-pipeline` の外側で直接実行されているため、バックエンドコード生成も `pass-140-backend` として同一プロファイラに記録した上で、全体の最終段階でレポートを出力するようにリファクタリング。

### 6.3 整形レポート出力 (`print-pass-timing-report`)
1. **出力フォーマット**:
   標準エラー出力に以下の形式で整列表示：
   ```text
   ========================================================================================
   ULisp Nanopass Execution Profile (--time-passes)
   ========================================================================================
   Pass ID                  Pass Name                     Time (ms)  Share (%)  Heap (KB)
   ----------------------------------------------------------------------------------------
   pass-010-library         Desugar Libraries & Imports     0.18 ms       3.2%       24 KB
   pass-015-dsl-expander    DSL Expander                    0.35 ms       6.2%       48 KB
   pass-020-macro-expander  Hygienic Macro Expander         1.25 ms      22.1%      192 KB
   pass-030-desugar         Core Desugar All                0.42 ms       7.4%       64 KB
   pass-070-anf             A-Normal Form Conversion        0.65 ms      11.5%       96 KB
   pass-110-closure-convert Closure Conversion              0.80 ms      14.1%      128 KB
   pass-130-lir             LIR Lowering and Generation     0.95 ms      16.8%      160 KB
   pass-133-lir-peephole    LIR Peephole Optimization       0.32 ms       5.7%       32 KB
   pass-140-backend-x86-64  x86-64 Machine Code Emission    0.74 ms      13.1%       80 KB
   ----------------------------------------------------------------------------------------
   Total Compilation Time : 5.66 ms
   Total Heap Allocation  : 824 KB
   ========================================================================================
   ```
2. **安全なフォーマッタ**:
   - 小数点以下2桁（`ms`）および1桁（`%`）の固定長パディング文字列化関数を純粋 Scheme で実装（外部ライブラリ非依存）。

### 6.4 CLI & 環境変数ディレクティブ
1. **有効化トリガー**:
   - CLI 引数: `--time-passes`
   - S 式ディレクティブ: `(!time-passes)`
   - 環境変数: `ULISP_BENCH_PASSES=1`
2. **無効時のオーバーヘッドゼロ**:
   - 単一のグローバル真偽値チェックのみでパススルーし、非プロファイル時のコンパイル性能への影響を完全に排除。

---

## 7. 完了条件 / Success Criteria (DoD)
- [x] `--time-passes`、`(!time-passes)`、または `ULISP_BENCH_PASSES=1` 指定時に、全 Nanopass の時間・メモリ消費テーブルが標準エラー出力に出力されること。
- [x] プロファイル出力が標準エラー出力（stderr）にのみ出力され、標準出力（stdout）のアセンブリコード生成結果を一切汚染しないこと。
- [x] バックエンドコード生成（x86-64 / C / AArch64）の所要時間がテーブル内に明示的に計測・表示されること。
- [x] 通常コンパイル時（フラグなし）にプロファイリング処理が完全にスキップされ、オーバーヘッドがゼロであること。
- [x] `ulisp/tests/test_pass_profiler.sh` が追加され、`make test` または `make test_profiler` で自動検証に 100% 合格すること。
- [x] 生成コードのバイナリ等価性（フラグ有無で生成される .s / .o が同一であること）が保証されること。
