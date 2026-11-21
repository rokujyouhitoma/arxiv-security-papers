---
ID: 897
種別: Feature
優先度: Medium
ステータス: Open (New)
---

# [FEAT/ENH] Implement CTI-QL DSL Reference Implementation and E2E Verification (ID: 897)

## 1. 概要 / Summary
[[DSN-33-04]](../designs/DSN-33-04-ulisp_language_workbench_interpreter_generator_and_guest_runtime_architecture.md) 第 7 章に基づき、セキュリティ脅威ログのフィルタリング DSL である `cti-ql` の文法・オブジェクトモデル・評価器定義をリファレンス実装し、言語ワークベンチによるパーサー合成、AOT コンパイル、および極限ネイティブ機械語（7命令）出力の E2E 実証テストを構築する。

---

## 2. トレーサビリティ / Traceability
- 関連設計書:
  - [[DSN-33-04] ULisp 言語ワークベンチ設計書 (第7章 リファレンス実装仕様: セキュリティ CTI フィルタ言語 cti-ql)](../designs/DSN-33-04-ulisp_language_workbench_interpreter_generator_and_guest_runtime_architecture.md)
  - [[DSN-33-03] ULisp ステージ多相メタコンパイラ ＆ 二村射影フラクタル実行基盤設計書](../designs/DSN-33-03-ulisp_stage_polymorphic_metacompiler_and_futamura_projection_architecture.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [ulisp/workbench/examples/cti_ql.scm](../../ulisp/workbench/examples/cti_ql.scm)
- [ ] [ulisp/tests/test_workbench_cti_ql_e2e.scm](../../ulisp/tests/test_workbench_cti_ql_e2e.scm)
- [ ] [ulisp/Makefile](../../ulisp/Makefile)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/897-implement-cti-ql-dsl-reference-implementation-and-e2e-verification`

1. `ulisp/workbench/examples/cti_ql.scm` に文法定義（`define-grammar`）、オブジェクトモデル（`define-guest-object <cti-event>`）、および単一評価器（`eval-cti-ql`）を実装。
2. `ulisp-cogen` を用いて、スタンドアロンコンパイラ `bin/cti-qlc` を自動生成。
3. 脅威判定ルール（`threat == "ransomware" AND cve-score >= 8`）を AOT コンパイルし、出力されたバイナリが期待通りの判定結果を返すか検証。
4. ディスアセンブル結果を検査し、余計な AST 走査や連想リスト探索が消滅し、ダイレクトなアセンブリ命令列のみが出力されていることを自動検証。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] `cti_ql.scm` から `cti-qlc` コンパイラがビルド可能であること。
- [ ] 生成バイナリが CTI イベントストリームを高速フィルタリングできること。
- [ ] `make -C ulisp test_workbench_cti_ql_e2e` が PASS すること。
- [ ] `make py_compile && make static_analysis` が PASS すること。
