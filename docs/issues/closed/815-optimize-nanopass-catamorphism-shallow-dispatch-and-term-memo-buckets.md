---
ID: 815
種別: Feature
優先度: High
ステータス: Closed
完了日: 2026-11-14
---

# [FEAT/ENH] nanopass-catamorphism-step の O(1) 浅層ディスパッチ化と *nanopass-term-memo* ハッシュバケット化によるコンパイル時間 90% 削減 (ID: 815)

## 1. 概要 / Summary
`ULISP_BENCH_PASSES=1`（`--time-passes`）を用いたパス別プロファイリングの結果、コンパイル時間の **90% 以上**が Nanopass フレームワークの共通自動走査エンジン `nanopass-catamorphism-step`（[ulisp/compiler/nanopass_meta.scm](../../../ulisp/compiler/nanopass_meta.scm)）およびその周辺キャッシュ処理の以下 4 つのボトルネックに集中していることが判明した：

- `compiler_base_in.scm` でのベースライン実測値（Total: `10,325.24 ms`, Heap: `1,164,394 KB`）：
  - `pass-030-desugar`: `1,263.86 ms` (12.2%)
  - `pass-050-cp0`: `6,265.15 ms` (60.6% / `207,148 KB`、小規模入力比で実行時間 **33.5 倍**の $O(N^2)$ スケーリング)
  - `pass-100-contify`: `1,813.92 ms` (17.5% / `43,426 KB`)
  - 上記 3 パスのみでコンパイル時間全体の **90.3%（9.34 秒 / 10.33 秒）** を占有している。

### 根本原因の特定
1. **毎ノードでのサブツリー再帰全検証 ($O(N \cdot D)$ 〜 $O(2^D)$)**：
   - `nanopass-catamorphism-step`（`nanopass_meta.scm:1833-1890`、特に 1887 行目）および `nanopass-schema-transform-node`（`nanopass_meta.scm:1641-1667`）/ `nanopass-schema-transform-subpattern`（`nanopass_meta.scm:1544-1607`）がノード通過ごとに `nanopass-find-matching-production`（`nanopass_meta.scm:1508-1533`）を呼び出している。
   - 内部の `nanopass-production-matches?`（`nanopass_meta.scm:401-428`）が子孫ノードに対して `nanopass-check-valid-node` を葉まで再帰的に実行するため、AST の深さ $D$ に対して毎回全サブツリーを再検査し、さらに `(if e0 e1)` vs `(if e0 e1 e2)` 等の複数生成規則でバックトラックが発生している。
2. **`*nanopass-term-memo*` の単一フラット alist 線形探索 ($O(N^2)$)**：
   - `run-single-pass`（`pass_manager.scm:595-640`、特に 601 行目）が全パス実行を `with-nanopass-term-memo`（`nanopass_meta.scm:2418-2430`）でラップしているが、`*nanopass-term-memo*`（`nanopass_meta.scm:1874-1884`, `2389-2447`）が単一のフラットな連想リストであり、数万ノードごとに `assq` の $O(N)$ 線形走査（全体で $O(N^2)$）および `(length (car *nanopass-term-memo*))` 計測を発生させている。
3. **`nanopass-classify-meta-var` のキャッシュ参照前 `symbol->raw-name` 呼び出し**：
   - `nanopass-classify-meta-var`（`nanopass_meta.scm:111-130`）が `*classify-meta-var-cache*` を引く前に毎回 `(symbol->raw-name var)` と `(symbol->raw-name lang-name)` および `string-fast-hash-1024` を呼んでおり、キャッシュヒット時にも文字列変換・ハッシュ計算コストが課されている。
4. **`*femto-analysis-cache*` のパス境界越え残存**：
   - `run-pass-pipeline`（`pass_manager.scm:646`）の開始時のみ `(femto-cache-reset!)` を呼び出しており、`run-single-pass` 完了時にリセットされないため、上流パスで蓄積された `*femto-analysis-cache*` に対して下流パス（`133_lir_peephole` 等）の `record-picopass-firing!`（`nanopass_meta.scm:619-645`）が毎回 `femto-cache-invalidate-node!` / `femto-cache-invalidate-tags!` を実行してしまう。

