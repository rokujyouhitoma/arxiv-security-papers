---
ID: 903
種別: Feature
優先度: Medium
ステータス: Closed (Completed)
---

# [FEAT/ENH] Implement Performance Regression Detector and Automated Markdown Reporting (ID: 903)

## 1. 概要 / Summary

[[DSN-33-06]](../designs/DSN-33-06-ulisp_ilisp_aot_jit_continuous_benchmarking_framework.md) 第 4 章および [[DSN-10]](../designs/DSN-10-observability_and_eval_framework.md) に基づき、過去のベースライン測定値と新規測定値を統計的に比較して 5% 以上の性能退行（パフォーマンスリグレッション）を自動検知する統計的判定器（`tools/regression_detector.py`）、および時系列トレンド可視化表を含む完全日本語エグゼクティブサマリー `outputs/benchmarks/benchmark_report.md` を自動生成するパイプライン（`tools/report_benchmarks.py`）を実装する。

本基盤により、ULisp コンパイラや JIT エンジンの機能拡張、リファクタリング、最適化パス追加時における微細な性能低下や分岐予測悪化を客観的・統計的有意差（ウェルチの t 検定）をもって自動捕捉し、CI/CD パイプラインで確実にブロック・可視化できる品質ゲートを確立する。

---

## 2. トレーサビリティ / Traceability

- 関連設計書:
  - [[DSN-33-06] ILisp・ULisp AOT・ULisp JIT 3種実行系 継続的性能評価基盤 設計仕様書 (第4章)](../designs/DSN-33-06-ulisp_ilisp_aot_jit_continuous_benchmarking_framework.md)
  - [[DSN-10] 可観測性 ＆ 情報検索評価包括フレームワーク設計書 (第4章・第5章)](../designs/DSN-10-observability_and_eval_framework.md)
  - [[DSN-33] ULISP 包括設計仕様書](../designs/DSN-33-ulisp_underlying_x86_native_aot_compiler_architecture_specification.md)
