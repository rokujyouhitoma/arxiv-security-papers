---
ID: 947
種別: Feature
優先度: Medium
ステータス: Closed
---

# [FEAT/ENH] オントロジー推論ルール `master_rules.json` の未使用状態の解消と `EdgeInferenceRuleRegistry` 読み込み整合化 (ID: 947)

## 1. 概要 / Summary

コードベース精査の結果、当初想定していた「[rule_registry.py](../../../src/ontology/rule_registry.py) で [master_rules.json](../../../src/ontology/rules/master_rules.json) が一切読まれていない」という状態とは異なり、実際には `EdgeInferenceRuleRegistry._initialize_rules(None)` が `load_from_json(None)` 経由で `DEFAULT_RULES_PATH`（[master_rules.json](../../../src/ontology/rules/master_rules.json)、16 ルール）を読み込む構造になっていることが判明した。一方で、以下の **4 つの具体的な不整合・形骸化** が確認されたため、これらを統合的に是正し [master_rules.json](../../../src/ontology/rules/master_rules.json) を名実ともに単一情報源（SSOT）として機能させた。

1. **SSOT 乖離（16 件 vs 12 件 ＋ 共通 12 件全件の定義差分）**:
   - [master_rules.json](../../../src/ontology/rules/master_rules.json) は Issue #179 で拡張された 16 ルールを保持している一方、[rule_registry.py](../../../src/ontology/rule_registry.py) 内の `BUILTIN_FALLBACK_RULES` は Issue #163 時点の 12 ルールのまま取り残されていた。
   - 欠落していた 4 ルールは `RULE-EDGE-PAPER-PRECONDITION-01`, `RULE-EDGE-DEFENSE-DETECTION-BLOCKS-01`, `RULE-EDGE-PAPER-GAP-IDENTIFIES-01`, `RULE-EDGE-PAPER-VENUE-PRESENTED-01` である。
   - さらに共通する 12 ルールすべてに差分が存在した。特に `RULE-EDGE-PAPER-TECH-STACK-01` では [master_rules.json](../../../src/ontology/rules/master_rules.json) に定義されている `condition_spec.categories`（`["os", "cloud", "firmware", "protocol"]`）が `BUILTIN_FALLBACK_RULES` で欠落しており、全 12 ルールで `description` および `evidence_spec.case_sensitive` が不一致であったため、`compute_ruleset_hash()` の SHA-256 フィンガープリントが完全に乖離していた。
2. **サイレントフォールバックと改ざん・設定ミスの隠蔽**:
   - `_initialize_rules()` が `custom_path` 明示指定時や既存 JSON 破損・スキーマ違反時も含め `(OSError, ValueError)` を無条件に握り潰し、警告ログも来歴情報（`loaded_source`, `is_fallback`, `ruleset_version`）も残さず古い `BUILTIN_FALLBACK_RULES` へ静かにフォールバックしていた。
   - また `load_from_json()` にはルート JSON の型検証（`dict` 以外で `AttributeError` になる懸念）、空配列 `[]` の拒絶、重複 `rule_id` 検証、ファイル種別・サイズ上限検証が欠如していた。
3. **`TechniqueInferenceEngine` での `self.rule_registry` 未参照（死んだ注入）**:
   - [inference.py](../../../src/domain/security/cti/inference.py) の `TechniqueInferenceEngine.__init__` は `self.rule_registry = rule_registry or EdgeInferenceRuleRegistry()` を保持しているにもかかわらず、`infer()`、`_find_direct_technique_ids()`、`_score_name()`、`_score_single_keyword()`、`_apply_direct_match()`、`_create_inferred_technique()` のいずれも `self.rule_registry` を一切参照せず、正規表現（`TECHNIQUE_ID_REGEX`）、ルール ID、ルール名、スコア重み、スニペット長をすべてハードコードしていた。
   - このため、[master_rules.json](../../../src/ontology/rules/master_rules.json) や注入されたカスタム `EdgeInferenceRuleRegistry` の変更・ルール無効化（`is_active=False`）が推論結果へ一切反映されていなかった。
4. **`CTIBackfillEnricher` におけるルール来歴監査の欠落**:
   - [cti_backfill.py](../../../src/pipeline/cti_backfill.py) は `EdgeInferenceRuleRegistry` を生成して注入しているものの、実行統計（`stats`）やログに `ruleset_hash` / `ruleset_source` を記録しておらず、`rules_path` を指定する口もなかった。

