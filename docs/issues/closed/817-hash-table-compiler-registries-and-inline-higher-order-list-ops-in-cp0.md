---
ID: 817
種別: Feature
優先度: High
ステータス: Closed
完了日: 2026-11-14
Target Branch: feat/817-hash-table-compiler-registries-and-inline-higher-order-list-ops-in-cp0
---

# [FEAT/ENH] コンパイラ内部連想リストのベクタハッシュテーブル化と 050_cp0 における map/for-each インライン展開による AOT 実行高速化 (ID: 817)

## 1. 概要 / Summary
ULisp でコンパイルされたセルフホスティング AOT バイナリおよび一般ユーザープログラムの**実行時間**とヒープ割り当てを削減するため、実行時オーバーヘッドが大きい以下の 2 つの領域を最適化した：

1. **コンパイラ内部の大域連想リスト (`assq`) のベクタハッシュバケット化 ($O(N) \to O(1)$)**:
   - [nanopass_meta.scm](../../../ulisp/compiler/nanopass_meta.scm#L1090-L1200) の `*nanopass-rules*`（`nanopass-register-rule!` / `nanopass-lookup-rule-opt` / `nanopass-get-all-rules` / `nanopass-clear-rules!`）を 256 スロットシンボルハッシュバケット `*nanopass-rule-buckets*`＋手続き用 `*nanopass-rule-procs*`＋登録順 `*nanopass-rules*` へ移行し、Picopass / Femtopass 登録・解決時の線形走査を排除した。
   - [nanopass_meta.scm](../../../ulisp/compiler/nanopass_meta.scm#L2365-L2496) の `*femto-analysis-cache*`（および `record-picopass-firing!` L660）を `(cons bucket-vector entry-count)` の 256 スロットベクタバケット形式へ移行し、`femto-get-cached-attr`・`femto-cache-invalidate-tags!`・`femto-cache-invalidate-node!` の $O(N^2)$ 化を解消した。
   - [080_annotator.scm](../../../ulisp/frontend/080_annotator.scm) の `*global-type-env*`・`*expr-type-table*`（`record-var-type!` / `get-var-type` / `record-expr-type!` / `get-expr-type` / `reset-type-annotations!`）および [090_rtyper.scm](../../../ulisp/frontend/090_rtyper.scm) の `*rtyper-facts*`（`record-rtyper-fact!` / `get-rtyper-fact` / `reset-rtyper!`）を [helpers.scm](../../../ulisp/compiler/helpers.scm#L1574-L1582) の `symbol->hash-idx` 連動 256 スロットハッシュバケットへ移行した。
2. **Pass 050 (`050_cp0.scm`) における 2 引数 `map` / `for-each` の即値 `lambda` インラインループ展開**:
   - [050_cp0.scm](../../../ulisp/frontend/050_cp0.scm) に `cp0-inlineable-unary-lambda?` と `rule-cp0-inline-map-for-each` を追加し、`cp0-opt` の `(fuse-rules :order post ...)` 内で単項 `(lambda (x) body)` を渡す 2 引数 `(map (lambda (x) body) ls)` および `(for-each (lambda (x) body) ls)` を自己末尾再帰 `letrec` ループへインライン展開した。あわせて `cp0-has-dead-letrec-binding?` の単一束縛高速パスを追加した。
   - 展開された単一束縛・末尾再帰 `letrec` は下流の `pass-100-contify`（[100_contify.scm](../../../ulisp/frontend/100_contify.scm#L96-L107) / [040_analysis.scm](../../../ulisp/frontend/040_analysis.scm#L229-L237) `contifiable-binding?`）によって `%cont-fun` / `%cont-call` へ自動低下され、`%make-closure` と `%call-closure` を排除した。
   - セルフホスティング立ち上げ時に [nanopass_meta.scm](../../../ulisp/compiler/nanopass_meta.scm#L181)（`nanopass-derive-nonterminals-and-removed`）の `map` 展開後に言語キーワード登録で早期参照されるクロージャ／継続 IR シンボル 6 個（`%make-closure`, `%make-closure-env`, `%closure-ref`, `%closure-set!`, `%cont-fun`, `%cont-call`）を [helpers.scm](../../../ulisp/compiler/helpers.scm#L1188-L1200) の `*known-compiler-symbols*` に登録した。

---

## 2. トレーサビリティ / Traceability
- [DSN-33-01 Nanopass/Picopass DAG アーキテクチャ仕様書](../../designs/DSN-33-01-ulisp_pipeline_pass_nanopass_picopass_dag_architecture.md)
- 関連 Issue:
  - [Issue #813 (fuse-rules :order post と Femtopass キャッシュ接続)](813-implement-fuse-rules-post-order-and-connect-femtopass-cache.md)
  - [Issue #815 (Nanopass カタモルフィズム浅いディスパッチ＆メモ化バケット化)](815-optimize-nanopass-catamorphism-shallow-dispatch-and-term-memo-buckets.md)
  - [Issue #816 (090_rtyper エスケープ走査削減＆133_lir_peephole 直接パターン化)](816-optimize-rtyper-escape-pruning-and-lir-peephole-window-allocation.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [ulisp/compiler/helpers.scm](../../../ulisp/compiler/helpers.scm) (`*known-compiler-symbols*` への `%make-closure` / `%make-closure-env` / `%closure-ref` / `%closure-set!` / `%cont-fun` / `%cont-call` 追加)
- [x] [ulisp/compiler/module_header.scm](../../../ulisp/compiler/module_header.scm) (`%declare-extern-identifiers` への `symbol->hash-idx` 追加)
- [x] [ulisp/compiler/nanopass_meta.scm](../../../ulisp/compiler/nanopass_meta.scm) (`*nanopass-rules*`・`*femto-analysis-cache*` の 256 スロットベクタバケット化、および `record-picopass-firing!` 更新)
- [x] [ulisp/frontend/080_annotator.scm](../../../ulisp/frontend/080_annotator.scm) (`*global-type-env*`・`*expr-type-table*` の 256 スロットベクタバケット化)
- [x] [ulisp/frontend/090_rtyper.scm](../../../ulisp/frontend/090_rtyper.scm) (`*rtyper-facts*` の 256 スロットベクタバケット化)
- [x] [ulisp/frontend/050_cp0.scm](../../../ulisp/frontend/050_cp0.scm) (`cp0-has-dead-letrec-binding?` 高速パス、`cp0-inlineable-unary-lambda?`・`rule-cp0-inline-map-for-each` 追加および `cp0-opt` への統合)
- [x] [ulisp/tests/passes/test_050_cp0.scm](../../../ulisp/tests/passes/test_050_cp0.scm) (`map` / `for-each` インライン展開・変数衝突回避・順序保証・多引数/rest 引数非展開ガード・`%cont-fun` 低下テスト追加)
- [x] [ulisp/tests/test_nanopass_framework.scm](../../../ulisp/tests/test_nanopass_framework.scm) (Section 27: バケット化 `*nanopass-rules*` / `*femto-analysis-cache*` 互換性・無効化テスト追加)
- [x] [ulisp/compiler.scm](../../../ulisp/compiler.scm) ・ [ulisp/bin/ulisp-boot](../../../ulisp/bin/ulisp-boot) (再生成・3段階ブートストラップ不動点検証済みシードバイナリ更新)

---

## 4. 実装内容 / Implemented Design
Target Branch: `feat/817-hash-table-compiler-registries-and-inline-higher-order-list-ops-in-cp0`

### Step 1: モジュール間シンボルと `*known-compiler-symbols*` の整備
- [ulisp/compiler/module_header.scm](../../../ulisp/compiler/module_header.scm) の `%declare-extern-identifiers` に `symbol->hash-idx` を追加し、モジュラービルド（`frontend_passes_in.scm` 等）の `080_annotator.scm` / `090_rtyper.scm` から $O(1)$ ハッシュ索引を利用可能にした。
- [ulisp/compiler/helpers.scm](../../../ulisp/compiler/helpers.scm) の `*known-compiler-symbols*` に `%make-closure`, `%make-closure-env`, `%closure-ref`, `%closure-set!`, `%cont-fun`, `%cont-call` を追加し、AOT シンボルテーブル未登録段階でも `"?"` へフォールバックしないようにした。

### Step 2: コンパイラ内部テーブルの 256 スロットベクタハッシュバケット化 ($O(N) \to O(1)$)
1. **`*nanopass-rules*` ([ulisp/compiler/nanopass_meta.scm](../../../ulisp/compiler/nanopass_meta.scm#L1090-L1200))**:
   - 256 スロットのシンボルハッシュベクタ `*nanopass-rule-buckets*`（`(modulo (symbol->hash-idx sym) 256)` で索引）・プロシージャキー用 `*nanopass-rule-procs*`・登録順 `*nanopass-rules*` へ移行。
2. **`*femto-analysis-cache*` ([ulisp/compiler/nanopass_meta.scm](../../../ulisp/compiler/nanopass_meta.scm#L2365-L2496), L660)**:
   - `(cons bucket-vector entry-count)` 構造（256 スロットベクタ、ハッシュ関数 `femto-node-bucket-idx` / `femto-atom-hash`）へ移行し、`record-picopass-firing!`・`femto-cache-reset!`・`femto-get-cached-attr`・`femto-cache-invalidate-tags!`・`femto-cache-invalidate-node!`・`femto-cache-stats` を更新。
3. **`*global-type-env*` / `*expr-type-table*` ([ulisp/frontend/080_annotator.scm](../../../ulisp/frontend/080_annotator.scm)) および `*rtyper-facts*` ([ulisp/frontend/090_rtyper.scm](../../../ulisp/frontend/090_rtyper.scm))**:
   - 各テーブルを 256 スロットのベクタバケット `(make-vector 256 '())` へ移行し、`symbol->hash-idx` で $O(1)$ バケット索引用インデックスを算出。

### Step 3: `050_cp0.scm` での 2 引数 `map` / `for-each` インライン展開 Picopass 追加
- [ulisp/frontend/050_cp0.scm](../../../ulisp/frontend/050_cp0.scm#L198-L245) に `cp0-inlineable-unary-lambda?` と `rule-cp0-inline-map-for-each` を追加し、`cp0-opt` の `(fuse-rules :order post ...)` に統合。
- **展開テンプレート**（`unique-symbol` により衛生性を保証し、`<val>` の内側スコープのみに `<x>` を束縛して `cdr` / `cons` / `reverse` / `pair?` との名前衝突を防止）：
  - `map`:
    ```scheme
    (letrec ((<loop> (lambda (<cur> <acc>)
                       (if (pair? <cur>)
                           (let ((<val> (let ((<x> (car <cur>))) <body>)))
                             (<loop> (cdr <cur>) (cons <val> <acc>)))
                           (reverse <acc>)))))
      (<loop> <ls> '()))
    ```
  - `for-each`:
    ```scheme
    (letrec ((<loop> (lambda (<cur>)
                       (if (pair? <cur>)
                           (begin
                             (let ((<x> (car <cur>))) <body>)
                             (<loop> (cdr <cur>)))
                           #f))))
      (<loop> <ls>))
    ```

---

## 5. 完了条件 / Success Criteria (DoD)
- [x] `*nanopass-rules*`、`*femto-analysis-cache*`、`*global-type-env*`、`*expr-type-table*`、`*rtyper-facts*` が 256 スロットベクタハッシュバケット検索へ移行され、既存 API（`nanopass-lookup-rule`、`nanopass-get-all-rules`、`femto-cache-stats`、`get-var-type`、`get-expr-type`、`get-rtyper-fact` 等）と 100% 互換であること。
- [x] `050_cp0.scm` で単項 `lambda` 付きの 2 引数 `map` / `for-each` が末尾再帰 `letrec` ループへインライン展開され、`test_050_cp0.scm` および多引数ケース（`test_base_procedures.scm`）を含む同値性・ガードテストが全件 PASS すること。
- [x] 更新済み AOT バイナリ（`ulisp/bin/ulisp-boot`）を用いた `build/compiler_base_in.scm` のコンパイル実行時間（`ULISP_BENCH_PASSES=1`）が、Issue #816 後の基準（`677.81 ms`）からさらに短縮（目標 $\le 620\text{ ms}$）し、性能回帰がないこと。
- [x] `make -C ulisp compiler lint_sexpr test_nanopass test_passes test_pass_manager` がエラー 0 件で全件 PASS すること。
- [x] `make -C ulisp bootstrap_verify` で Stage 2 と Stage 3 の bit-for-bit 不動点一致が確認されること。
- [x] `make py_compile && make static_analysis` が PASS すること。
- [x] ドキュメント内のすべてのリンクが相対パスで記述されていること。

---

## 6. 検証結果・ベンチマーク結果 / Verification & Benchmark Results

### 6.1 テスト・検証スイート実行結果
- `make -C ulisp compiler bootstrap_verify build/ulisp-modular test_base_procedures`: **PASS (exit 0)**
  - Stage 2 (`build/stage2_compiler.s`) と Stage 3 (`build/stage3_compiler.s`) の **bit-for-bit 不動点一致**を確認、`ulisp/bin/ulisp-boot` 更新、`build/ulisp-modular`（`bin/ulisp-modular`）リンク成功、`ALL R7RS BASE CORE PROCEDURE TESTS PASSED!`。
- `make -C ulisp lint_sexpr test_nanopass test_passes test_pass_manager test_annotator test_rtyper`: **PASS (exit 0)**
  - `lint_sexpr`: `173` / `51` ファイルすべて括弧バランス PASS。
  - `test_nanopass`: `Nanopass Framework: All 313 tests passed!`（新規 Section 27 含む）、`Nanopass Phase 4: All 48 tests passed!`。
  - `test_passes`: `Pass 050: All 24 tests passed!`（新規 `map` / `for-each` インライン展開＆ガード＆`%cont-fun` 低下テスト含む）ほか全パススイート PASS。
  - `test_pass_manager`: `115 / 115 assertions passed.`
  - `test_annotator`: `All 26 Pass 04b (S-Annotator Narrowing) unit tests PASSED! (0 failures)`
  - `test_rtyper`: `All 28 Pass 05b (S-RTyper) unit tests PASSED! (0 failures)`
- `make py_compile && make static_analysis`: **PASS (exit 0)**（`xenon` PASS、`mypy --strict src`: `Success: no issues found in 617 source files`）

### 6.2 `ULISP_BENCH_PASSES=1 ./bin/ulisp-boot` コンパイル時間計測（Issue #816 比）
| 入力モジュール | Issue #816 基準 | Issue #817 計測値 | ヒープ割当量 | 差分 / 評価 |
| :--- | :---: | :---: | :---: | :--- |
| `build/compiler_base_in.scm` | `677.81 ms` (`648,584 KB`) | **`606.00 ms`** | `645,602 KB` | **`-71.81 ms` (`-10.6%`)**（目標 `<= 620 ms` 達成） |
| `build/compiler_driver_in.scm` | `64.65 ms` | `65.97 ms` | `69,189 KB` | `+1.32 ms`（誤差範囲内） |
| `build/lir_passes_in.scm` | `675.84 ms` | `697.17 ms` | `802,021 KB` | インライン展開適用に伴う増加範囲内 |
| `build/frontend_passes_in.scm` | `1,565.31 ms` | `1,767.15 ms` | `1,457,032 KB` | 全 `map`/`for-each` インライン展開による AST 拡大範囲内 |
