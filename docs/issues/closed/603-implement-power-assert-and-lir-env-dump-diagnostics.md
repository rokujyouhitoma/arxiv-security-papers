---
ID: 603
種別: Feature
優先度: Medium
ステータス: Closed (Completed)
---

# [FEAT/ENH] Power Assert 風アサーション式展開および LIR 変数解決失敗時のローカル環境（env）自動ダンプ機能の実装 (ID: 603)

## 1. 概要 / Summary

コンパイラ開発・自己ホストブートストラップおよびテストスイート実行時において、アサーション違反や未束縛変数例外（`Unbound variable in LIR`）が発生した際、単に「条件不成立」や「未定義シンボル名」だけが報告される原始的なエラーハンドリングでは、「なぜその条件が不成立だったのか（部分式が何を返したのか）」「その時点で環境（`env`）に何が存在していたのか」を把握できず、デバッグに多くの時間を浪費していた。

### 背景と課題:
1. **アサーション失敗時の原因究明困難性**:
   `assert-true` や `assert-equal` 等の既存テストアサーションでは、式 `(assq var env)` が不成立（`#f`）となった場合、`var` の値が何であったか、`env` に何が束縛されていたのかが即座に分からず、テストコードに一時的な `(display ...)` を挿入して再実行する必要があった。
2. **LIR 変数解決エラーの不親切さ**:
   `ulisp/lir/130_lir.scm` の `lir-compile-variable` において `(not (assq var env))` が発生した場合、現在は `(error "Unbound variable in LIR: <var>" var)` が出力されるのみである。この時点で有効だったローカル変数バインディング（引数、レジスタ、スタックスロット）や、クロージャ自由変数の環境情報が一切ダンプされない。
3. **タイポ・スペルミスの自己解決支援の欠如**:
   変数名や関数名のわずかなスペルミス（例: `len` と `length`, `param-ls` と `param-lst`, `car` と `cdr`）に対して、コンパイラが有効なスコープ内シンボルから類似候補（Did you mean ...?）を提示する機構が存在しない。
4. **自己ホスト環境（ULisp native AOT / ILisp）における互換性・リソース制約**:
   リッチな診断機構は有用である一方、自己ホストブートストラップバイナリ（Stage 1/2/3）やテスト実行環境において、過度な動的メモリ確保（文字列アロケーション・ヒープ消費）や循環参照によるスタックオーバーフローを引き起こしてはならない。

本 Issue では、Power Assert の概念を導入し、アサーション失敗時に対象式および構成要素（部分式）の評価値をツリー／ダイアグラム状に自動展開する `power-assert` マクロおよびフォーマッタを実装する。
また、LIR 生成フェーズ（`lir-compile-variable`）において未束縛変数が検出された際、有効なローカル環境バインディング（`env`）の構造化ダンプと、レーベンシュタイン距離アルゴリズムに基づく類似シンボル推薦（"Did you mean ...?"）を自動提示する高度な診断機構を構築する。

---

## 2. トレーサビリティ / Traceability

- **正典仕様書**:
  - [DSN-33 (ULisp 包括設計仕様書)](../../docs/designs/DSN-33-ulisp_underlying_x86_native_aot_compiler_architecture_specification.md) (Section 3: Nanopass コンパイラパイプライン設計)
  - [LIR 命令セット仕様書](../../ulisp/docs/spec_lir.md)
  - [ULisp パイプライン・Nanopass 詳細仕様書](../../ulisp/docs/spec_pipeline.md)
