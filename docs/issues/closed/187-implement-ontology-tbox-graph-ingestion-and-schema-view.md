---
ID: 187
種別: Feature
優先度: High
ステータス: Open (In Progress)
---

# [FEAT/ENH] オントロジー・メタモデル（TBox）のグラフDBインジェストおよびスキーマ・エクスプローラー（Schema View）の実装 (ID: 187)

## 1. 概要 / Summary
`outputs/ontology/security_ontology_v2.ttl` で定義された全領域セキュリティ知識オントロジーの構造（クラス体系、オブジェクトプロパティ、因果連鎖、具現化関係）をプロパティグラフDB（`PropertyGraphEngine`）にインジェストし、Web API（`/api/graph/schema`）およびダッシュボード（`site/dashboard.html`）の「📐 Schema View」としてインタラクティブに可視化・探索できる基盤を実装する。

---

## 2. トレーサビリティ / Traceability
- 関連要求: [REQ-ONT-01](../../docs/requirements/REQ-ONT-01-security-paper-ontology.md)
- 設計仕様: [DSN-22](../../docs/designs/DSN-22-security_and_threat_ontology_w3c_specification.md)
- 関連Issue: [Issue 184](closed/184-enhance-owl-logic-incident-coupling-and-standards-alignment.md), [Issue 185](closed/185-implement-threat-model-causality-impact-and-precondition-neutralization.md), [Issue 186](closed/186-implement-claim-evidence-reification-and-regex-data-constraints.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [src/graph/ontology_loader.py](../../src/graph/ontology_loader.py) (TBox オントロジーローダー)
- [ ] [src/web/gateway/handlers.py](../../src/web/gateway/handlers.py) (/api/graph/schema エンドポイント)
- [ ] [src/web/gateway/app.py](../../src/web/gateway/app.py) (ルートディスパッチ)
- [ ] [site/dashboard.html](../../site/dashboard.html) (Schema View トグル & Canvas 描画)
- [ ] [tests/graph/test_ontology_tbox_ingestion.py](../../tests/graph/test_ontology_tbox_ingestion.py) (テスト)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/187-implement-ontology-tbox-graph-ingestion-and-schema-view`

1. **オントロジーTBoxローダーの実装 (`src/graph/ontology_loader.py`)**:
   - `build_full_spectrum_security_ontology()` または `.ttl` からクラス・プロパティを解析
   - 各クラス（`sec:Paper`, `sec:AttackTechnique`, `sec:DefenseMechanism`, `sec:Impact`, `sec:Precondition`, `sec:Claim`, `sec:EvaluationResult`, `sec:Incident` 等）を Vertex として生成
   - 各オブジェクトプロパティ（`sec:mitigates`, `sec:hasImpact`, `sec:neutralizesPrecondition`, `sec:assertsClaim` 等）を Edge として生成
   - 逆関係（`owl:inverseOf`）やラベル、コメント、ドメイン/レンジをプロパティに付与
2. **Web Gateway API エンドポイント追加**:
   - `/api/graph/schema`: TBox メタモデルグラフの nodes / edges JSON を返却
3. **Dashboard Canvas UI 連携**:
   - モード切替: 「🌐 Data View (実論文データ)」 $\leftrightarrow$ 「📐 Schema View (オントロジー設計図)」
   - Schema View 表示時はオントロジーの各クラスノードと関係性エッジを色分け表示し、クリックでクラス詳細・ドメイン・レンジを表示
4. **テスト作成 & 検証**:
   - TBox インジェストの完全性（全クラス・全プロパティが格納されること）の検証
   - API レスポンス検証

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] `outputs/ontology/security_ontology_v2.ttl` の全クラス・プロパティがグラフDBのノード/エッジとして欠落なくインジェストできること。
- [ ] `/api/graph/schema` エンドポイントが正当な JSON レスポンス（nodes, edges）を返すこと。
- [ ] `site/dashboard.html` 上で Schema View に切り替えてオントロジー構造を視覚的に探索できること。
- [ ] 単体・統合テストが全件 PASS すること。