- 先行 Issue:
  - [Issue #902: 3種実行系（ILisp / AOT / JIT）自動ベンチマークハーネスおよび Mytkowicz バイアス排除の実装](closed/902-implement-automated-continuous-benchmarking-harness-and-mytkowicz-bias-elimination.md)
- 後続 Issue:
  - [Issue #904: 外部 C ランタイム完全排除と Pure Scheme _start エントリポイント・Raw Syscall 直結](904-eliminate-external-c-runtime-and-establish-pure-scheme-start-entry.md)

---

## 3. 脅威モデルとセキュリティ要件 (Threat Model & Security Requirements)

| 脅威 ID | 分類 (STRIDE) | 脆弱性・リスク事象 | 対策方針・緩和策 |
| :--- | :--- | :--- | :--- |
| **TM-903-01** | Tampering | 入出力パス指定（`--baseline`, `--candidate`, `--markdown-out`, `--json-out`）におけるパストラバーサル（CWE-22 / CWE-73） | すべてのファイルパス入力を `Path.resolve()` で検証し、リポジトリルート外へのファイルアクセスおよび不正書き込みを遮断するバリデータを実装。 |
| **TM-903-02** | Denial of Service (DoS) | 履歴 JSON 走査時の過大ファイル読み込みによるメモリ枯渇および処理遅延（CWE-400） | `outputs/benchmarks/history/` 読み込み時に走査件数の上限（デフォルト最新 20 件）を設け、各ファイルの最大サイズ制限（1MB）をチェックする。 |
| **TM-903-03** | Information Disclosure | 自動生成 Markdown レポートや JSON エクスポートにおける内部環境情報・機密ホスト名の漏洩（CWE-532） | ユーザー名、特定ホームディレクトリパス、機密環境変数をサニタイズし、アーキテクチャ・OS・Python バージョン等の無害なメタデータのみを出力。絶対パスを徹底排除。 |
| **TM-903-04** | Denial of Service (DoS) | ゼロ除算・浮動小数点例外による検定器クラッシュ（CWE-369） | 実行時間 0.0ms や標本分散 0 のエッジケースにおいて、ゼロ除算保護（イプシロン加算または早期分岐）を配置し安全にハンドリング。 |

---

## 4. 影響範囲と関連ファイル / Scope and Affected Files

### 新規作成ファイル
- [`tools/regression_detector.py`](../../tools/regression_detector.py)
  - ウェルチの t 検定（Welch's t-test）を用いた統計的有意差判定および 5% 性能退行自動検知 CLI / ライブラリ。
- [`tools/report_benchmarks.py`](../../tools/report_benchmarks.py)
  - 履歴スナップショット集約、トレンド可視化表、Mermaid 構成図を含む日本語エグゼクティブサマリー自動生成ツール。
- [`tests/test_benchmark_reporter.py`](../../tests/test_benchmark_reporter.py)
  - 退行検知数理ロジック、異常系、レポート生成、CWE-22 パストラバーサル防止の包括的テストスイート。

### 修正対象ファイル
- [`tools/benchmark_ilisp_ulisp.py`](../../tools/benchmark_ilisp_ulisp.py)
  - 各反復の生サンプル（`raw_samples_ms`）を JSON 結果に追加し、統計的仮説検定の標本データとして提供。
- [`Makefile`](../../Makefile)
  - `bench_ci` ターゲットにおいて、従来の固定倍率比較から `tools/regression_detector.py` を用いた統計的 5% 閾値判定へ刷新。
- [`outputs/benchmarks/benchmark_report.md`](../../outputs/benchmarks/benchmark_report.md)
  - 最新フォーマットによる自動生成レポートの更新。

---

## 5. 詳細実装方針 / Detailed Implementation Plan

Target Branch: `feat/903-implement-performance-regression-detector-and-automated-markdown-reporting`

### 5.1 統計的性能退行検知エンジン (`tools/regression_detector.py`)
1. **数理モデル（ウェルチの t 検定 / Welch's t-test）**:
   - 2 つの標本群 $X_1$（ベースライン）と $X_2$（候補ラン）について、等分散性を仮定しない t 統計量を算出：
     $$t = \frac{\bar{X}_2 - \bar{X}_1}{\sqrt{\frac{s_1^2}{N_1} + \frac{s_2^2}{N_2}}}$$
   - 自由度（Welch–Satterthwaite の式）：
     $$\nu \approx \frac{\left(\frac{s_1^2}{N_1} + \frac{s_2^2}{N_2}\right)^2}{\frac{(s_1^2 / N_1)^2}{N_1 - 1} + \frac{(s_2^2 / N_2)^2}{N_2 - 1}}$$
   - Pure Python 標準ライブラリ（`math` モジュール）のみで動作する p 値近似（正規近似および t 分布の裾確率評価）を実装（Zero External Dependency 原則）。
2. **判定基準**:
   - 相対悪化率 $\Delta = \frac{\bar{X}_2 - \bar{X}_1}{\bar{X}_1} \ge 0.05$（5% 以上のレイテンシ増大）。
   - 統計的有意水準: $p < 0.05$（偶然のノイズによる見かけ上の変動を排除）。
   - 標本数が少ない（または反復が単一）場合のフォールバックとして、Mean 比率閾値判定をサポート。
3. **CLI インターフェースと終了コード**:
   - `--baseline <path>`: 比較元 JSON（デフォルト: `outputs/benchmarks/latest.json`）。
   - `--candidate <path>`: 比較対象 JSON。
   - `--threshold <float>`: 退行許容閾値比率（デフォルト: `0.05` = 5%）。
   - `--p-value <float>`: 有意水準（デフォルト: `0.05`）。
   - `--json-out <path>`: 検定結果構造化レポートの保存先。
   - 終了コード:
     - `0`: 退行なし（PASS）
     - `1`: 5% 以上の統計的有意な性能退行を検知（FAIL / CI ブロック）
     - `2`: 引数エラー、ファイル不存在、またはフォーマット異常

### 5.2 自動 Markdown レポート生成エンジン (`tools/report_benchmarks.py`)
1. **100% 日本語完全マークダウン表形式**:
   - システム環境メタデータ（OS, CPU, Python バージョン, 日時）。
   - 3 種実行系（ILisp, ULisp AOT, ULisp JIT）の最新ベンチマーク結果要約表（平均時間 ± 標準偏差、ILisp 比加速倍率、戻り値整合性）。
   - 統計的退行検知サマリー（ベースラインとの差異、Welch's t-test p値、ステータス判定）。
2. **時系列トレンド推移表（Historical Trend Table）**:
   - `outputs/benchmarks/history/` から直近 5〜10 回の実行データを収集し、ワークロードごとの平均所要時間推移をマークダウン表形式で一覧化。
3. **Mytkowicz ハードウェアカウンタ解析**:
   - `perf stat` 取得時の動的命令数（instructions）、分岐ミス（branch-misses）、サイクル数（cycles）の比較表を掲載。
4. **Mermaid 構成図**:
   - 実行時間比較またはアーキテクチャ階層図を Mermaid ブロックとして埋め込み。
5. **相対パス規則の厳格徹底**:
   - 出力 Markdown 内のすべてのリンク・参照において絶対パス（`/workspace/...`, `/root/...`）を 0 件とし、相対パスのみを使用。

### 5.3 `tools/benchmark_ilisp_ulisp.py` 連携強化
1. 各測定ループで得られた全反復のミリ秒リストを `raw_samples_ms` として JSON 出力に保存。
2. これにより、後続の `tools/regression_detector.py` が完全な標本分散およびウェルチの t 検定を正確に計算可能にする。

### 5.4 `Makefile` への CI ゲート統合
- `make bench_ci` を更新し、ベンチマーク実行後に `tools/regression_detector.py` を呼び出して 5% 閾値での厳密判定を実行する。

---

## 6. 完了条件 / Success Criteria (DoD)

- [x] `tools/regression_detector.py` が実装され、ウェルチの t 検定による統計的有意差判定および 5% 性能退行検知が正常に動作すること。
- [x] 性能退行検知時に終了コード `1` で終了し、正常時に `0` で終了すること。
- [x] `tools/report_benchmarks.py` が実装され、`outputs/benchmarks/benchmark_report.md` を 100% 日本語かつ相対パスのみで生成すること。
- [x] `tools/benchmark_ilisp_ulisp.py` が `raw_samples_ms` を出力 JSON に記録すること。
- [x] `Makefile` の `bench_ci` ターゲットが更新され、統計的退行検知パイプラインと連動すること。
- [x] 単体テスト `tests/test_benchmark_reporter.py` を作成し、全テストケースが PASS すること。
- [x] CWE-22, CWE-73, CWE-400, CWE-532 に対するセキュリティバリデーションが機能していること。
- [x] `make py_compile && make static_analysis` がエラー 0 件で合格すること。

---

## 7. 検証手順 / Verification Steps

```bash
# 1. 単体テスト実行
pytest -v tests/test_benchmark_reporter.py

# 2. 統計的性能退行検知器の直接テスト (正常時)
python3 tools/regression_detector.py --baseline outputs/benchmarks/latest.json --candidate outputs/benchmarks/latest.json --threshold 0.05
# -> 終了コード 0 (PASS)

# 3. 意図的な退行データによる検知テスト
python3 -c "
import json
with open('outputs/benchmarks/latest.json') as f: d = json.load(f)
for r in d['results']: r['ulisp_aot']['mean_ms'] *= 1.2
with open('/tmp/regressed.json', 'w') as f: json.dump(d, f)
"
python3 tools/regression_detector.py --baseline outputs/benchmarks/latest.json --candidate /tmp/regressed.json --threshold 0.05
# -> 終了コード 1 (REGRESSION DETECTED)

# 4. 日本語レポート生成テスト
python3 tools/report_benchmarks.py --latest outputs/benchmarks/latest.json --history-dir outputs/benchmarks/history --output outputs/benchmarks/benchmark_report.md
grep -rnE '/workspace|/root' outputs/benchmarks/benchmark_report.md # -> 0件

# 5. CI ターゲットの実行
make bench_ci

# 6. 静的解析とコンパイル検証
make py_compile && make static_analysis
```
