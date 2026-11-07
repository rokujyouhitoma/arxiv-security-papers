---
ID: 760
種別: Feature
優先度: High
ステータス: Open (New)
---

# [FEAT/ENH] 5ステップ融合サイクルの局所再適用 (Local Re-dispatch) と extends (-) 対 eliminates 自動整合性検証の実装 (DSN-33-01 T3.2) (ID: 760)

## 1. 概要 / Summary

[[DSN-33-01] ULisp 階層型パス融合 ＆ DAG 最適化基盤設計書](../designs/DSN-33-01-ulisp_pipeline_pass_nanopass_picopass_dag_architecture.md) の第 4.1 節、第 4.3 節（(1) 局所再適用）、第 8.3 節（(1) 自動整合性クロスチェック）、およびタスク **T3.2** に基づき、以下の2つの核心機能を実装する：

1. **5ステップ標準融合サイクルと多段脱糖のための局所再適用（Local Re-dispatch）**:
   - 1ノード訪問時に「①事前 `attopass` 群 $\to$ ②`femtopass` 属性計算 $\to$ ③`picopass` $O(1)$ ディスパッチ ＋ マッチ時の局所再適用（Re-dispatch） $\to$ ④カタモルフィズム自動再帰 ＋ 構造共有 $\to$ ⑤事後 `attopass` 群」の5ステップを実行する。
   - 特に、ある Picopass（例: `rule-desugar-case`）が別の脱糖対象構文（例: `or` や複数式 `let`）を含むノードを生成した場合、Picopass 側で明示的に `(Expr ...)` を呼ばなくても、融合エンジン側で生成ノードに対して自動的にディスパッチを再適用し、1回のパスで完全に $L_{\text{out}}$ まで引き下げる。
2. **`define-language` の `extends (-)` と Picopass 群の `eliminates` の自動整合性検証**:
   - `define-pass` が $L_{\text{in}} \to L_{\text{out}}$ を宣言し `(fuse-rules ...)` を用いている際、`(language-diff L_in L_out)` の `removed`（`-` で除去宣言された構文先頭シンボル）が、融合された Picopass 群の `eliminates`（または `head-tags`）によってすべてカバーされているかを展開時に検証する。

---

## 2. トレーサビリティ / Traceability

- 関連設計書:
  - [[DSN-33-01] ULisp 階層型パス融合 ＆ DAG 最適化基盤設計書](../designs/DSN-33-01-ulisp_pipeline_pass_nanopass_picopass_dag_architecture.md) (第 4.1 節, 第 4.3 節, 第 8.3 節, 第 9.2 節 タスク **T3.2**)
- 依存関係:
  - 先行 Issue: [Issue #753 (T1.1: 言語定義統廃合)](closed/753-consolidate-define-language-files-and-establish-extends-chain.md), [Issue #759 (T3.1: fuse-rules と O(1) ディスパッチ)](759-implement-fuse-rules-and-head-tag-o1-dispatch.md)
  - 後続 Issue: [Issue #762 (T4.1: 026〜029 の Picopass 化)](762-migrate-desugar-passes-026-to-029-to-picopass.md), [Issue #763 (T4.2: 030_desugar.scm の fuse-rules 置換)](763-replace-desugar-030-duplicate-rules-with-fuse-rules.md), [Issue #764 (T4.3: Verifier の attopass 化)](764-migrate-verifier-to-attopass-and-eliminate-triple-traversal.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files

- [ ] [ulisp/compiler/nanopass.scm](../../ulisp/compiler/nanopass.scm)
- [ ] [ulisp/compiler/nanopass_meta.scm](../../ulisp/compiler/nanopass_meta.scm)
- [ ] [ulisp/tests/test_nanopass_framework.scm](../../ulisp/tests/test_nanopass_framework.scm)

---

## 4. 実装方針 / Implementation Plan

Target Branch: `feat/760-local-redispatch-and-schema-coverage-check`

1. **5ステップ標準融合サイクルと Local Re-dispatch の実装**:
   - `(fuse-rules ...)` に渡されたルール記述子リストを `kind`（`'atto`, `'femto`, `'pico`）に応じて自動仕分けする。
   - `pico` ルールが発火して新しい式 `ir'` を返した場合（かつ `(not (equal? ir' ir))` の場合）、再帰走査を継続するために同じ非終端記号トランスフォーマ `NT` を `ir'` に対して再呼び出し（Re-dispatch）し、マッチしなくなった時点で `nanopass-catamorphism-step` によって子ノードへ降下する。
2. **スキーマ除去構文カバレッジ検証関数 `nanopass-verify-fusion-coverage` の実装**:
   - `L_in` と `L_out` がともに登録済み言語である場合、`language-diff` から除去された生成規則の先頭キーワードを抽出し、融合された `pico` ルール群の対象タグに含まれていないものがあれば警告またはエラーを出力する。

---

## 5. 完了条件 / Success Criteria (DoD)

- [ ] `case` $\to$ `or` $\to$ `if` のように複数段階にまたがる2つの独立した `define-picopass`（内部で `Expr` を明示呼び出ししない純粋テンプレート置換）を `fuse-rules` で融合した際、1回のパス実行で最終形の `if` まで完全に展開されること。
- [ ] `atto`, `femto`, `pico` を混在させて `fuse-rules` に渡した際、5ステップの順序に従って単一走査内で正しく実行されること。
- [ ] `L_out` で `-` 指定された構文に対する Picopass の欠落を検出するテストが `test_nanopass_framework.scm` で PASS すること。