---

## 2. トレーサビリティ / Traceability

- 関連資料・設計・実装:
  - [DSN-17-security_knowledge_ontology.md](../../designs/DSN-17-security_knowledge_ontology.md)（Section 7–8: EIROM マスターデータ仕様・品質ゲート）
  - [163-implement-edge-inference-rule-ontology-master.md](163-implement-edge-inference-rule-ontology-master.md)（EIROM 初回実装・フォールバックおよび SHA-256 完全性要件）
  - [165-backfill-and-enrich-okf-papers-with-eirom-and-edge-confidence.md](165-backfill-and-enrich-okf-papers-with-eirom-and-edge-confidence.md)（CTI バックフィル統合）
  - [rule_registry.py](../../../src/ontology/rule_registry.py)
  - [rule_schema.py](../../../src/ontology/rule_schema.py)
  - [master_rules.json](../../../src/ontology/rules/master_rules.json)
  - [inference.py](../../../src/domain/security/cti/inference.py)
  - [cti_backfill.py](../../../src/pipeline/cti_backfill.py)
  - [test_rule_ontology_master.py](../../../tests/ontology/test_rule_ontology_master.py)

---

## 3. 脅威モデリングとセキュリティ要件 / Threat Model & Security Requirements

外部 JSON ルールファイルを読み込み正規表現および推論重みとして実行する構造上、以下の脅威（CWE）に対する防御を組み込んだ。

1. **任意ファイル参照・リソース枯渇の防止（CWE-22 / CWE-400）**:
   - `load_from_json()` において `Path(path).resolve()` によりパスを正規化し、通常ファイル（`is_file()`）であること、拡張子が `.json` であること、およびファイルサイズが上限（`MAX_RULES_FILE_BYTES = 5 * 1024 * 1024`）以下であることを検証し、ディレクトリ指定や過大ファイル読み込みを拒絶する。
2. **データ完全性検証と改ざん隠蔽の防止 / Fail-Closed 原則（CWE-345）**:
   - `custom_path` が明示指定された場合、ファイル不在・読込失敗・JSON 不正・スキーマ違反のいずれであってもフォールバックせず即座に例外を送出する（Fail-Closed）。
   - `DEFAULT_RULES_PATH` が存在する状態で JSON 構文エラー・スキーマ違反・ReDoS 検知・重複 `rule_id`・空配列を検出した場合も、改ざんまたは破損を隠蔽しないようフォールバックせず例外を送出する（Fail-Closed）。
   - `load_builtin_rules()` への自動フォールバックは `custom_path is None` かつ `strict=False` かつ `DEFAULT_RULES_PATH` 不在（`FileNotFoundError`）時に限定し、必ず `logger.warning(...)` で警告を出力するとともに `is_fallback = True` を記録する。
3. **正規表現サービス不能攻撃の防止 / ReDoS 防護（CWE-1333）**:
   - [rule_schema.py](../../../src/ontology/rule_schema.py) の `_validate_regex_safety()` で検証済みの正規表現パターンのみを `TechniqueInferenceEngine` 側でコンパイルし、危険なパターンはロード時に即拒絶する。
4. **入力構造バリデーション（CWE-20）**:
   - ルート JSON が `dict` 型であること、`"rules"` が非空 `list` で全要素が `dict` であること、`rule_id` の重複がないことを検証する。さらにロード中に 1 件でも検証失敗した場合は部分ロード状態を残さない（原子的ロード）。

---

## 4. 影響範囲と関連ファイル / Scope and Affected Files

