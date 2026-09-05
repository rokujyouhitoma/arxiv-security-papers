---
ID: 165
種別: Feature / Ops
優先度: Medium
ステータス: Closed
---

# [FEAT/OPS] 全量 OKF 論文アーカイブへの推論ルール（EIROM）適用と確信度・エビデンス付きグラフ再構築バッチの実装 (ID: 165)

## 1. 概要 / Summary
Issue 163（Edge Inference Rule Ontology Master: EIROM）および Issue 162（Edge 推論機構・確信度・エビデンス属性刻印）の完了に伴い、過去に収集・変換された既存の OKF 論文群（`outputs/okf_papers/`）および永続化グラフデータベース（`outputs/database/graph/graph.db` / `outputs/cti_graph.json`）に対し、最新の推論ルール公理と説明責任属性（確信度スコア、ティア、判定ルール ID、引用エビデンス）を全量再アノテーション・バックフィルするバッチパイプライン（`src/pipeline/cti_backfill.py`）を拡充・実装した。

本バッチの機能要件：
1. **最新推論エンジン（`TechniqueInferenceEngine`）および EIROM ルールオントロジーの統合**:
   - レガシーな単純文字列一致から、EIROM（`EdgeInferenceRuleRegistry`）に基づく多層判定（直接正規表現、タイトル名親和性、アブストラクト意味語彙スコアリング）へ全面刷新。
   - 論文タイトルおよび本文から脅威テクニック（`AttackTechnique`）、戦術（Tactic）、研究フォーカス（Offensive / Defensive / Analysis）を抽出。
2. **OKF YAML フロントマターの高度化と説明責任刻印**:
   - `inferred_techniques`（および後方互換用 `cti_techniques`）として、各テクニックの `technique_id`, `name`, `confidence`, `confidence_tier` (HIGH/MEDIUM/LOW), `primary_rule_id`, `applied_rules`, `inference_mechanism`, `evidence_quote`, `research_focus` を構造化保存。
   - 抽出テクニックに対応する MITRE ATT&CK 緩和策（`mitigations`）の自動マップ・付与。
3. **コンテンツハッシュ（SHA-256）に基づく高速差分・冪等実行**:
   - 論文のタイトル・本文から `source_text_hash` を算出してフロントマターに記録。
   - 既存ハッシュと現在ハッシュが一致する場合は再推論およびファイル I/O を安全にスキップ（`--force` フラグ指定時は強制再処理）。
4. **PropertyGraphEngine へのエッジ属性同期（Graph Bridge 連携）**:
   - OKF 論文と脅威テクニック間の有向エッジ（`TARGETS`, `PROPOSES_DEFENSE`, `DISCUSSES`）に、確信度・判定ルール・エビデンスプロパティを完全刻印してグラフ DB に自動同期（`--sync-graph`）。
5. **堅牢な実行制御と監査サマリーレポート**:
   - `--dry-run`, `--force`, `--max-papers`, `--sync-graph`, `--db-path`, `--report-file` などの CLI 引数を完備。
   - 処理件数、更新件数、スキップ件数、確信度ティア別内訳（HIGH / MEDIUM / LOW）、上位検出テクニックを含む構造化 JSON 監査ログを出力。

---

## 2. トレーサビリティ / Traceability
- 設計ドキュメント:
  - `docs/designs/DSN-17-security_knowledge_ontology.md` (Rev 2.0 Section 6 & 11: 動的エッジ説明責任とEIROM仕様)
  - `docs/designs/DSN-18-property_graph_database_engine.md` (Property Graph 永続化とエッジ属性)
- 関連 Issue:
  - `docs/issues/closed/162-enhance-graph-edge-inference-mechanism-and-confidence-attributes.md` (Edge 推論機構・属性刻印)
  - `docs/issues/closed/163-implement-edge-inference-rule-ontology-master.md` (EIROM 推論ルールマスター)
  - `docs/issues/closed/164-integrate-edge-confidence-rule-and-evidence-in-graph-tab.md` (Graph UI 確信度・ルールフィルタ)
  - `docs/issues/closed/153-implement-supervisor-4xdaily-cron-and-cti-backfill-reannotation.md` (初期 CTI Backfill)
- 関連ソースコード:
  - `src/pipeline/cti_backfill.py`
  - `src/domain/security/cti/inference.py` (`TechniqueInferenceEngine`, `InferredTechnique`)
  - `src/domain/security/cti/graph_bridge.py` (`batch_sync_papers_to_graph`, `sync_cti_inferences_to_graph`)
  - `src/domain/security/cti/registry.py` (`MITRECTIRegistry`)
  - `src/ontology/rule_registry.py` (`EdgeInferenceRuleRegistry`)
  - `src/graph/engine.py` (`PropertyGraphEngine`)
  - `tests/pipeline/test_cti_backfill.py`

---

## 3. 脅威モデリングとセキュリティ要件 (Threat Model & Security Requirements)
1. **パストラバーサル・不正ファイル書き込み防止**:
   - `find_all_okf_files()` で検出された全パスに対し `security.validation.path.is_safe_workspace_path` を適用し、ワークスペース外のファイルへの意図しない書き込み・情報漏洩を防御。
2. **アトミック書き込みによるファイル破損防止 (Atomic File Write)**:
   - 14,000 件以上の大規模アーカイブに対する更新処理において、バッチ中断（SIGINT、OOM、プロセス停止）時にファイルが不完全な状態で破損するのを防ぐため、一時ファイル（`.tmp`）に書き込んでから `os.replace` によるアトミック置換を実施。
