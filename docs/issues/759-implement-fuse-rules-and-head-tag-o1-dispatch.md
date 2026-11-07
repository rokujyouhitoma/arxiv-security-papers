---
ID: 759
種別: Feature
優先度: High
ステータス: Open (New)
---

# [FEAT/ENH] define-pass 内 fuse-rules 構文と先頭タグ (Head-Tag) 別 O(1) case ディスパッチ生成エンジンの実装 (DSN-33-01 T3.1) (ID: 759)

## 1. 概要 / Summary

[[DSN-33-01] ULisp 階層型パス融合 ＆ DAG 最適化基盤設計書](../designs/DSN-33-01-ulisp_pipeline_pass_nanopass_picopass_dag_architecture.md) の第 4.2 節およびタスク **T3.1** に基づき、`define-pass` 内に複数の Picopass / Femtopass / Attopass を融合する `(fuse-rules ...)`（別名 `fuse-tree-rules`）構文を導入し、従来の $O(R)$ 線形 `if` カスケード（`nanopass-build-rules-cascade`）に代わる **先頭タグ（Head Symbol）別 $O(1)$ `case` ディスパッチ生成エンジン** を実装する。

現在、`030_desugar.scm` のような約 100 個のルールを持つパスでは、変数参照 `x` や定数、`if` ノードに対しても毎回 100 回の `nanopass-try-clause` が線形に呼び出されている。本 Issue により、ルール数が何百個に増えても 1 ノードあたり $O(1)$ で該当ルールバケットへ直撃するコードを生成する。

---

## 2. トレーサビリティ / Traceability

- 関連設計書:
  - [[DSN-33-01] ULisp 階層型パス融合 ＆ DAG 最適化基盤設計書](../designs/DSN-33-01-ulisp_pipeline_pass_nanopass_picopass_dag_architecture.md) (第 4.2 節, 第 4.4 節, 第 4.5 節, 第 8.4 節, 第 9.2 節 タスク **T3.1**)
- 依存関係:
  - 先行 Issue: [Issue #756 (T2.1: Rule Descriptor と Picopass DSL 実装)](756-implement-rule-descriptor-and-picopass-femtopass-attopass-dsl.md), [Issue #757 (T2.2: 関数合成コンビネータ群)](757-implement-picopass-strategy-combinators.md), [Issue #758 (T2.3: Pass 015 への新 DSL 統合)](758-integrate-picopass-dsl-into-pass-015-expander.md)
  - 後続 Issue: [Issue #760 (T3.2: 局所再適用と extends 整合性検査)](760-implement-local-redispatch-and-extends-eliminates-validation.md), [Issue #763 (T4.2: 030_desugar.scm の fuse-rules 置換)](763-replace-desugar-030-duplicate-rules-with-fuse-rules.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files

- [ ] [ulisp/compiler/nanopass.scm](../../ulisp/compiler/nanopass.scm)
- [ ] [ulisp/compiler/nanopass_meta.scm](../../ulisp/compiler/nanopass_meta.scm)
- [ ] [ulisp/tests/test_nanopass_framework.scm](../../ulisp/tests/test_nanopass_framework.scm)

---

## 4. 実装方針 / Implementation Plan

Target Branch: `feat/759-implement-fuse-rules-o1-dispatch`

1. **`define-pass` における `(fuse-rules ...)` / `(fuse-tree-rules ...)` 節のパース**:
   - `nanopass-expand-define-pass-with-trace`（`nanopass.scm`）において、非終端記号トランスフォーマの直接記述に加え、`(fuse-rules rule1 rule2 ...)` 節を受け付けるように拡張する。
   - また、既存のインライン非終端記号ルール群に対しても同じ Head-Tag バケット分類器を適用可能にし、すべての `define-pass` が $O(1)$ ディスパッチの恩恵を受けられるようにする。
2. **先頭シンボル（Head-Tag）バケット分類と `case` コード生成**:
   - ルールリストを以下の3カテゴリに分類する：
     1. **固定先頭シンボルルール**: パターンが `(sym ...)`（`sym` は `unquote` や `_` でない具体的なシンボル）で始まるもの $\to$ `sym` ごとのバケット（例: `letrec` バケット、`cond` バケット）へ格納（元の定義順序を保持）。
     2. **ペア汎用ルール**: パターンがペアだが先頭が `,op` や `((,a ...) ...)` のもの $\to$ ペアフォールバックリストへ格納。
     3. **アトム／ワイルドカードルール**: パターンが `,x` や定数のもの $\to$ アトムルールリストへ格納。
   - 生成コードでは、まず `(pair? ir)` と `(symbol? (car ir))` を判定し、`(case (car ir) ((tag1) <tag1バケット>) ((tag2) <tag2バケット>) ...)` で該当バケットのルールのみを試行し、不発ならペア汎用ルール $\to$ `nanopass-catamorphism-step` へフォールバックさせる。

---

## 5. 完了条件 / Success Criteria (DoD)

- [ ] `(fuse-rules r1 r2 ...)` を用いた `define-pass` が、複数の Picopass を単一の走査関数へ正しく融合できること。
- [ ] 展開後のコードが `(case (car ir) ...)` による先頭タグ別ディスパッチ構造を持ち、無関係なタグのルールに対して `nanopass-try-clause` が呼ばれないこと。
- [ ] 既存の全 `define-pass` 単体テストおよび新規追加の `fuse-rules` テストが 100% PASS すること。

