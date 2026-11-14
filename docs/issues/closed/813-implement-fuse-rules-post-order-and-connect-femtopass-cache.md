---
ID: 813
種別: Feature
優先度: High
ステータス: Closed
---

# [FEAT/ENH] fuse-rules 後順 (Bottom-Up) 融合モード `:order post` の導入と 050_cp0 / 100_contify 移行および Femtopass 解析キャッシュ実接続 (ID: 813)

## 1. 概要 / Summary
Nanopass フレームワーク（DSN-33-01）において、Pass 050 (CP0) および Pass 100 (Contify) は Picopass / Femtopass 規則が定義されているものの、現在の `fuse-rules` は親から子へ規則を適用する前順（Pre-order / Top-down）のみをサポートしているため、定数畳み込みや局所簡約のような「子ノードを最適化した後に親ノードに規則を適用する」後順（Post-order / Bottom-up）処理を表現できず、手書きの再帰走査（約90行）が残存している。

また、手書き再帰によりノードを毎回再構築しているため、`nanopass_meta.scm` に実装済みの `eq?` 構造共有（T1.3）や Term Memoization（T5.2）がバイパスされている。
さらに、`100_contify.scm` の `femto-contifiable?` は未接続のままであり、Femtopass 解析キャッシュ機構（T5.1）が本番パイプラインで活用されていない。

本 Issue では以下のフレームワーク機能およびパス移行を実施する：
1. `fuse-rules` に後順融合モード（`:order post` / `fuse-post-rules`）を追加し、カタモルフィズムによる子ノード走査・構造共有後の親ルール O(1) ディスパッチおよび局所再ディスパッチ（Local Re-dispatch）を実現。
2. `050_cp0.scm` の手書き再帰（L161–L212）および `%program` 手動走査ボイラープレート（L218–L234）を撤去し、後順 `(fuse-rules :order post ...)` による完全宣言的融合に置換。各 Picopass に適切な `guard` 条件を付与し、未変更サブツリーの `eq?` 構造共有を 100% 維持する。
3. `100_contify.scm` の手書き再帰 `contify-expr`（L53–L92）、`contify-letrec`（L153–L167）、および `%program` 手動走査を後順 `(fuse-rules :order post rule-contify-letrec)` に移行し、`rule-contify-letrec` から `femto-contifiable?` を呼び出すよう接続。
4. `define-femtopass` の `:reads` 依存関係に基づく `femto-register-attr-dependencies!` / `femto-get-cached-attr` 自動配線と、Picopass 発火時（`record-picopass-firing!`）の `femto-cache-invalidate-tags!` / `femto-cache-invalidate-node!` 自動無効化を確立し、T5.1 解析キャッシュを実稼働させる。

---

## 2. トレーサビリティ / Traceability
- [DSN-33-01 Nanopass/Picopass DAG アーキテクチャ仕様書 Section 3.1 & 5.1 & 5.2](../../designs/DSN-33-01-ulisp_pipeline_pass_nanopass_picopass_dag_architecture.md)
  - T3.1: define-pass 内 fuse-rules 構文と Head-Tag 別 O(1) case ディスパッチ生成
  - T5.1: Femtopass 解析キャッシュとルール依存関係 DAG による無効化プロトコル
  - T5.2: HIR/MIR Hash-Consing Term DAG と訪問済みノード O(1) メモ化走査
