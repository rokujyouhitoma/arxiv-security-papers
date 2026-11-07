---
ID: 756
種別: Feature
優先度: High
ステータス: Open (New)
---

# [FEAT/ENH] 第一級ルール記述子 (Rule Descriptor) と define-picopass / define-femtopass / define-attopass DSL の実装 (DSN-33-01 T2.1) (ID: 756)

## 1. 概要 / Summary

[[DSN-33-01] ULisp 階層型パス融合 ＆ DAG 最適化基盤設計書](../designs/DSN-33-01-ulisp_pipeline_pass_nanopass_picopass_dag_architecture.md) の第 3.1 節、第 3.2 節、およびタスク **T2.1** に基づき、再帰走査を持たない微細粒度ルールを定義するための3つの直交 DSL プリミティブ（`define-picopass`, `define-femtopass`, `define-attopass`）およびその内部表現である **第一級ルール記述子（Rule Descriptor）** を実装する。

1. **`define-picopass`（局所構文書き換え規則）**: 単一ノード（または命令窓）に対するパターンマッチと置換テンプレートのみを記述する。マッチ時は変換後の S 式を返し、非マッチ時はフォールスルー（または単体呼び出し時は元の式）を返す。
2. **`define-femtopass`（非破壊属性計算・注釈規則）**: 構文木の構造を一切変更せず、自由変数集合・利用回数・推論型タグ・SourceSpan 等のメタデータを計算する。
3. **`define-attopass`（原子命題アサーション規則）**: 構文木を一切書き換えず、禁止構文の不在・未束縛変数の不在・アフィン線形性等の単一不変条件を検証し、違反時に構造化エラー（`picopass-fail`）を送出する。

---

## 2. トレーサビリティ / Traceability

- 関連設計書:
  - [[DSN-33-01] ULisp 階層型パス融合 ＆ DAG 最適化基盤設計書](../designs/DSN-33-01-ulisp_pipeline_pass_nanopass_picopass_dag_architecture.md) (第 3.1 節, 第 3.2 節, 第 6.3 節, 第 7.1 節, 第 9.2 節 タスク **T2.1**)
- 依存関係:
  - 先行 Issue: [Issue #755 (T1.3: 未変更部分木の構造共有と重複 Trace 整理)](755-implement-catamorphism-structural-sharing-and-unify-trace-hooks.md)
  - 後続 Issue: [Issue #757 (T2.2: 関数合成コンビネータ群の実装)](757-implement-picopass-strategy-combinators.md), [Issue #758 (T2.3: Pass 015 への新 DSL 統合)](758-integrate-picopass-dsl-into-pass-015-expander.md), [Issue #759 (T3.1: fuse-rules と O(1) ディスパッチ)](759-implement-fuse-rules-and-head-tag-o1-dispatch.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files

- [ ] [ulisp/compiler/nanopass_meta.scm](../../ulisp/compiler/nanopass_meta.scm)
- [ ] [ulisp/compiler/nanopass.scm](../../ulisp/compiler/nanopass.scm)
- [ ] [ulisp/tests/test_nanopass_framework.scm](../../ulisp/tests/test_nanopass_framework.scm)

---

## 4. 実装方針 / Implementation Plan

Target Branch: `feat/756-implement-picopass-femtopass-attopass-dsl`

1. **Rule Descriptor レコードとグローバルルールレジストリの実装（`nanopass_meta.scm`）**:
   - ルール記述子 `(make-rule-descriptor name kind nt-name head-tags reads writes eliminates clauses proc)` とアクセサ群（`rule-descriptor?`, `rule-name`, `rule-kind`, `rule-nt-name`, `rule-head-tags`, `rule-reads`, `rule-writes`, `rule-eliminates`, `rule-clauses`, `rule-proc`）を実装する。
   - パターンリストから先頭シンボル候補 `head-tags`（例：`((and ,e ...) ...)` なら `'(and)`、変数パターン `,x` を含む場合は `'*`）および `reads` / `writes` / `eliminates` タグ集合を自動抽出する静的解析関数を実装する。
   - グローバルレジストリ `*nanopass-rules*`（`nanopass-register-rule!`, `nanopass-lookup-rule`）を設け、ルール名シンボルまたはオブジェクトから記述子を引けるようにする。
2. **`define-picopass`, `define-femtopass`, `define-attopass` の展開関数実装（`nanopass.scm`）**:
   - `nanopass-expand-define-picopass`, `nanopass-expand-define-femtopass`, `nanopass-expand-define-attopass` を実装する。
   - 定義されたルール名 `rule-foo` が、単体テストや REPL で `(rule-foo '(and a b))` のように**直接関数として呼び出し可能**であり、かつ `*nanopass-rules*` にも記述子が登録されるように展開する。
   - `picopass-fail` エラー報告ヘルパーを実装する。

---

## 5. 完了条件 / Success Criteria (DoD)

- [ ] `define-picopass`, `define-femtopass`, `define-attopass` で定義した各ルールに対し、単一の S 式断片を渡して1行で単体テスト（`(rule-desugar-and '(and a b))` 等）が実行できること。
- [ ] 各ルールから `head-tags`, `reads`, `writes`, `eliminates`, `clauses` メタデータが正確に取得できること。
- [ ] `ulisp/tests/test_nanopass_framework.scm` に `pico` / `femto` / `atto` 3バリアントの単体テストを追加し、全件 PASS すること。