- [x] [rule_registry.py](../../../src/ontology/rule_registry.py): `BUILTIN_FALLBACK_RULES` の 16 ルール完全同期、`strict: bool = False` 引数・来歴プロパティ（`loaded_source`, `is_fallback`, `ruleset_version`）導入、`_initialize_rules` の Fail-Closed 化、`load_from_json` のパス/サイズ/構造/重複 ID/非空/原子的ロード実装
- [x] [master_rules.json](../../../src/ontology/rules/master_rules.json): 正本（SSOT）としてのスキーマ・16 ルール整合確認
- [x] [inference.py](../../../src/domain/security/cti/inference.py): `TechniqueInferenceEngine` の `self.rule_registry` 実駆動化（5 主要推論ルールの有効状態・正規表現・重み・閾値・スニペット長・ルール名をレジストリから動的解決しコンパイル済み正規表現をキャッシュ）
- [x] [cti_backfill.py](../../../src/pipeline/cti_backfill.py): `CTIBackfillEnricher.__init__` への任意引数 `rules_path: Optional[str] = None` 追加、`_init_backfill_stats` および開始ログへの `ruleset_hash` / `ruleset_source` / `ruleset_is_fallback` 出力
- [x] [test_rule_ontology_master.py](../../../tests/ontology/test_rule_ontology_master.py): SSOT 16 ルール＆ SHA-256 パリティテスト、Fail-Closed テスト（`custom_path` 不在・破損 JSON・ReDoS・重複 ID・空配列・`strict=True`）、フォールバック警告ログ＆来歴テスト、カスタムレジストリ注入（`is_active=False`・重み/パターン変更）の推論反映テスト、`test_builtin_fallback` の 16 件期待値更新
- [x] [test_cti_backfill.py](../../../tests/pipeline/test_cti_backfill.py): `stats` 内の `ruleset_hash`（64 桁 SHA-256）・`ruleset_source`・`ruleset_is_fallback` 検証テストおよび `rules_path` Fail-Closed テスト追加

---

## 5. 実装方針 / Implementation Plan

Target Branch: `feat/947-reconcile-ontology-master-rules-json`

### Phase 1: `master_rules.json` 正本（SSOT）確定と `BUILTIN_FALLBACK_RULES` 完全同期 (`src/ontology/rule_registry.py`)
1. [master_rules.json](../../../src/ontology/rules/master_rules.json) に定義された 16 ルールを EIROM の正本（SSOT）として確定する。
2. `BUILTIN_FALLBACK_RULES`（および `BUILTIN_RULESET_VERSION = "2026.09.1"`）に欠落 4 ルール（`RULE-EDGE-PAPER-PRECONDITION-01`, `RULE-EDGE-DEFENSE-DETECTION-BLOCKS-01`, `RULE-EDGE-PAPER-GAP-IDENTIFIES-01`, `RULE-EDGE-PAPER-VENUE-PRESENTED-01`）を追加し、既存 12 ルールの `description`、`condition_spec`（特に `RULE-EDGE-PAPER-TECH-STACK-01` の `categories`）、`evidence_spec`（`case_sensitive: False` 含む）をすべて [master_rules.json](../../../src/ontology/rules/master_rules.json) と完全一致させる。
3. `load_from_json(DEFAULT_RULES_PATH)` と `load_builtin_rules()` が同一の 16 ルールおよび同一 SHA-256 `compute_ruleset_hash()` を返す状態を保証する。

### Phase 2: `EdgeInferenceRuleRegistry` のロード規約厳格化と来歴メタデータ導入 (`src/ontology/rule_registry.py`)
1. `__init__(self, auto_load: bool = True, custom_path: Optional[str] = None, strict: bool = False)` へ後方互換な `strict` 引数を追加し、内部状態・読み取り専用プロパティとして `loaded_source`（`"json:<resolved_path>"` / `"builtin_fallback"` / `"uninitialized"`）、`is_fallback`（`bool`）、`ruleset_version`（`str`）を追加する。
2. Xenon Rank A（循環的複雑度 ≤ 5）を維持するため、検証・登録処理を単一責務ヘルパーへ分割する:
   - `_resolve_rules_path(path: Optional[str]) -> Path`: パス解決、存在・通常ファイル検証、`.json` 拡張子確認、サイズ上限（`5 MiB`）確認。
   - `_extract_rules_payload(raw_data: object) -> Tuple[str, List[Dict[str, Any]]]`: ルート `dict` 検証、非空 `"rules"` リスト検証、全要素 `dict` 検証、`version` 抽出。
   - `_build_validated_rules(rule_list: List[Dict[str, Any]]) -> List[EdgeInferenceRule]`: 各エントリの `EdgeInferenceRule.from_dict()` 変換と重複 `rule_id` 検出（重複時は `ValueError` 送出）。
