---
ID: 763
種別: Feature
優先度: High
ステータス: Open (In Progress)
---

# [FEAT/ENH] 030_desugar.scm (desugar-all) の手動ディスパッチ約205行撤去と fuse-rules による全規則宣言的自動融合への完全置換 (DSN-33-01 T4.2) (ID: 763)

## 1. 概要 / Summary

[[DSN-33-01] ULisp 階層型パス融合 ＆ DAG 最適化基盤設計書](../designs/DSN-33-01-ulisp_pipeline_pass_nanopass_picopass_dag_architecture.md) の第 1.1 節（Nanopass の粒度ジレンマ）、第 4.1〜4.3 節（Pass Fusion エンジンと先頭タグ $O(1)$ ディスパッチ・局所再適用）、第 6.2 節（中間言語階層と全パス配置マップ）、および第 9.2 節タスク **T4.2** に基づき、`ulisp/frontend/030_desugar.scm` の統括脱糖パス `desugar-all` を抜本的にリファクタリングする。

先行する [Issue #762](closed/762-migrate-desugar-passes-026-to-029-to-picopass.md) (Task T4.1) において、フロントエンド脱糖サブモジュール群（Pass 026 Constructors, Pass 027 Conditionals, Pass 028 Bindings, Pass 029 Dynamic）の全構文変換規則は、第一級オブジェクトである **`define-picopass`**（および **`define-attopass`**）として独立に再定義された。

しかしながら、本番コンパイラパイプラインの中核である `ulisp/frontend/030_desugar.scm`（`desugar-all`）には、依然として手書きのディスパッチ関数群：
- `desugar-dispatch-dyn` (L19-74)
- `desugar-dispatch-ctors` (L75-106)
- `desugar-dispatch-bindings` (L107-188)
- `desugar-dispatch-expr` (L189-223)

にわたる**約205行の手作業 `case` 分岐と `nanopass-catamorphism-step` のハードコード呼び出し**が残存している。

本 Issue では、これら 4 つの個別ディスパッチ関数を完全に撤去し、先行ロードされている Pass 026〜029 の全 Picopass / Attopass 規則群（合計 31 ルール）を **`(fuse-rules ...)` 構文による単一の宣言的自動融合** へと置き換える。
これにより、手動ディスパッチチェーンの冗長性と二重管理を根絶し、Nanopass コンパイラ基盤が提供する $O(1)$ Head-Tag ディスパッチテーブル生成エンジンと有界局所再適用（Local Re-dispatch）の恩恵を本番パイプラインへ直接統合する。

---

## 2. トレーサビリティ / Traceability

- **関連設計書**:
  - [[DSN-33-01] ULisp 階層型パス融合 ＆ DAG 最適化基盤設計書](../designs/DSN-33-01-ulisp_pipeline_pass_nanopass_picopass_dag_architecture.md)
    - 第 1.1 節（Nanopass の粒度ジレンマ）
    - 第 2.3 節（4階層の責務と入出力契約: Picopass, Nanopass, Pass）
    - 第 4.1 節（Pass Fusion エンジン: 複数 Nanopass / Picopass の自動インライン融合）
    - 第 4.2 節（先頭タグ $O(1)$ ディスパッチテーブル生成）
    - 第 4.3 節（有界局所再適用 Local Re-dispatch とカタモルフィズム）
    - 第 6.2 節（エンドツーエンド中間言語階層と全パス配置マップ）
    - 第 8.2 節（課題①: HIR 8構文ハードコードの撤去と明示的脱糖ルール）
    - 第 9.2 節（Phase 4 タスク **T4.2**）
- **依存関係**:
  - **先行 Issue**:
    - [Issue #759](closed/759-implement-fuse-rules-and-head-tag-o1-dispatch.md) (T3.1: `fuse-rules` 構文と Head-Tag $O(1)$ ディスパッチ生成エンジンの実装) (Closed)
    - [Issue #760](closed/760-implement-local-redispatch-and-extends-eliminates-validation.md) (T3.2: 5ステップ融合サイクルの局所再適用と `extends (-)` 対 `eliminates` 自動整合性検証) (Closed)
    - [Issue #762](closed/762-migrate-desugar-passes-026-to-029-to-picopass.md) (T4.1: フロントエンド脱糖パス 026〜029 の全規則 define-picopass 化と 1行S式単体テスト整備) (Closed)
  - **後続 Issue**:
    - [Issue #764](764-migrate-verifier-to-attopass-and-eliminate-triple-traversal.md) (T4.3: verifier.scm の手書き検証ループの define-attopass 化と Nanopass 融合による三重走査の解消)
    - [Issue #765](765-implement-rule-dependency-dag-and-femtopass-cache-invalidation.md) (T5.1: ルール依存関係 DAG 自動構築・独立ルール自動 Fusion・Femtopass 解析キャッシュ維持の実装)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files

- [ ] [ulisp/frontend/030_desugar.scm](../../ulisp/frontend/030_desugar.scm)
  - 手動ディスパッチ関数（`desugar-dispatch-dyn`, `desugar-dispatch-ctors`, `desugar-dispatch-bindings`, `desugar-dispatch-expr`）の完全撤去（約205行削減）。
  - `desugar-all` を `(fuse-rules ...)` による宣言的 Pass 定義へ刷新。
- [ ] [ulisp/compiler.scm](../../ulisp/compiler.scm)
  - `make -C ulisp compiler` による結合ソース再生成と 3-Stage セルフホスト固定点の検証。
- [ ] [ulisp/tests/passes/test_030_desugar.scm](../../ulisp/tests/passes/test_030_desugar.scm)
  - 既存の 12 グループの単体テストが自動融合された `desugar-all` 上で 100% PASS することの確認。
- [ ] [docs/issues/763-replace-desugar-030-duplicate-rules-with-fuse-rules.md](763-replace-desugar-030-duplicate-rules-with-fuse-rules.md)
  - Issue 仕様・設計・進捗・DoD の維持更新。
- [ ] [docs/issues/README.md](README.md)
  - Issue 台帳（Open Issues テーブル）のステータス更新。

---

## 4. 詳細設計 / Detailed Design

### 4.1 アーキテクチャ上の課題とリファクタリング方針

#### (1) 現状の課題: 手書きディスパッチチェーンの弊害
現在、`030_desugar.scm` は以下のように 4 段階の関数が手動で数珠つなぎに呼び出される構成となっている：
```
desugar-dispatch-expr
  -> (else) desugar-dispatch-bindings
       -> (else) desugar-dispatch-ctors
            -> (else) desugar-dispatch-dyn
                 -> (else) (nanopass-catamorphism-step 'L_src 'L_core 'Expr ir Expr '() '())
```
この構造には以下の重大な欠点がある：
1. **多重ディスパッチオーバーヘッド**: 未知の関数適用や末端の構文において、4 つの関数呼び出しと多段の `case` 探索を順次通過しなければならない。
2. **保守性の乖離**: Pass 026〜029 で新しい構文規則を追加・修正しても、Pass 030 のディスパッチ関数を別途手動で更新しない限り本番パイプラインへ反映されない。
3. **ボイラープレートの氾濫**: 各節で `(Expr ...)` による手動再帰や、引数不一致時の `(nanopass-catamorphism-step ...)` フォールバック記述が散乱している。

#### (2) 改善方針: `(fuse-rules ...)` による宣言的融合
Pass 015〜029 の先行定義において、各構文規則は以下のように完全に独立した `define-picopass` / `define-attopass` としてエクスポートされている：
- **Pass 026 (9 rules)**: `rule-desugar-list`, `rule-desugar-vector`, `rule-desugar-bytevector`, `rule-desugar-string-ops`, `rule-desugar-vector-ops`, `rule-desugar-bytevector-ops`, `rule-desugar-math-variadic`, `rule-desugar-format`, `rule-desugar-cxr`
- **Pass 027 (6 rules)**: `rule-desugar-cond-expand`, `rule-desugar-cond`, `rule-desugar-case`, `rule-desugar-and`, `rule-desugar-or`, `rule-desugar-chain-cmp`
- **Pass 028 (7 rules)**: `rule-desugar-case-lambda`, `rule-desugar-let*`, `rule-desugar-letrec*`, `rule-desugar-named-let`, `rule-desugar-multi-body`, `rule-desugar-do`, `rule-desugar-internal-define`
- **Pass 029 (9 rules)**: `rule-desugar-let-values`, `rule-desugar-define-values`, `rule-desugar-guard`, `rule-desugar-parameterize`, `rule-desugar-delay`, `rule-desugar-parameter-ops`, `rule-desugar-values`, `rule-desugar-error-assume`, `atto-no-unexpanded-let-syntax`

これら 31 個のルールを `desugar-all` に集約し、Nanopass コンパイラフレームワークの `fuse-rules` 展開マクロに委譲する。

---

### 4.2 `030_desugar.scm` の刷新後設計

`030_desugar.scm` は手動ディスパッチ関数をすべて撤去し、以下の極めて宣言的で簡潔な定義（約 45 行）へと集約される：

```scheme
;;; =======================================================================
;;; ULisp Compiler Pass 030: Core Syntax Desugaring & Normalization Pass
;;; Conforms to DSN-33 Architecture Specification & Nanopass Framework Standard
;;; Migrated to Declarative Pass Fusion (fuse-rules) per Issue #763 (DSN-33-01 T4.2).
;;; Automatically combines all 31 Picopasses/Attopasses from Passes 026-029 into
;;; a single O(1) Head-Tag dispatch traversal with local re-dispatch.
;;; =======================================================================

(define-pass desugar-all : L_src (ir) -> L_core ()
  (fuse-rules
    ;; --- Pass 026: Composite Literals & Constructors ---
    rule-desugar-list
    rule-desugar-vector
    rule-desugar-bytevector
    rule-desugar-string-ops
    rule-desugar-vector-ops
    rule-desugar-bytevector-ops
    rule-desugar-math-variadic
    rule-desugar-format
    rule-desugar-cxr

    ;; --- Pass 027: Conditionals & Comparisons ---
    rule-desugar-cond-expand
    rule-desugar-cond
    rule-desugar-case
    rule-desugar-and
    rule-desugar-or
    rule-desugar-chain-cmp

    ;; --- Pass 028: Bindings & Internal Definitions ---
    rule-desugar-case-lambda
    rule-desugar-let*
    rule-desugar-letrec*
    rule-desugar-named-let
    rule-desugar-multi-body
    rule-desugar-do
    rule-desugar-internal-define

    ;; --- Pass 029: Dynamic Environment & Values ---
    rule-desugar-let-values
    rule-desugar-define-values
    rule-desugar-guard
    rule-desugar-parameterize
    rule-desugar-delay
    rule-desugar-parameter-ops
    rule-desugar-values
    rule-desugar-error-assume
    atto-no-unexpanded-let-syntax))
```

---

### 4.3 構文除去カバレッジ自動検証（Eliminates Coverage Validation）

`define-pass` のマクロ展開時、`nanopass-verify-fusion-coverage` が起動し、ソース言語 `L_src` とターゲット言語 `L_core` の差分構文（除去タグ一覧: `quasiquote`, `cond`, `case`, `and`, `or`, `let*`, `letrec*`, `do`, `delay`, `guard`, `let-values`, `parameterize` 等）を自動計算する。
すべての除去構文が 31 個の Picopass のいずれかによってカバーされているか自動検査され、未処理の構文漏れが 0 件であることがコンパイル時に保証される。

---

### 4.4 セキュリティ考慮事項 / Security Considerations

- **CWE-400 (Uncontrolled Resource Consumption / CPU 枯渇防止)**:
  - 局所再適用（Local Re-dispatch）による無限ループを決定的に遮断するため、Nanopass エンジンの Fuel Guard（最大再ディスパッチ制限 16 回、`*nanopass-redispatch-limit*`）が適用される。
- **CWE-674 (Uncontrolled Recursion / 再帰深さ爆発の防止)**:
  - 可変長結合や複雑なマクロ展開結果において、ボトムアップのカタモルフィズム走査とスマート再構築（未変更ノードの構造共有）により、スタック消費量を $O(\text{AST Depth})$ に厳格に抑制する。
- **CWE-1188 (不変条件の強制)**:
  - `atto-no-unexpanded-let-syntax` が本番の `desugar-all` に直接統合されるため、マクロ展開器をすり抜けた未展開構文が中間言語 `L_core` 以降へ漏洩することを決定的に遮断する。

---

## 5. 実装手順 / Implementation Steps

Target Branch: `refactor/763-replace-desugar-030-with-fuse-rules`

- [ ] **Step 1: Feature ブランチ作成と作業環境準備**
  - `refactor/763-replace-desugar-030-with-fuse-rules` ブランチを作成し、現在の `main` から分岐。
- [ ] **Step 2: `030_desugar.scm` の手動ディスパッチ関数撤去と `fuse-rules` 移行**
  - `desugar-dispatch-dyn`, `desugar-dispatch-ctors`, `desugar-dispatch-bindings`, `desugar-dispatch-expr` の全 4 関数（約205行）を削除。
  - `desugar-all` を 31 個の Picopass / Attopass を含む `(fuse-rules ...)` 定義へと書き換え。
- [ ] **Step 3: 単体テスト実行と動作確認**
  - `make -C ulisp test_passes` 内の `test_030_desugar.scm` を実行し、既存の全 12 グループのテストが 100% PASS することを確認。
- [ ] **Step 4: 全 39 パス単体テストバッチ実行**
  - `make -C ulisp test_all_passes` を実行し、全 39 パスの 1:1 テストがエラー 0 件で PASS することを確認。
- [ ] **Step 5: コンパイラ再生成と 3-Stage セルフホスト固定点検証**
  - `make -C ulisp compiler` を実行し、結合ソース `compiler.scm` を再生成。
  - `make -C ulisp bootstrap` を実行し、Stage 2 と Stage 3 の bit-for-bit IDENTICAL 一致およびスモークテスト（42）PASS を確認。
- [ ] **Step 6: リポジトリ品質ゲート検証**
  - `make py_compile` および `make static_analysis` のエラー 0 件を確認。
  - 相対リンク検証（絶対パスリンク 0 件）を確認。
- [ ] **Step 7: ブランチマージとコミット (`git-workflow`)**
  - `refactor/763-replace-desugar-030-with-fuse-rules` をコミットし、`main` へマージ。
- [ ] **Step 8: Issue 台帳更新とクローズ**
  - `docs/issues/763-replace-desugar-030-duplicate-rules-with-fuse-rules.md` をクローズし、`docs/issues/closed/` へ移動。
  - `docs/issues/README.md` を更新。

---

## 6. 完了条件 / Success Criteria (DoD)

1. [ ] **手動ディスパッチの完全撤去**: `030_desugar.scm` から `desugar-dispatch-*` 4 関数（約205行）が完全に削除され、純粋な `(fuse-rules ...)` 定義となっていること。
2. [ ] **31 規則の完全統合**: Pass 026〜029 で定義されたすべての Picopass / Attopass が漏れなく `desugar-all` の `fuse-rules` に指定されていること。
3. [ ] **Pass 030 単体テスト 100% PASS**: `test_030_desugar.scm` の全テストが回帰なく完全 PASS すること。
4. [ ] **全 39 パス回帰なし**: `make -C ulisp test_all_passes` が 0 failures で全件 PASS すること。
5. [ ] **3-Stage セルフホスティング固定点**: `make -C ulisp bootstrap` が bit-for-bit 完全一致で成功し、スモークテスト（42）が正常完了すること。
6. [ ] **静的解析・相対リンク品質**: `make py_compile`、`make static_analysis` がエラー 0 件で通過し、絶対パスリンクが 0 件であること。