3. **YAML インジェクション・構文破壊防止**:
   - タイトルやエビデンス引用（`evidence_quote`）に含まれる特殊文字（ダブルクォート、改行、コロン等）を適切にエスケープ・サニタイズして YAML 直列化を行い、パーサーエラーや YAML インジェクションを防止。
4. **ReDoS (Regular Expression Denial of Service) 防護**:
   - 正規表現および語彙走査は EIROM に事前コンパイルされた安全なパターンのみを使用し、論文本文の走査長・最大エビデンス長（120 文字）を制限して CPU 資源枯渇を防止。

---

## 4. 影響範囲と関連ファイル / Scope and Affected Files
- [x] `src/pipeline/cti_backfill.py`:
  - `TechniqueInferenceEngine` および `EdgeInferenceRuleRegistry` を使用するバックフィル処理へ改修。
  - フロントマターへの `inferred_techniques`、`mitigations`、`source_text_hash` の書き込み・更新。
  - `source_text_hash` によるスキップ・差分判定。
  - アトミック書き込み処理の実装。
  - `PropertyGraphEngine` へのバッチ同期機能の統合。
  - CLI 引数（`--dry-run`, `--force`, `--max-papers`, `--sync-graph`, `--db-path`, `--report-file`）のサポート。
- [x] `tests/pipeline/test_cti_backfill.py`:
  - 最新 EIROM 推論結果を用いた OKF フロントマター生成・更新テスト。
  - `source_text_hash` に基づく冪等性・スキップテスト。
  - `--force` オプション時の再処理テスト。
  - グラフデータベース同期連携テスト（Vertex / Edge プロパティ検証）。
  - CLI 実行およびアトミック書き込みのテスト。

---

## 5. 実装方針 / Implementation Plan
Target Branch: `feat/165-backfill-okf-papers-eirom-confidence`

### 5.1 `CTIBackfillEnricher` の初期化と推論エンジンの組み込み
- `__init__` で `TechniqueInferenceEngine` をインスタンス化（`EdgeInferenceRuleRegistry` を保持）。
- `MITRECTIRegistry` を併用して MITRE 緩和策（Mitigations）を解決。
- `PropertyGraphEngine` のインスタンス化ヘルパー（明示的 `db_path` またはデフォルト `outputs/database/graph/graph.db`）。

### 5.2 差分判定とハッシュ計算 (`source_text_hash`)
- 論文タイトルおよび本文から `_compute_text_hash(title, text)` を算出（SHA-256 の先頭 16〜32 文字）。
- 既存フロントマターから `source_text_hash` を抽出し、現在ハッシュと一致しかつ `force=False` の場合は `{ "updated": False, "reason": "Unchanged (hash match)" }` を返却。

### 5.3 フロントマターの YAML 直列化とアトミック更新
- 抽出された `InferredTechnique` のリストから YAML 直列化用の行を生成：
  ```yaml
  inferred_techniques:
    - { technique_id: "T1190", name: "Exploit Public-Facing Application", confidence: 0.95, confidence_tier: "HIGH", primary_rule_id: "RULE-EDGE-PAPER-TECH-REGEX-01", inference_mechanism: "regex_id_match", research_focus: "offensive", evidence_quote: "T1190 was tested" }
  ```
- 既存の `cti_techniques:` / `inferred_techniques:` / `mitigations:` / `source_text_hash:` ブロックを安全に除去し、新しいブロックを注入。
- 書き込み時は対象ファイルの隣に `.tmp` を作成し、成功時に `os.replace()` を呼び出すアトミック書き込みを採用。

### 5.4 グラフ同期連携 (`batch_sync_papers_to_graph`)
- `sync_graph=True` の場合、バッチ単位で `batch_sync_papers_to_graph` を呼び出し、各論文の Vertex と AttackTechnique への Edge（確信度・ルール属性付き）を登録。
- バッチ終了時（または一定チャンク毎）に `graph_engine.save()` を実行。

### 5.5 実行統計レポートの生成
- 以下の集計結果を含む辞書を生成し、標準出力および `--report-file` へ JSON 出力：
  ```json
  {
    "total_scanned": 100,
    "updated_count": 85,
    "skipped_count": 15,
    "error_count": 0,
    "tier_breakdown": {
      "HIGH": 45,
      "MEDIUM": 30,
      "LOW": 10
    },
    "total_edges_synced": 85,
    "top_techniques": [
      {"technique_id": "T1190", "count": 25},
      {"technique_id": "T1059", "count": 18}
    ]
  }
  ```

---

## 6. 完了条件 / Success Criteria (DoD)
- [x] `CTIBackfillEnricher` が `TechniqueInferenceEngine` を介して OKF 論文から確信度・ルール・エビデンス付き推論を実行できること
- [x] OKF フロントマターに `inferred_techniques`（または確信度付き `cti_techniques`）、`mitigations`、`source_text_hash` が安全に刻印されること
- [x] `source_text_hash` が一致する場合に不要な書き込みがスキップされ、`--force` 指定時には再推論・再書き込みが行われること（完全な冪等性）
- [x] グラフ同期オプション（`--sync-graph`）実行時、`PropertyGraphEngine` 内のエッジに `confidence_tier`, `primary_rule_id`, `applied_rules`, `evidences`, `evidence_quote` が正しく永続化されること
- [x] ファイル書き込みがアトミック書き込みで行われ、パーサーエラーや破損が発生しないこと
- [x] `--dry-run`, `--max-papers`, `--force`, `--report-file` 等の CLI オプションが正常動作すること
- [x] `tests/pipeline/test_cti_backfill.py` の単体テスト・結合テストが 100% PASS すること
- [x] Xenon 循環的複雑度 Rank A ($\le 5$)、Mypy `--strict` 適合
- [x] `make check_format` および `make static_analysis` が 100% PASS すること
