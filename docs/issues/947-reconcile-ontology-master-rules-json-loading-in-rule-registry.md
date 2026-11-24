---
ID: 947
種別: Feature
優先度: Low
ステータス: Open (New)
---

# [FEAT/ENH] オントロジー推論ルール `master_rules.json` の未使用状態の解消と `EdgeInferenceRuleRegistry` 読み込み整合化 (ID: 947)

## 1. 概要 / Summary

[rule_registry.py](../../src/ontology/rule_registry.py) には `DEFAULT_RULES_PATH = Path(__file__).parent / "rules" / "master_rules.json"` が定義されているものの、`_initialize_rules()` は `custom_path` 未指定時に `load_builtin_rules()` のみを呼び出すため、リポジトリに配置されている [master_rules.json](../../src/ontology/rules/master_rules.json) がデフォルト経路で読み込まれていない状態になっている。

`master_rules.json` とコード内のハードコード済みビルトインルールの差分を精査し、外部 JSON ルールを単一情報源としてデフォルト読み込みする（または不要なら明確に統廃合する）ことでルール定義の二重化と乖離を解消する。

---

## 2. トレーサビリティ / Traceability

- 関連資料:
  - [rule_registry.py](../../src/ontology/rule_registry.py)
  - [master_rules.json](../../src/ontology/rules/master_rules.json)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files

- [ ] [rule_registry.py](../../src/ontology/rule_registry.py) (`_initialize_rules`, `load_from_json`, `load_builtin_rules`)
- [ ] [master_rules.json](../../src/ontology/rules/master_rules.json)
- [ ] [inference.py](../../src/domain/security/cti/inference.py)
- [ ] [cti_backfill.py](../../src/pipeline/cti_backfill.py)

---

## 4. 実装方針 / Implementation Plan

Target Branch: `feat/947-reconcile-ontology-master-rules-json`

1. `master_rules.json` と `load_builtin_rules()` のルール定義差分を比較し、単一情報源（SSOT）とすべき正本を決定する。
2. `EdgeInferenceRuleRegistry._initialize_rules()` の初期化経路を整理し、`DEFAULT_RULES_PATH` からのロードまたは重複定義の整理を行う（詳細は `polish-issue` にて精緻化する）。

---

## 5. 完了条件 / Success Criteria (DoD)

- [ ] `master_rules.json` と `EdgeInferenceRuleRegistry` の責務・読み込み経路が一本化され、未使用・二重管理状態が解消されていること。
- [ ] CTI 推論・オントロジー関連テストおよび `make py_compile && make static_analysis` が PASS すること（詳細ゲートは `polish-issue` 時に確定）。
