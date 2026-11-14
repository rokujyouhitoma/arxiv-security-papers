---
ID: 816
種別: Feature
優先度: High
ステータス: Closed
Target Branch: feat/816-optimize-rtyper-escape-pruning-and-lir-peephole-window-allocation
完了日: 2026-11-14
---

# [FEAT/ENH] 090_rtyper のエスケープ走査 O(N) 化と 133_lir_peephole ウィンドウマッチングのヒープアロケーション削減 (ID: 816)

## 1. 概要 / Summary
Issue #815 後の `ULISP_BENCH_PASSES=1` による計測（`ulisp/build/compiler_base_in.scm` 合計 `1,793.31 ms`）およびコード分析の結果、残存する 2 大ボトルネックが確認された：

1. **Pass 090 (`090_rtyper.scm`) の $O(F \cdot N)$ エスケープ全走査（`314.40 ms` / 17.5%）**:
   - `find-pure-int-fns`（[090_rtyper.scm](../../../ulisp/frontend/090_rtyper.scm)）が、全トップレベル関数 $F$ 個すべてについて、自身の関数本体が純粋整数関数かを調べる `pure-int-expr?` よりも**先に**、プログラム全体（`cons main defs`、サイズ $N$）を `fn-escapes-in-expr?` で毎回フル走査しているため。
   - さらに `fn-escapes-in-expr?` が各 `let` ノードで `(map car* (cadr expr))` をヒープ割り当てし、`rtyper-expr-scoped` の `letrec` で `find-pure-int-fns` を二重呼び出ししており、`(<= (expr-size body) 40)` も上限 40 を超えた後も巨大な AST 全体を走査している。
2. **Pass 133 (`133_lir_peephole.scm`) / `fuse-window-rules` の大量ヒープアロケーション（`387.64 ms` / 21.6%, `450,186 KB`; `lir_passes_in.scm` では `832.97 ms` / `829,240 KB`）**:
   - 原因 1: [nanopass.scm](../../../ulisp/compiler/nanopass.scm) の `nanopass-compile-window-rule-chain`、`nanopass-compile-single-rule-cascade`、および `nanopass-build-rule-cascade` が、命令リストの各要素位置ごとにインタプリタ型 `nanopass-match-clause` を呼び出し、パターン不成立・ガード失敗（99.9%）の場合でも一時 alist や `reverse` / `append` でコンスセルを大量割り当てしていること。
   - 原因 2: [nanopass_meta.scm](../../../ulisp/compiler/nanopass_meta.scm) の `nanopass-sliding-window-pass` が、ルールが一度も発火しないパス（`changed? == #f`）でも毎命令ごとに `acc` をコンスして `(reverse acc)` していること。
   - 原因 3: `lir-peephole-reg?`（[133_lir_peephole.scm](../../../ulisp/lir/133_lir_peephole.scm) / `nanopass_meta.scm`）が毎回 `symbol->string` を呼び出して文字列割り当てを行っていること。

---