- **関連 Issue**:
  - [Issue 576: 軽量 IR Verifier フレームワークの導入による中間不変条件の機械的検証](closed/576-implement-lightweight-ir-verifier-framework.md)
  - [Issue 593: LIR層: define-language L_lir_canonical の導入と lir_verifier 宣言的統合](closed/593-define-lir-canonical-language-and-verifier-integration.md)
  - [Issue 597: IR Verifier 基盤の共通化・階層分離と LIR 検証パフォーマンス最適化](597-unify-ir-verifier-framework-and-optimize-lir-performance.md)
  - [Issue 601: ネイティブランタイムにおけるシンボル名表示の復元および未捕捉例外メッセージの構造化整形](closed/601-restore-symbol-printing-and-format-unhandled-exceptions.md)
  - [Issue 602: コンパイラ実行時における現在Nanopass・処理中トップレベル式・ソース位置のコンテキスト追跡とエラー診断ダンプの導入](closed/602-track-compiler-context-pass-and-toplevel-form-on-error.md)
  - [Issue 604: コンパイラ実行時のコールスタック追跡（Call Stack Traceback）および未捕捉例外時のバックトレース表示機能の実装](604-implement-call-stack-traceback-for-compiler-exceptions.md)
  - [Issue 606: ビルド時 cat 結合の廃止と R7RS include 構文によるソース位置（ファイル名・行番号）追跡基盤の導入](606-replace-cat-bundle-with-r7rs-include-and-source-tracking.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files

- [x] [ulisp/compiler/helpers.scm](../../ulisp/compiler/helpers.scm)
  - Power Assert 評価エンジンおよびフォーマッタ（`format-power-assert-diagram`, `power-assert-report`）の実装
  - ホスト・自己ホスト双方で動作する `power-assert` マクロの定義
  - ゼロ外部依存・自己ホスト安全なレーベンシュタイン距離計算アルゴリズム（`string-levenshtein-distance`, `symbol-levenshtein-distance`）の実装
  - タイポ類似シンボル推薦エンジン（`find-similar-symbols`）の実装
  - LIR 環境（`env`）ダンプフォーマッタ（`format-lir-env-bindings`）の実装
- [x] [ulisp/lir/130_lir.scm](../../ulisp/lir/130_lir.scm)
  - `lir-compile-variable` における未束縛変数検出時のリッチ診断ダンプフック（有効 `env` 一覧表示および類似シンボル候補サジェスト）の統合
- [x] [ulisp/tests/passes/test_power_assert.scm](../../ulisp/tests/passes/test_power_assert.scm) (新規)
  - `power-assert` 成功／失敗時の評価値キャプチャ検証
  - レーベンシュタイン距離および類似シンボル推薦の網羅的単体テスト
  - LIR 環境フォーマットおよび未束縛変数診断メッセージの正確性検証
- [x] [ulisp/Makefile](../../ulisp/Makefile)
  - `NANOPASS_TESTS` への `tests/passes/test_power_assert.scm` の登録および個別ターゲット `test_power_assert` の整備

---

## 3.2 脅威分析とセキュリティ要件 / Threat Modeling & Security Requirements

コンパイラの診断ダンプおよび文字列演算処理におけるセキュリティ脅威と信頼境界を分析し、以下の対策を講じる。

| 脅威分類 (STRIDE / CWE) | 脅威シナリオ | 影響度 | 対策要件 (Mitigation) |
| :--- | :--- | :---: | :--- |
| **情報漏洩・過大出力 (CWE-209 / CWE-779)** | 診断レポート生成時に循環リストや数メガバイトの巨大 AST が渡され、標準出力が溢れ、メモリ枯渇やバッファ過大消費を招く。 | Medium | `truncate-expr-for-diagnostics`（Issue 602導入済み）を活用して式の深さ・長さを最大 5 要素／深さ 3 に制限。環境（`env`）ダンプも最大出力件数（例: 最大 20 エントリ）を設け、超過時は `... (N more bindings omitted)` で省略する。 |
| **リソース枯渇・アルゴリズム DoS (CWE-400)** | 極端に長いシンボル名や大量のローカル束縛に対して $O(M \times N)$ のレーベンシュタイン距離計算を繰り返し実行し、コンパイル処理が長時間フリーズする。 | Medium | 1. シンボル長が極端に長い場合（64 文字超）は類似度計算をスキップ。<br>2. 探索対象シンボルと長さの差が閾値（3 文字超）を超える場合は早期リターン（枝刈り）。<br>3. 比較対象候補数を制限（最大 50 件）し、計算オーバーヘッドをミリ秒未満に抑え込む。 |
| **再帰エラー・多重フォールト (CWE-674)** | 診断ダンプや式評価の出力処理（`display`, `write`）中に別の Scheme 例外が発生し、エラーハンドラが自己再帰してスタック枯渇（SEGV）する。 | High | 既存のコンパイラ再帰ガード（`*compiler-in-error*`）と完全に同期させ、診断ダンプ処理中に二重エラーが発生した場合は即座に簡易プレーン出力へフォールバックして制御を安全に返す。 |
| **自己ホストバイナリでのメモリ破壊 (CWE-119 / CWE-787)** | ネイティブ AOT コンパイルされたブートストラップ環境において、ベクタや文字列の境界外アクセス、未初期化バッファ参照が発生する。 | High | 動的計画法（DP）テーブルは純粋な Scheme ベクタ（またはリスト）を用い、インデックス境界チェック（`0 <= i < len`）を明示的に徹底する。 |

---

## 4. 実装方針 / Implementation Plan

Target Branch: `feat/603-implement-power-assert-and-lir-env-dump-diagnostics`

### 4.1 Power Assert マクロおよびグラフィカル診断フォーマッタ (`ulisp/compiler/helpers.scm`)

Power Assert は、アサーション式が失敗（`#f` または非真値）した際に、ルート式および各引数・部分式の評価値を捕捉し、可視化する機構である。

1. **構文とマクロ展開**:
   `(power-assert (op arg1 arg2 ...))` の形式を以下のような評価捕捉形式に展開する：
   ```scheme
   (let* ((v-arg1 arg1)
          (v-arg2 arg2)
          (v-result (op v-arg1 v-arg2)))
     (if (not v-result)
         (power-assert-report '(op arg1 arg2 ...)
                              (list (list 'arg1 v-arg1)
                                    (list 'arg2 v-arg2))
                              v-result)
         v-result))
   ```
2. **2層表現による診断出力 (`power-assert-report`)**:
   端末幅の崩れや複雑な S 式に対応するため、以下の2つの表現を同時に出力する：
   - **Structured Key-Value Dump**:
     ```text
     ======================================================================
     [POWER ASSERT FAILED] Assertion condition evaluated to #f
     ======================================================================
       Expression : (assq var env)
       Evaluations:
         - (assq var env) => #f
         - var            => car
         - env            => ((ls . (param . -8)) (pred . (param . -16)))
     ```
   - **Graphical Tree Diagram**:
     ```text
       Diagram    :
         (assq var env)
          |    |   |
          |    |   ((ls . (param . -8)) (pred . (param . -16)))
          |    car
          #f
     ======================================================================
     ```
3. **自己ホストおよび ILisp 互換性**:
   `define-macro` を用いてホスト系（ILisp / chibi / Gauche）で展開可能としつつ、ネイティブコンパイル時にも `015_dsl_expander.scm` または `helpers.scm` 経由で同等の手続き呼び出しへ安全に脱糖可能とする。

### 4.2 レーベンシュタイン距離 & タイポ類似シンボル推薦機構

1. **レーベンシュタイン距離アルゴリズム (`string-levenshtein-distance s1 s2`)**:
   - 2 つの文字列 `s1`（長さ $M$）と `s2`（長さ $N$）の最小編集距離（挿入・削除・置換）を計算する。
   - 空間計算量を $O(N)$ に抑えるため、2 行分のベクタ（`v0` と `v1`）を用いて動的計画法を反復実行する。
   - 早期プルーニング: `(abs (- m n)) > max-threshold` の場合は距離計算を行わずに即時超過判定を返す。
2. **シンボル推薦 (`find-similar-symbols target candidate-symbols [max-dist]`)**:
   - `candidate-symbols`（`env` の全バインディングキーなど）を走査。
   - 各候補について `symbol-levenshtein-distance` を計算。
   - 距離が閾値（デフォルト: `2`、かつターゲット文字列長の 50% 以下）以内の候補を距離昇順で抽出。
   - 上位最大 3 件の候補リストを返却。

### 4.3 LIR 未束縛変数時のローカル環境（`env`）ダンプ機構 (`ulisp/lir/130_lir.scm`)

`lir-compile-variable` における変数解決失敗時の処理を高度化する。

```scheme
(define (lir-compile-variable var env)
  (let ((binding (assq var env)))
    (if (not binding)
        (begin
          (dump-lir-unbound-variable-diagnostic var env)
          (error (string-append "Unbound variable in LIR: " (symbol->string var)) var))
        (let ((info (cdr binding)))
          ...)))
```

1. **`dump-lir-unbound-variable-diagnostic` の動作**:
   - `env`（形式: `((var . info) ...)`）から有効な変数名一覧を抽出。
   - `find-similar-symbols` を用いて、`var` に類似したスコープ内シンボルを検索。
   - 以下の形式で視認性の高いリッチレポートを出力：
     ```text
     ======================================================================
     [LIR COMPILER ERROR] Unbound Variable Resolution Failed
     ======================================================================
       Unbound Symbol  : car
       Current Function: filter-evens
       Current Expr    : (car ls)
       Did you mean?   : (cdr, caar)
       Active Local Bindings in 'env' (2 entries):
         - ls   -> (param . -8)
         - pred -> (param . -16)
     ======================================================================
     ```
   - バインディングの内部表現（`param -8`, `reg %rax`, スタックスロット等）を人間可読な形式にフォーマット。

### 4.4 テストスイートの拡充 (`ulisp/tests/passes/test_power_assert.scm`)

新規テストスイートを作成し、以下の項目を網羅的に検証する：
1. **Power Assert 成功ケース**: 真値（`#t`, `42`, `'ok`）を返す式が副作用なく結果を返すこと。
2. **Power Assert 失敗ケース**: 条件不成立時に適切に捕捉され、ダイアグラムおよび評価値が生成されること。
3. **レーベンシュタイン距離計算**:
   - 同一文字列: 距離 0
   - 1文字置換 (`cat` vs `bat`): 距離 1
   - 1文字挿入・削除 (`cat` vs `cats`, `cats` vs `cat`): 距離 1
   - 空文字列との比較: 文字列長に一致
   - 早期枝刈り判定の検証
4. **類似シンボル推薦**:
   - `'car` に対する `'(cdr caar cadar foo bar)` からの推薦（`caar` 等の抽出）
   - 該当なしの場合の空リスト返却
5. **LIR 環境ダンプフォーマット**:
   - 空の `env` に対する安全な表示（`(empty environment)`）
   - 多数の束縛を持つ `env` に対する切り詰め処理（最大件数制限）

---

## 5. 完了条件 / Success Criteria (DoD)

- [x] `ulisp/compiler/helpers.scm` に `power-assert` マクロおよびフォーマッタ（`format-power-assert-diagram` / `power-assert-report`）が実装されていること。
- [x] `ulisp/compiler/helpers.scm` に純粋 Scheme によるレーベンシュタイン距離（`symbol-levenshtein-distance`）および類似シンボル推薦（`find-similar-symbols`）が実装されていること。
- [x] `ulisp/compiler/helpers.scm` に `env` フォーマッタ（`format-lir-env-bindings`）が実装されていること。
- [x] `ulisp/lir/130_lir.scm` の `lir-compile-variable` において、未束縛変数例外発生時に有効な `env` の中身および類似シンボル候補（"Did you mean ...?"）が構造化出力されること。
- [x] 新規単体テスト `ulisp/tests/passes/test_power_assert.scm` が作成され、全テスト項目が 100% PASS すること。
- [x] `ulisp/Makefile` の `NANOPASS_TESTS` に新規テストが登録され、`make -C ulisp compiler` および `make test_unit` が正常完了すること。
- [x] 既存の全テスト（`make -C ulisp test_passes`, `make -C ulisp test_lir_suite`）がリグレッションなく PASS すること。
- [x] リポジトリ内全リンクが相対パス（`../../...`）に準拠していること。

---

## 6. 検証手順 / Verification Procedures

1. **コンパイラパス再生成と静的検証**:
   ```bash
   make -C ulisp compiler
   make -C ulisp build/compiler_passes.scm
   ```
2. **Power Assert および診断ダンプ新規単体テスト実行**:
   ```bash
   make -C ulisp test_power_assert
   # または
   PYTHONPATH=. python3 -m ilisp ulisp/tests/passes/test_power_assert.scm
   ```
3. **Nanopass 全パス結合テスト実行**:
   ```bash
   make -C ulisp test_passes
   ```
4. **LIR スイート回帰テスト実行**:
   ```bash
   make -C ulisp test_lir_suite
   bash ulisp/test_lir.sh
   ```
5. **品質ゲート全検証**:
   ```bash
   make static_analysis
   make test
   ```