3. `load_from_json()` は `_build_validated_rules()` が全件成功した後にのみ `self._replace_rules()` を実行する原子的ロードとし、途中失敗時に既存レジストリ状態を破壊しないようにする。
4. `_initialize_rules(self, custom_path: Optional[str], strict: bool) -> None` は `custom_path is not None or strict` で Fail-Closed、`custom_path is None and not strict` の `FileNotFoundError` 時のみ `logger.warning(...)` を出力し `load_builtin_rules()` へフォールバックする。

### Phase 3: `TechniqueInferenceEngine` の `EdgeInferenceRuleRegistry` 実駆動化 (`src/domain/security/cti/inference.py`)
1. `self.rule_registry` から 5 主要推論ルール（`RULE-EDGE-PAPER-TECH-REGEX-01`, `RULE-EDGE-PAPER-TECH-TITLE-02`, `RULE-EDGE-PAPER-TECH-KEYWORD-03`, `RULE-EDGE-PAPER-TECH-ABSTRACT-04`, `RULE-EDGE-FOCUS-OFFENSIVE-01`）を動的解決し、有効状態・パターン・重み・閾値・スニペット長・ルール名を推論結果へ反映させる。
2. `_score_name`, `_score_single_keyword`, `_score_keywords`, `_score_single_technique`, `_apply_direct_match`, `_create_inferred_technique`, `_classify_research_focus` をインスタンスメソッド化し、`self._get_active_rule(rule_id)` 経由でルール設定を参照するように統一する。
3. デフォルトの [master_rules.json](../../../src/ontology/rules/master_rules.json) ロード時における既存推論スコア・ルール ID・エビデンス形式・優先順位選択（`_select_primary_rule`）の互換性を完全に維持する。

### Phase 4: `CTIBackfillEnricher` の監査トレーサビリティ連携 (`src/pipeline/cti_backfill.py`)
1. `CTIBackfillEnricher.__init__` に任意引数 `rules_path: Optional[str] = None` を追加し、`EdgeInferenceRuleRegistry(custom_path=rules_path)` を初期化する。
2. `_init_backfill_stats()` および開始ログに `ruleset_hash`、`ruleset_source`、`ruleset_is_fallback` を追加記録する。

### Phase 5: テスト拡充・実装上の注意点・品質ゲート検証
1. Xenon Rank A（循環的複雑度 ≤ 5）、`mypy --strict src` 0 エラー、外部依存ゼロ（Python 標準ライブラリのみ）、関連ドキュメントの絶対パス排除を遵守する。
2. [test_rule_ontology_master.py](../../../tests/ontology/test_rule_ontology_master.py) および [test_cti_backfill.py](../../../tests/pipeline/test_cti_backfill.py) にて全要件を検証する。

---

## 6. 完了条件 / Success Criteria (DoD)

- [x] [master_rules.json](../../../src/ontology/rules/master_rules.json)（16 ルール）が正本（SSOT）として確定し、`BUILTIN_FALLBACK_RULES` との 16 ルール全件および SHA-256 `compute_ruleset_hash()` の完全一致が自動テストで検証されていること。
- [x] `EdgeInferenceRuleRegistry` が `loaded_source` / `is_fallback` / `ruleset_version` を保持し、`custom_path` エラーや既存 JSON 破損・ReDoS・重複 `rule_id`・空配列時に Fail-Closed（例外送出）し、デフォルトファイル不在時のみ警告ログ付きでフォールバックすること。
- [x] `TechniqueInferenceEngine` が `self.rule_registry` の有効ルール・正規表現・重み・スニペット長を実際に参照して推論を行い、カスタムレジストリによるルール無効化や重み変更が推論出力へ反映されることが単体テストで証明されていること。
- [x] `CTIBackfillEnricher` が `ruleset_hash` / `ruleset_source` / `ruleset_is_fallback` を実行統計およびログへ出力すること。
- [x] `PYTHONPATH=src .venv/bin/pytest tests/ontology/ tests/domain/test_edge_confidence.py tests/domain/test_stix_navigator.py tests/pipeline/test_cti_backfill.py tests/web/test_dashboard_graph_tab.py` が 100% PASS すること。
- [x] `make check_format`（`isort`, `black`, `flake8`）および `make static_analysis`（`radon`, `xenon` Rank A, `mypy --strict`, `py_compile`）が 0 エラーで PASS すること。
- [x] 本 Issue および変更対象ドキュメント内に絶対パスリンクが存在せず、全相対リンクが有効であること。