- 関連 Issue:
  - [Issue #759 (fuse-rules O(1) case ディスパッチ)](759-implement-fuse-rules-and-head-tag-o1-dispatch.md)
  - [Issue #765 (Femtopass 解析キャッシュ維持)](765-implement-rule-dependency-dag-and-femtopass-cache-invalidation.md)
  - [Issue #766 (Term DAG と CP0/Contify Picopass 化)](766-implement-hash-consing-term-dag-and-memoized-catamorphism.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [ulisp/compiler/nanopass.scm](../../../ulisp/compiler/nanopass.scm) (`fuse-rules :order post` 構文解析、`nanopass-build-rules-cascade-with-order`、`define-femtopass` キャッシュ統合)
- [x] [ulisp/compiler/nanopass_meta.scm](../../../ulisp/compiler/nanopass_meta.scm) (`nanopass-fallback-transform-node` における `%cont-fun` / `define` 構造共有対応、`record-picopass-firing!` における Femtopass キャッシュ自動無効化)
- [x] [ulisp/frontend/040_analysis.scm](../../../ulisp/frontend/040_analysis.scm) (`analyze-escapes` および `tail-calls-only-impl` への `%cont-fun` / `%cont-call` 節追加によるボトムアップ Contify 解析対応)
- [x] [ulisp/frontend/050_cp0.scm](../../../ulisp/frontend/050_cp0.scm) (Picopass `guard` 精緻化、手書き `cp0-opt` / `cp0-optimize` の `fuse-rules :order post` への完全置換)
- [x] [ulisp/frontend/100_contify.scm](../../../ulisp/frontend/100_contify.scm) (手書き `contify-expr` / `contify-letrec` / `contify-all` の `fuse-rules :order post` 移行、`femto-contifiable?` 接続)
- [x] [ulisp/tests/test_nanopass_framework.scm](../../../ulisp/tests/test_nanopass_framework.scm) (`fuse-rules :order post` 単体テスト、`cp0-optimize` 構造共有 `eq?` 検証、`femto-contifiable?` キャッシュヒット検証)
- [x] [ulisp/tests/passes/test_050_cp0.scm](../../../ulisp/tests/passes/test_050_cp0.scm) (CP0 最適化・構造共有回帰テスト)
- [x] [ulisp/tests/passes/test_100_contify.scm](../../../ulisp/tests/passes/test_100_contify.scm) (Contify 最適化・ネストループ・Femtopass キャッシュ回帰テスト)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/813-implement-fuse-rules-post-order-and-connect-femtopass-cache`

1. **`ulisp/compiler/nanopass_meta.scm` の拡張**:
   - `nanopass-fallback-transform-node` (L1669–L1737) において、`((set! define) ...)` および `((%cont-fun) ...)` ケースを追加し、`%cont-fun` の第1引数（関数名）および第2引数（仮引数リスト `(params ...)`）を式として誤走査せず、`f-body` と `in-body` のみを `nanopass-cons-sharing` で再帰変換するようにする。
   - `nanopass-schema-transform-node` (L1647) において、汎用適用生成規則 `(e0 e1 ...)` に `%cont-fun` がマッチした場合は `nanopass-fallback-transform-node` へ委譲し、仮引数リストの保護を保証する。
   - `record-picopass-firing!` (L619) において、`*femto-analysis-cache*` が空でない場合（`(pair? (car *femto-analysis-cache*))`）、発火した `rule-name` の記述子から `rule-writes` / `rule-eliminates` を取得して `femto-cache-invalidate-tags!` および `(femto-cache-invalidate-node! old-ir)` を自動実行する。

2. **`ulisp/compiler/nanopass.scm` の拡張**:
   - `nanopass-parse-fuse-rules-specs` ヘルパを追加し、`fuse-rules` / `fuse-tree-rules` の引数リスト先頭に `:order post` / `:order :post` / `:order pre` / `:order :pre` が指定された場合に `(cons order clean-specs)` を返すよう実装する。
   - `nanopass-extract-all-pass-rule-specs` (L593) および `nanopass-flatten-nt-rules` (L442) で `nanopass-parse-fuse-rules-specs` を用いてオプションキーワードを除外してルール記述子を抽出する。
   - `nanopass-nt-rules-detect-order` ヘルパを追加し、NT 節内の `(fuse-rules :order post ...)` から走査順序（`'pre` または `'post`）を判定する。
   - `nanopass-build-rules-cascade-with-order` を実装（既存の `nanopass-build-rules-cascade` は `'pre` モードのラッパーとして後方互換を維持）：
     - `:pre` モード（デフォルト）：従来通りルールカスケードを先行評価し、不一致時のフォールバックとして `cata-call`（`nanopass-catamorphism-step`）を実行。
     - `:post` モード：先に `(let ((ir-var cata-call)) ...)` で子ノードをボトムアップ走査・`eq?` 構造共有再構築し、その結果の `ir-var` に対して O(1) Head-Tag `case` ディスパッチおよび局所再ディスパッチ（`__redispatch_loop_`、不一致時のフォールバックは `ir-var` 自身）を適用する。
   - `nanopass-bind-matched-vars` または `nanopass-compile-single-rule-cascade` において、ルール本体・ガード内で現在の対象ノードを参照できるよう `ir` 束縛（パターン変数に含まれない場合）を保持する。
   - `nanopass-expand-rule-dsl` (L889) において、`rule-kind` が `'femto` の場合：
     - `:reads` タグリストを `(femto-register-attr-dependencies! 'name 'reads)` で自動登録する。
     - 追加属性引数を持たない単項 Femtopass（`(null? in-attrs)`）の本体を `(femto-get-cached-attr 'name ir (lambda () ...))` でラップし、同一 AST ノードに対する再評価を O(1) キャッシュヒットさせる。

3. **`ulisp/frontend/040_analysis.scm` の補強**:
   - ボトムアップ順で内側の `letrec` が先に `%cont-fun` / `%cont-call` へ変換された場合でも外側の `letrec` の Contify 可否判定（`contifiable-binding?`）が正確に動作するよう、`analyze-escapes` (L86) と `tail-calls-only-impl` (L155) に `(%cont-fun ,f-name (,params ...) ,f-body ,in-body)` および `(%cont-call ,target ,es ...)` の節を追加する。

4. **`ulisp/frontend/050_cp0.scm` のリファクタリング**:
   - 各 Picopass (`rule-cp0-prune-if-3`, `rule-cp0-prune-if-2`, `rule-cp0-flatten-begin`, `rule-cp0-dead-let`, `rule-cp0-dead-letrec`, `rule-cp0-call-values`, `rule-cp0-const-fold`) に発火条件の `(guard ...)` を明示し、変換不要なノードでは発火せずカタモルフィズムの `eq?` 構造共有結果をそのまま返すようにする。
   - `cp0-opt` の手書き `Expr` 節（52行）を `(fuse-rules :order post ...)` の宣言1つに置換し、`cp0-optimize` の重複 `%program` 走査を `(cp0-opt form)` 呼び出しに統合する。

5. **`ulisp/frontend/100_contify.scm` のリファクタリング**:
   - `rule-contify-letrec` において、直接の `contifiable-binding?` 呼び出しを `(femto-contifiable? ir)` 呼び出しに置き換える。
   - 手書きの `contify-expr`（L53–L92）および `contify-letrec`（L153–L167）を撤去し、`(define-pass contify-opt : L_core (ir) -> L_core () (fuse-rules :order post rule-contify-letrec))` に統合する。

6. **テストとブートストラップ検証**:
   - `ulisp/tests/test_nanopass_framework.scm` に `:order post` 融合テスト、`cp0-optimize` の未変更サブツリー `eq?` 構造共有テスト、および `femto-contifiable?` のキャッシュヒット＆無効化テストを追加。
   - `make -C ulisp compiler`、`make -C ulisp lint_sexpr`、`make -C ulisp test_passes`、`make -C ulisp bootstrap_verify` を実行して全件 PASS を確認する。

---

## 5. 完了条件 / Success Criteria (DoD)
- [x] `fuse-rules` が `:order post`（後順融合）オプションをトップレベルおよび NT 節内の双方でサポートし、子ノード最適化後の親ルール O(1) ディスパッチおよび局所再ディスパッチが機能すること。
- [x] `050_cp0.scm` の `cp0-opt` における手書き構文走査（約50行）および `%program` ボイラープレートが撤去され、`fuse-rules :order post` による宣言的定義に置換されていること。
- [x] `cp0-optimize` において未変更 AST ノードのポインタ同一性（`eq?` 構造共有）が保持されることがテストで実証されること。
- [x] `100_contify.scm` の手書き走査 `contify-expr` / `contify-letrec` が `fuse-rules :order post` に置換され、`rule-contify-letrec` から `femto-contifiable?` が呼び出されていること。
- [x] `define-femtopass` が `*femto-analysis-cache*` および `femto-register-attr-dependencies!` と自動連携し、`contify-all` 実行時および単体テストで `femto-cache-stats` のヒット・ミス記録および Picopass 発火時のタグ無効化が検証されること。
- [x] `make -C ulisp compiler` で `compiler.scm` が正常に生成され、`make -C ulisp lint_sexpr` がエラー 0 件であること。
- [x] `make -C ulisp test_passes`、`make -C ulisp test_pass_manager`、`make -C ulisp test_concurrency` が全件 PASS すること。
- [x] `make -C ulisp bootstrap_verify` で Stage 2 と Stage 3 の bit-for-bit 不動点一致が確認されること。
- [x] `make py_compile && make static_analysis` が 100% PASS すること。
- [x] ドキュメント内のすべてのリンクが相対パスで記述されていること。
