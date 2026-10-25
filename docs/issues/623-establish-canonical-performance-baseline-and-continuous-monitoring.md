---
ID: 623
種別: Feature
優先度: Medium
ステータス: Open (New)
---

# [FEAT/ENH] ULisp 正典性能ベースライン測定レポート（BASELINE.md）の策定と継続的性能監視基盤の構築 (ID: 623)

## 1. 概要 / Summary
Issue 620（ハーネス修復）、Issue 621（Pass 所要時間プロファイラ）、および Issue 622（GC/perf 統計）の成果を統合し、最適化施策を着手する前の「公式ベースライン数値（Canonical Baseline Metrics）」を確定・記録する。

主要 6 大ワークロードについて、ULisp（x86-64 ネイティブ）、GCC -O2（C 言語）、および主要 Scheme 処理系（Chez Scheme / Gauche 等）の実測値を多角的に収集し、`ulisp/benchmarks/BASELINE.md` に正式記録する。さらに、今後の機能追加や最適化によって予期せぬ性能低下（Performance Regression）が生じていないかを CI やテストスイート（`make bench_verify`）で自動検知できる監視基盤を構築する。

---

## 2. トレーサビリティ / Traceability
- **正典仕様書**:
  - [DSN-33 (ULisp 包括設計仕様書)](../../docs/designs/DSN-33-ulisp_underlying_x86_native_aot_compiler_architecture_specification.md) (第 10 章 品質ゲート・テスト自動化)
  - [ULisp ベンチマークレポート](../../ulisp/benchmarks/README.md)
- **関連 Issue**:
  - Issue 618: S-RTyper（Pass 090）および LIR / バックエンドにおける関数間アンボックス特化とタグオーバーヘッド撲滅
  - Issue 620: ベンチマークスイートの修復および make bench 自動計測ハーネスの確立
  - Issue 621: コンパイラ Nanopass 実行時間・メモリ消費プロファイラ（--time-passes）の実装
  - Issue 622: 実行時 GC 統計プロファイルおよび Linux perf ハードウェアカウンタ連携基盤の実装

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [ulisp/benchmarks/BASELINE.md](../../ulisp/benchmarks/BASELINE.md) (新規: 正典ベースライン測定結果およびシステム環境詳細)
- [ ] [ulisp/benchmarks/verify_regression.py](../../ulisp/benchmarks/verify_regression.py) (新規: ベースラインとの比較・回帰検知スクリプト)
- [ ] [ulisp/Makefile](../../ulisp/Makefile) (`bench_baseline`, `bench_verify` ターゲットの追加)
- [ ] [ulisp/benchmarks/README.md](../../ulisp/benchmarks/README.md) (ベースライン参照リンクと更新プロトコルの記載)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/623-establish-canonical-performance-baseline-and-continuous-monitoring`

1. **ベースライン測定の実施**:
   - Issue 620〜622 のツール群を用いて、環境（CPU 型番、クロック、OS カーネル、メモリ）を明記した上で 30 回試行の安定データを採取。
   - 収集項目:
     - コンパイル時間（総時間および Pass 別内訳）
     - バイナリサイズ（.text, .data, .bss）
     - 実行時間（平均、中央値、標準偏差）
     - GC 停止時間・総回収回数・割り当てメモリ量
     - ハードウェア性能指標（IPC、分岐ミス率、キャッシュミス率）
2. **正典ドキュメント `BASELINE.md` の作成**:
   - 上記データを構造化 Markdown 表形式および Mermaid グラフで `ulisp/benchmarks/BASELINE.md` に記述。
3. **性能回帰自動検知スクリプト（`verify_regression.py`）の実装**:
   - `make bench_verify` を実行した際、最新の測定値が `BASELINE.md` の数値から有意（例: 10% 以上）に悪化していないかを自動判定。
   - 悪化が検知された場合はエラーコードでビルドを停止し、ボトルネックの Nanopass や関数をアラート表示。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] `ulisp/benchmarks/BASELINE.md` が完全な実測値とともに作成・コミットされていること。
- [ ] `make bench_baseline` でベースラインの再記録、`make bench_verify` で回帰検知が動作すること。
- [ ] 以降の最適化（Issue 618 など）において、改善率をベースラインとの対比（例:「1.35倍高速化」）で客観的に証明できる状態になっていること。
