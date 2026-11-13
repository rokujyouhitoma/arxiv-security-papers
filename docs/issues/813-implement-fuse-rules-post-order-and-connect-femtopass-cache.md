---
ID: 813
種別: Feature
優先度: High
ステータス: Open (New)
---

# [FEAT/ENH] fuse-rules 後順 (Bottom-Up) 融合モード `:order post` の導入と 050_cp0 / 100_contify 移行および Femtopass 解析キャッシュ実接続 (ID: 813)

## 1. 概要 / Summary
Nanopass フレームワーク（DSN-33-01）において、Pass 050 (CP0) および Pass 100 (Contify) は Picopass / Femtopass 規則が定義されているものの、現在の `fuse-rules` は親から子へ規則を適用する前順（Pre-order / Top-down）のみをサポートしているため、定数畳み込みや局所簡約のような「子ノードを最適化した後に親ノードに規則を適用する」後順（Post-order / Bottom-up）処理を表現できず、手書きの再帰走査（約90行）が残存している。

また、手書き再帰によりノードを毎回再構築しているため、`nanopass_meta.scm` に実装済みの `eq?` 構造共有（T1.3）や Term Memoization（T5.2）がバイパスされている。
さらに、`100_contify.scm` の `femto-contifiable?` は未接続のままであり、Femtopass 解析キャッシュ機構（T5.1）が本番パイプラインで活用されていない。

本 Issue では以下のフレームワーク機能およびパス移行を実施する：
1. `fuse-rules` に後順融合モード（`:order post` または `fuse-post-rules`）を追加し、カタモルフィズムによる子ノード走査・構造共有後の親ルール O(1) ディスパッチを実現。
2. `050_cp0.scm` の手書き再帰（L161–L212）および `%program` ボイラープレートを撤去し、後順 `fuse-rules` による完全宣言的融合に置換。
3. `100_contify.scm` の手書き再帰（L53–L92）を後順 `fuse-rules` に移行し、`femto-contifiable?` を `contifiable-binding?` の直接呼び出し箇所へ接続。
4. `define-femtopass` の `:reads` / `:writes` 依存関係に基づく `femto-get-cached-attr` / `femto-cache-invalidate-tags!` 自動配線を確立し、T5.1 解析キャッシュを実稼働させる。

---

## 2. トレーサビリティ / Traceability
- [DSN-33-01 Nanopass/Picopass DAG アーキテクチャ仕様書 Section 3.1 & 5.1 & 5.2](../designs/DSN-33-01-ulisp_pipeline_pass_nanopass_picopass_dag_architecture.md)
  - T3.1: define-pass 内 fuse-rules 構文と Head-Tag 別 O(1) case ディスパッチ生成
  - T5.1: Femtopass 解析キャッシュとルール依存関係 DAG による無効化プロトコル
  - T5.2: HIR/MIR Hash-Consing Term DAG と訪問済みノード O(1) メモ化走査
- 関連 Issue:
  - [Issue #759 (fuse-rules O(1) case ディスパッチ)](closed/759-implement-fuse-rules-and-head-tag-o1-dispatch.md)
  - [Issue #765 (Femtopass 解析キャッシュ維持)](closed/765-implement-rule-dependency-dag-and-femtopass-cache-invalidation.md)
  - [Issue #766 (Term DAG と CP0/Contify Picopass 化)](closed/766-implement-hash-consing-term-dag-and-memoized-catamorphism.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [ulisp/compiler/nanopass.scm](../../ulisp/compiler/nanopass.scm) (fuse-rules `:order post` 構文拡張、define-femtopass キャッシュ呼び出しコード生成)
- [ ] [ulisp/compiler/nanopass_meta.scm](../../ulisp/compiler/nanopass_meta.scm) (後順走査ヘルパおよび Femtopass キャッシュ連携)
- [ ] [ulisp/frontend/050_cp0.scm](../../ulisp/frontend/050_cp0.scm) (手書き `cp0-opt` 手動走査の `fuse-rules :order post` への完全置換)
- [ ] [ulisp/frontend/100_contify.scm](../../ulisp/frontend/100_contify.scm) (手書き `contify-expr` の移行、`femto-contifiable?` 接続)
- [ ] [ulisp/tests/test_nanopass_framework.scm](../../ulisp/tests/test_nanopass_framework.scm) (fuse-rules 後順モードおよび Femtopass キャッシュヒット率検証)
- [ ] [ulisp/tests/passes/test_050_cp0.scm](../../ulisp/tests/passes/test_050_cp0.scm) (CP0 最適化回帰テスト)
- [ ] [ulisp/tests/passes/test_100_contify.scm](../../ulisp/tests/passes/test_100_contify.scm) (Contify 最適化回帰テスト)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/813-implement-fuse-rules-post-order-and-connect-femtopass-cache`

1. **nanopass.scm の拡張**:
   - `nanopass-extract-all-pass-rule-specs` および `nanopass-flatten-nt-rules` において `(fuse-rules :order post r1 r2 ...)` を解析可能にする。
   - `nanopass-build-rules-cascade` に `order` 引数（デフォルト `:pre`、または `:post`）を追加。
   - `:post` モードでは、ノード `ir-var` に対して先にカタモルフィズム再帰 `nanopass-catamorphism-step`（未変更時は `eq?` 構造共有を保持）を実行し、その結果ノードに対して Head-Tag O(1) `case` ディスパッチを適用するコードを展開する。
   - `define-femtopass` 展開時に、引数ノードに対する `femto-get-cached-attr` による結果取得とキャッシュ保存コードを自動注入し、Picopass 発火時の `femto-cache-invalidate-tags!` との連動を担保する。
2. **050_cp0.scm のリファクタリング**:
   - `cp0-opt` 内の 52 行におよぶ手書き `Expr` 生成規則を `(fuse-rules :order post ...)` に置き換える。
   - 手動の `(list 'if opt-test opt-then opt-else)` などの再構築を撤去し、Nanopass 本体の `nanopass-cons-sharing` による構造共有を 100% 活用する。
3. **100_contify.scm のリファクタリング**:
   - `contify-expr` の手書き走査を整理し、`rule-contify-letrec` から `femto-contifiable?` を通じて解析を実行するように接続。
4. **検証**:
   - `make -C ulisp test_passes`, `make -C ulisp test_pass_manager`, `make -C ulisp test_concurrency`, `make -C ulisp bootstrap_verify` を実行し、全件 PASS および 3-Stage ブートストラップ不動点を確認する。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] `fuse-rules` が `:order post`（後順融合）オプションをサポートし、子ノード最適化後の親ルール適用が宣言的に記述できること。
- [ ] `050_cp0.scm` の `cp0-opt` における手書き構文走査（約50行）が撤去され、`fuse-rules :order post` による定義に置換されていること。
- [ ] `100_contify.scm` において `femto-contifiable?` が実際に呼び出され、Femtopass 解析キャッシュが利用されていること。
- [ ] `femto-cache-stats` のヒット数が記録され、T5.1 キャッシュ機構が機能していることがテストで実証されること。
- [ ] `make -C ulisp compiler` で `compiler.scm` が正常に生成され、`make -C ulisp lint_sexpr` がエラー 0 件であること。
- [ ] `make -C ulisp test_passes` および `make -C ulisp test_concurrency` が全件 PASS すること。
- [ ] `make -C ulisp bootstrap_verify` で Stage 2 と Stage 3 の bit-for-bit 不動点一致が確認されること。
- [ ] `make py_compile && make static_analysis` が 100% PASS すること。
- [ ] ドキュメント内のすべてのリンクが相対パスで記述されていること。