## 2. トレーサビリティ / Traceability
- [DSN-33-01 Nanopass/Picopass DAG アーキテクチャ仕様書](../../designs/DSN-33-01-ulisp_pipeline_pass_nanopass_picopass_dag_architecture.md)
- 関連 Issue:
  - [Issue #767 (LIR ピープホール Picopass 化)](767-migrate-lir-peephole-to-picopass-and-dependency-dag.md)
  - [Issue #815 (Nanopass カタモルフィズム浅いディスパッチ＆メモ化バケット化)](815-optimize-nanopass-catamorphism-shallow-dispatch-and-term-memo-buckets.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [ulisp/compiler/helpers.scm](../../../ulisp/compiler/helpers.scm) (`expr-size-budget` / `expr-size-le?` 早期打ち切りヘルパー追加)
- [x] [ulisp/compiler/module_header.scm](../../../ulisp/compiler/module_header.scm) (`%declare-extern-identifiers` へ `expr-size-le?` 追加)
- [x] [ulisp/frontend/090_rtyper.scm](../../../ulisp/frontend/090_rtyper.scm) (`rtyper-let-binds-var?` 導入、`find-pure-int-fns` の局所 `pure-int-expr?`＋不動点枝刈り先行化、`expr-size-le?` 適用、`letrec` 重複呼び出し排除・`rtyper-standard-let-bindings` 共通化)
- [x] [ulisp/compiler/nanopass.scm](../../../ulisp/compiler/nanopass.scm) (`nanopass-direct-matchable-pattern?` / `nanopass-compile-direct-pattern` 導入による `fuse-window-rules` および通常ルールのゼロアロケーション直接マッチング化)
- [x] [ulisp/compiler/nanopass_meta.scm](../../../ulisp/compiler/nanopass_meta.scm) (`nanopass-sliding-window-pass` の未変更時ゼロアロケーション走査、`nanopass-optimize-function-body`/`main-body` の `eq?` 共有維持、`lir-peephole-reg?` 高速化)
- [x] [ulisp/lir/133_lir_peephole.scm](../../../ulisp/lir/133_lir_peephole.scm) (`lir-peephole-reg?` の 16 レジスタ `case` 高速化)
- [x] [ulisp/tests/test_nanopass_framework.scm](../../../ulisp/tests/test_nanopass_framework.scm) (Section 26 回帰・単体テスト追加)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/816-optimize-rtyper-escape-pruning-and-lir-peephole-window-allocation`

1. **`090_rtyper.scm` の $O(F \cdot N)$ エスケープ走査解消**:
   - `fn-escapes-in-expr?` 内の `(memq fn-name (map car* (cadr expr)))` をゼロアロケーションの `rtyper-let-binds-var?` に置換。
   - `find-pure-int-fns` で `scope-exprs` 走査を行う**前に**、有効引数チェック (`rtyper-valid-int-params?`)・局所 `pure-int-expr?`・パラメータ出現 (`rtyper-all-params-occur?`)・自己本体エスケープチェック・局所不動点 (`rtyper-prune-pure-cands`) を実行し、生存候補が 0 件なら即座に `'()` を返却。生存候補のみに限定して `scope-exprs` 走査を行い、脱落があれば再度 `rtyper-prune-pure-cands` で伝播させる。
   - `(<= (expr-size body) 40)` をバジェット打ち切り型 `(expr-size-le? body 40)` に置換。
   - `rtyper-expr-scoped` の `letrec` における `find-pure-int-fns` の重複実行を排除。
2. **`nanopass.scm` / `nanopass_meta.scm` の直接パターンコンパイル＆ゼロアロケーション走査化**:
   - エリプシス（`...`）、`unquote-splicing`、およびカタモルフィズムを含まないパターンを、コンパイル時に `pair?` / `car` / `cdr` / `eq?` / `null?` / `equal?` / `let` のネスト木へと直接展開する `nanopass-compile-direct-pattern` を実装（シャドウイング防止のため新鮮な `__dpr_` ルート変数束縛を使用し、一致時のみ `(cons #t ...)` でラップして `#f` 返却ルールとの意味論的一致を保証）。
   - `nanopass-sliding-window-pass` がルール未発火時（`changed? == #f`）に `acc` をコンスせず、そのまま `(cons insts #f)` を返すことで不変時のリストコピーを完全にゼロ化（初回発火時のみ `nanopass-rev-prefix-until` で前方要素を回収）。
   - `lir-peephole-reg?` を x86-64 の 16 レジスタシンボルに対する `case` 即時判定に高速化。

---

## 5. 完了条件 / Success Criteria (DoD)
- [x] `ULISP_BENCH_PASSES=1`（`ulisp/build/compiler_base_in.scm`）において：
  - `pass-090-rtyper` $\le 60\text{ ms}$（基準 `314.40 ms` → 実測 **`10.99 ms`**）
  - `pass-133-lir-peephole` $\le 180\text{ ms}$ かつヒープ割り当て $\le 150,000\text{ KB}$（基準 `387.64 ms` / `450,186 KB` → 実測 **`17.80 ms` / `13,256 KB`**）
  - 合計コンパイル時間 $\le 1,350\text{ ms}$（基準 `1,793.31 ms` → 実測 **`677.81 ms`**）
- [x] `make -C ulisp compiler lint_sexpr test_nanopass test_passes test_pass_manager` がエラー 0 件で全件 PASS すること。
- [x] `make -C ulisp bootstrap_verify` で Stage 2 と Stage 3 の bit-for-bit 不動点一致が確認されること。
- [x] `make py_compile && make static_analysis` が PASS すること。
- [x] ドキュメント内のすべてのリンクが相対パスで記述されていること。

---

## 6. 実測検証結果 / Verification & Benchmark Results

### 6.1 ベンチマーク比較 (`ULISP_BENCH_PASSES=1`, 更新済み `ulisp/bin/ulisp-boot`)

| 対象モジュール / 指標 | 改修前 (After #815) | 改修後 (#816) | 改善倍率 |
| --- | ---: | ---: | ---: |
| `compiler_base_in.scm` / `pass-090-rtyper` | 314.40 ms | **10.99 ms** (16,074 KB) | **28.6x 高速化** |
| `compiler_base_in.scm` / `pass-133-lir-peephole` | 387.64 ms / 450,186 KB | **17.80 ms / 13,256 KB** | **21.8x 高速 / 34.0x ヒープ削減** |
| `compiler_base_in.scm` / 合計時間 | 1,793.31 ms | **677.81 ms** (648,584 KB) | **2.65x 高速化** |
| `lir_passes_in.scm` / `pass-133-lir-peephole` | 832.97 ms / 829,240 KB | **16.88 ms / 12,055 KB** | **49.3x 高速 / 68.8x ヒープ削減** |
| `lir_passes_in.scm` / 合計時間 | — | **675.84 ms** (800,431 KB) | — |
| `compiler_driver_in.scm` / 合計時間 | — | **64.65 ms** (71,373 KB) | — |
| `frontend_passes_in.scm` / 合計時間 | — | **1,565.31 ms** (1,425,460 KB) | — |

### 6.2 品質ゲート・テスト結果
- `make -C ulisp compiler lint_sexpr test_nanopass test_passes test_pass_manager`:
  - `lint_sexpr`: S 式括弧バランス検証全件 PASS (エラー 0 件)
  - `test_nanopass`: Nanopass Framework 294 / 294 tests passed (Section 26 追加分含む)、Nanopass Phase 4: 48 / 48 tests passed
  - `test_passes`: 全 39 個 1:1 Nanopass 単体テスト PASS、全 147 パス別単体テスト PASS
  - `test_pass_manager`: 115 / 115 assertions passed
- `make -C ulisp bootstrap_verify && make -C ulisp build/ulisp-modular`: Stage 2 と Stage 3 の出力 assembly が bit-for-bit 完全一致 (`cmp -s build/stage2_compiler.s build/stage3_compiler.s`)、`bin/ulisp-boot` および `build/ulisp-modular` を更新・リンク完了
- `make py_compile && make static_analysis`: PASS (`xenon` グレード A、`mypy --strict` 617 ファイルエラー 0 件)