---

## 2. トレーサビリティ / Traceability
- [DSN-33-01 Nanopass/Picopass DAG アーキテクチャ仕様書](../../designs/DSN-33-01-ulisp_pipeline_pass_nanopass_picopass_dag_architecture.md)
- 関連 Issue:
  - [Issue #766 (Hash-Consing Term DAG とメモ化 Catamorphism)](766-implement-hash-consing-term-dag-and-memoized-catamorphism.md)
  - [Issue #813 (fuse-rules :order post と Femtopass キャッシュ接続)](813-implement-fuse-rules-post-order-and-connect-femtopass-cache.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [ulisp/compiler/helpers.scm](../../../ulisp/compiler/helpers.scm)
  - AOT 環境における `*aot-fast-sym-hash?*` 判定および `symbol->raw-name` / `symbol->hash-idx` の高速バケット・整数演算パス追加
- [x] [ulisp/compiler/nanopass_meta.scm](../../../ulisp/compiler/nanopass_meta.scm)
  - 浅層 1-level 生成規則マッチャ (`nanopass-find-matching-production-shallow`, `nanopass-production-matches-shallow?`, `nanopass-match-subforms-shallow`, `nanopass-match-subpattern-shallow`, `nanopass-check-shallow-node`) の導入と `nanopass-catamorphism-step` / `nanopass-schema-transform-node` / `nanopass-schema-transform-subpattern` / `nanopass-schema-analyze-node` への接続
  - `nanopass-catamorphism-step` 先頭のアトミックノード早期リターン化および単一引数メモ化 `nanopass-memoize-step` 統合
  - `*nanopass-term-memo*` の 256 バケットベクタハッシュテーブル化 (`nanopass-make-term-memo-table`)・2 階層構造ハッシュ (`nanopass-atom-hash`, `nanopass-term-memo-bucket-idx`)・バケット深度上限 (max 16: `*nanopass-term-memo-bucket-limit*`)・$O(1)$ エントリ数カウンタ導入
  - `nanopass-classify-meta-var` の `symbol->hash-idx` ベース高速キャッシュ参照化
- [x] [ulisp/compiler/pass_manager.scm](../../../ulisp/compiler/pass_manager.scm)
  - `run-single-pass` 完了時および例外脱出時の `(femto-cache-reset!)` 呼び出し追加
- [x] [ulisp/frontend/050_cp0.scm](../../../ulisp/frontend/050_cp0.scm)
  - `cp0-has-dead-let-binding?` において `pure-expr?` 判定による事前スキップを追加し、`free-vars` 不要走査を削減
- [x] [ulisp/tests/test_nanopass_framework.scm](../../../ulisp/tests/test_nanopass_framework.scm)
  - Section 25 追加: 浅層ディスパッチの生成規則選択精度（2引数/3引数 `if`, `let`, `quote`, 関数適用、未脱糖子式に対する浅層/深層差異）、256 バケット `*nanopass-term-memo*` 統計/衝突時上限 (16)、および `nanopass-classify-meta-var` キャッシュ一貫性テスト
- [x] [ulisp/compiler.scm](../../../ulisp/compiler.scm) / [ulisp/bin/ulisp-boot](../../../ulisp/bin/ulisp-boot)
  - 統合コンパイラソースおよび 3-Stage 固定点検証済みセルフホスティングシードバイナリの再生成・更新

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/815-optimize-nanopass-catamorphism-shallow-dispatch-and-term-memo-buckets`

### 4.1 浅層 1-level 生成規則マッチャの導入 (`ulisp/compiler/nanopass_meta.scm`)
- **現状箇所**: `nanopass-production-matches?` (`401-428`), `nanopass-find-matching-production` (`1508-1533`), `nanopass-schema-transform-subpattern` (`1544-1607`), `nanopass-schema-transform-node` (`1641-1667`), `nanopass-catamorphism-step` (`1833-1890`)。
- **実装内容**:
  1. `nanopass-production-matches-shallow?`, `nanopass-match-subforms-shallow`, `nanopass-find-matching-production-shallow` を実装する。
  2. 浅層マッチャは `nanopass-check-valid-node` による子孫ノードへの再帰検証を行わず、以下を **1 階層（および直下の構造コンテナ）のみ** $O(1)$ で判定する：
     - 生成規則がシンボルの場合：終端述語（`nanopass-terminal-matches?`）または言語非終端の浅層ヘッド判定（子式の中身へは再帰しない）。
     - 生成規則がペア `(head . prod-rest)` の場合：
       - `head` が `'quote`：`(and (pair? expr) (eq? (car expr) 'quote) (pair? (cdr expr)) (null? (cddr expr)))` を検査。
       - `head` がキーワード（メタ変数でないシンボル）：`(eq? head (car expr))` に加え、`nanopass-match-subforms-shallow` で要素数・`...` 省略記号対応および直下の構造ペア（例：`let` の `((x e) ...)` バインディングペア形式、`lambda`/`%cont-fun` の仮引数リスト、2引数 `(if e0 e1)` vs 3引数 `(if e0 e1 e2)` のアリティ等）を子式の内部へ降りずに検査する。
       - `head` がメタ変数（例：`(e0 e1 ...)` 形式の関数適用）：`(and (not (memq (car expr) (nanopass-lang-keywords lang))) (nanopass-proper-list? expr))` 等でキーワード適用と区別し、アリティ・`...` 構造のみ検査する。
  3. `nanopass-catamorphism-step`（`1852` / `1887` 行目）および `nanopass-schema-transform-node` / `nanopass-schema-transform-subpattern` の走査ディスパッチを `nanopass-find-matching-production-shallow` に切り替える（明示的バリデータ `nanopass-valid?` / `nanopass-check-valid-node` の完全検証セマンティクスは破壊せず維持する）。

### 4.2 `*nanopass-term-memo*` の 256 バケットベクタハッシュテーブル化 (`ulisp/compiler/nanopass_meta.scm`)
- **現状箇所**: `nanopass-catamorphism-step` (`1867-1884`), `Section 14.2` (`2389-2447`)。
- **実装内容**:
  1. `*nanopass-term-memo*` を単一 alist から **256 バケットベクタ**（サイズ `256`、`(make-vector 256 '())`）と $O(1)$ エントリ数カウンタ `*nanopass-term-memo-entry-count*`（またはヘッダ構造）へ移行する。
  2. ノードごとのバケット索引関数 `nanopass-term-memo-bucket-idx`（2 階層構造ハッシュ）を導入する：`node` がペアの場合、`(car node)` および第 2 要素 `(if (pair? (cdr node)) (cadr node) ...)` のシンボル/整数/タグ種別から 2 階層の混合ハッシュ値 `(bitwise-and ... 255)` を計算し、同一先頭タグ（例：`let`, `call`, `if`）への偏りを分散させる。
  3. 最悪計算量 $O(1)$ を保証するため、1 バケットあたりの上限深度を **最大 16 エントリ** に制限する（上限到達時は末尾の古いエントリを追放するか当該バケットの登録をスキップ/差し替え、`50,000+` ノードの巨大 AST でもバケット走査が最大 16 回で打ち切られるようにする）。
  4. `nanopass-catamorphism-step` 内の重複したメモ化ブロック（`1874-1884`）と `nanopass-memoize-step`（`2432-2447`）を共通ヘルパへ統合する。
  5. `with-nanopass-term-memo`, `nanopass-term-memo-reset!`, `nanopass-term-memo-stats`（`((hits . N) (misses . M) (entries . K))` 形式）, `nanopass-term-memo-hit-rate` の公開 API と既存テスト（`test_nanopass_framework.scm` Section 23.2〜23.4）との 100% 互換性を維持する。

### 4.3 `nanopass-classify-meta-var` の `symbol->hash-idx` 高速パス (`ulisp/compiler/nanopass_meta.scm`)
- **現状箇所**: `nanopass-classify-meta-var`（`111-130` 行目）。
- **実装内容**:
  1. 関数冒頭で `(symbol->raw-name var)` および `(symbol->raw-name lang-name)` を計算する前に、プリミティブ `symbol->hash-idx` を用いて直接 1024 バケットインデックス `h` を算出する：
     - `(modulo (+ (symbol->hash-idx var) (* (symbol->hash-idx lang-name) 31)) 1024)`（またはビットマスク `bitwise-and ... 1023`）。
  2. 該当バケットを `(and (eq? (caar e) var) (eq? (cdar e) lang-name))` で検索し、**キャッシュヒット時は文字列変換を一切行わず即座に結果を返す**。
  3. キャッシュミス時（バケット空または不一致）のみ `(symbol->raw-name var)` を呼び出してプレフィックス/サフィックス解析を行い、バケットへ登録する。

### 4.4 パス境界での `*femto-analysis-cache*` リセット (`ulisp/compiler/pass_manager.scm`)
- **現状箇所**: `run-single-pass`（`595-640` 行目）。
- **実装内容**:
  1. `run-single-pass` 内のパス関数実行完了後（`with-nanopass-term-memo` 抜出直後、検証・戻り値返却前）に `(femto-cache-reset!)` を必ず呼び出す（例外的パス脱出時も含め、パスを跨いで古い `*femto-analysis-cache*` が残存しないようにする）。
  2. これにより、後続の `133_lir_peephole` 等における `record-picopass-firing!` が不要な `femto-cache-invalidate-node!` / `femto-cache-invalidate-tags!` 走査を実行しない状態を保証する。

### 4.5 ブートストラップおよび運用手順（Git / 品質ゲート）
1. Feature ブランチ `feat/815-optimize-nanopass-catamorphism-shallow-dispatch-and-term-memo-buckets` を作成する。
2. `ulisp/compiler/nanopass_meta.scm`、`ulisp/compiler/pass_manager.scm`、`ulisp/tests/test_nanopass_framework.scm` を実装・テスト追加する。
3. 既存 Stage 0 シード (`bin/ulisp-boot`) で `make -C ulisp test_nanopass test_passes test_pass_manager compiler lint_sexpr` を検証後、更新したコンパイラで新シードをビルドし、`make -C ulisp bootstrap_verify`（Stage 2 == Stage 3 ビット単位一致）を通過させ、必要に応じて `bin/ulisp-boot` を更新する。
4. `env ULISP_GC_PROFILE=compiler ULISP_BENCH_PASSES=1 ./ulisp/bin/ulisp-boot` で `ulisp/build/compiler_base_in.scm` に対する改善前後プロファイルを取得・比較し、目標値を達成していることを実証する。
5. `make py_compile && make static_analysis` および全相対リンク検証を通過させ、[git-workflow](../../../.agents/skills/git-workflow/SKILL.md) に従い Issue クローズ・コミット・マージを行う。

---

## 5. 完了条件 / Success Criteria (DoD)
- [x] **パフォーマンス目標達成 (`ULISP_BENCH_PASSES=1` 実測 on `ulisp/build/compiler_base_in.scm`)**:
  - `compiler_base_in.scm` 総コンパイル時間: **2,500 ms 以下**（ベースライン `10,325.24 ms` → 実測 **`1,793.31 ms`**、約 5.76 倍高速化 / 82.6% 削減）
  - `pass-050-cp0` 実行時間: **800 ms 以下**（ベースライン `6,265.15 ms` → 実測 **`176.09 ms`**、約 35.6 倍高速化 / 97.2% 削減）
  - `pass-100-contify` 実行時間: **500 ms 以下**（ベースライン `1,813.92 ms` → 実測 **`98.52 ms`**、約 18.4 倍高速化 / 94.6% 削減）
  - `pass-030-desugar` 等を含む 3 パス合計でも $O(N^2)$ スケーリングが解消されていること（`pass-030-desugar`: `1,263.86 ms` → **`91.47 ms`**）
- [x] **フレームワーク・パス機能テスト**:
  - `make -C ulisp test_nanopass` 全件 PASS（Section 25 含む **279 tests passed**）
  - `make -C ulisp test_passes` 全件 PASS
  - `make -C ulisp test_pass_manager` 全件 PASS（**115 / 115 assertions passed**）
- [x] **セルフホスティング・静的品質ゲート**:
  - `make -C ulisp compiler` および `make -C ulisp lint_sexpr` が 0 エラーで完了すること（52 / 173 / 51 ファイル全て S 式括弧バランス検証 PASS）
  - `make -C ulisp bootstrap_verify` で Stage 2 と Stage 3 のバイナリ bit-for-bit 不動点一致が確認されること（`1m15.254s` で完了、`bin/ulisp-boot` 更新済み）
  - `make py_compile && make static_analysis` が PASS すること（`xenon --max-absolute A --max-modules A --max-average A src` / `mypy --strict src` 617 ファイル 0 エラー）
- [x] **ドキュメント・トレーサビリティ整合性**:
  - `docs/` 配下の更新ファイルおよび Issue 本文内の全リンクが相対パスで記述されており、壊れたリンク・絶対パスが 0 件であること
  - 計測ログ（プロファイル出力結果）が Issue クローズ時の完了記録へ明記されていること

---

## 6. 完了記録 / Verification & Benchmark Results (2026-11-14)

### 6.1 パス別プロファイル比較 (`env ULISP_GC_PROFILE=compiler ULISP_BENCH_PASSES=1 ./bin/ulisp-boot`)

#### `ulisp/build/compiler_base_in.scm`
| 計測対象 | 改善前 (ms) | 改善後 (ms) | 倍率 / 削減率 | DoD 閾値 |
| --- | ---: | ---: | ---: | :---: |
| `pass-030-desugar` | 1,263.86 ms | **91.47 ms** | 13.8x (-92.8%) | — |
| `pass-050-cp0` | 6,265.15 ms | **176.09 ms** | 35.6x (-97.2%) | $\le 800\text{ ms}$ |
| `pass-100-contify` | 1,813.92 ms | **98.52 ms** | 18.4x (-94.6%) | $\le 500\text{ ms}$ |
| **Total Compilation Time** | **10,325.24 ms** | **1,793.31 ms** | **5.76x (-82.6%)** | **$\le 2,500\text{ ms}$** |

- `compiler_base_in.scm` 実測合計ヒープ確保量: `1,126,969 KB`

#### その他コンパイラモジュール実測
- `ulisp/build/compiler_driver_in.scm`: Total **`179.83 ms`** / Heap `133,549 KB`（`pass-050-cp0`: `46.45 ms`, `pass-100-contify`: `9.74 ms`）
- `ulisp/build/lir_passes_in.scm`: Total **`2,157.73 ms`** / Heap `1,876,083 KB`（`pass-050-cp0`: `190.67 ms`, `pass-100-contify`: `67.85 ms`；旧シードでは 58 分超で停滞）
- `make -C ulisp build/ulisp-modular`: 全 5 モジュールコンパイル＋アセンブル＋リンクを **`15.042s`** で完了

### 6.2 品質ゲート・ブートストラップ検証記録
- `make -C ulisp compiler lint_sexpr test_nanopass test_passes test_pass_manager`: EXIT 0
  - `test_nanopass`: 279 tests passed
  - `test_passes`: 全モジュール PASS（Phase 4: 48, Pass 015: 27, Pass 020: 8, Pass 026: 31, Pass 027: 22, Pass 028: 56, Pass 029: 34, Pass 030: 24, Pass 040: 15, Pass 050: 13, Pass 070: 17, Pass 110: 17, TBAA & Escape: 23, Pass 123–127, Pass 131: 9, Pass 132: 12, Pass 133: 17, Pass 140: 21, Pass 142: 8, Pass 143: 10, Pass 160: 15）
  - `test_pass_manager`: 115 / 115 assertions passed
- `make -C ulisp bootstrap_verify`: EXIT 0 (`real 1m15.254s`, Stage 2 and Stage 3 bit-for-bit identical, `bin/ulisp-boot` updated)
- `make py_compile static_analysis`: EXIT 0 (`xenon` A/A/A, `mypy --strict src`: Success: no issues found in 617 source files)
