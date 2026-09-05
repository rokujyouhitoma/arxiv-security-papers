---
ID: 164
種別: Feature
優先度: High
ステータス: Closed
---

# [FEAT/ENH] /dashboard tab=graph におけるエッジ確信度（Confidence Tier）＆推論ルール絞り込みフィルタとエビデンス（スニペット）表示の実装 (ID: 164)

## 1. 概要 / Summary
Issue 162 および Issue 163 により、グラフデータベース（`PropertyGraphEngine`）内の Edge に「判定ルール（Rule ID/Name）」「推論機構（Inference Mechanism）」「確信度ティア（Confidence Tier: HIGH / MEDIUM / LOW）」「根拠エビデンス（引用スニペット・マッチ語彙）」が完全に刻印された。

本課題では、これらの説明責任メタデータを `/dashboard?tab=graph` の Web UI 可視化画面に統合し、アナリスト・運用者が画面上で直感的に探索・検証できるようにする：
1. **確信度ティア絞り込みコントロール**:
   - 「確信度 HIGH のみ（厳格・誤検知ゼロモード: $\ge 0.8$）」「MEDIUM 以上（推奨デフォルト: $\ge 0.5$）」「全件表示（低確信度・探索モード: All）」を即座に切り替えるツールバーボタンの追加。
2. **推論ルール（EIROM）別エッジフィルタ**:
   - 「正規表現直接一致（RULE-EDGE-PAPER-TECH-REGEX-01）」「タイトル親和性」「アブストラクト語彙」等、適用ルール種別（Primary Rule ID）に応じたエッジ表示・非表示フィルタリング。
3. **エッジ描画スタイルの確信度差別化**:
   - Canvas 2D 描画時、確信度ティアに応じた線種・透明度の差別化（HIGH: 太実線 1.8px、MEDIUM: 標準実線 1.2px、LOW: 細破線 0.9px [3, 3]）を行い、グラフの信頼性を一目で把握可能にする。
4. **ノード詳細コールアウトにおける接続エッジ確信度・エビデンス表示**:
   - ノード選択時（`selectNode`）の Relations 一覧において、接続先ノード名だけでなく、確信度バッジ（HIGH/MED/LOW）、判定ルール ID、および論文本文から抽出された「根拠引用スニペット（Evidence Snippet）」を表示。

---

## 2. トレーサビリティ / Traceability
- 関連資料:
  - `docs/designs/DSN-17-security_knowledge_ontology.md` (Rev 2.0 Section 6 & 11: 動的エッジ説明責任とEIROM仕様)
  - `docs/designs/DSN-18-property_graph_database_engine.md` (Property Graph 探索と可視化)
  - `docs/issues/closed/162-enhance-graph-edge-inference-mechanism-and-confidence-attributes.md` (Edge 推論機構・属性刻印)
  - `docs/issues/closed/163-implement-edge-inference-rule-ontology-master.md` (EIROM 推論ルールマスター)
  - `docs/issues/146-implement-edge-relation-type-filter-in-graph-tab.md` (エッジ関係性フィルタ)
  - `src/graph/engine.py` (`export_cti_subgraph`, `execute_graph_query`)
  - `src/web/gateway/handlers.py` (`handle_cti_graph_mesh`, `handle_graph_query`)
  - `site/dashboard.html` (グラフ描画、ツールバー、コールアウト UI)

---

## 3. 脅威モデリングとセキュリティ要件 (Threat Model & Security Requirements)
1. **DOM / Stored XSS の完全遮断**:
   - エッジプロパティに格納される論文本文由来の引用スニペット（`evidence_quote`）、ルール ID、推論機構文字列を HTML に挿入する際は、既存の `escapeHtml()` 関数を必ず介して DOM レンダリングを行い、悪意ある論文テキストによるスクリプト注入を 100% 遮断する。
2. **クライアントリソース消費・ReDoS 防護**:
   - スニペット表示は最大 120 文字に正規化されたものを扱い、極端に巨大なテキストによるレンダリングブロックやレイアウト破損を防止する。
3. **入力バリデーション**:
   - 確信度ティア引数は固定ホワイトリスト（`HIGH`, `MEDIUM`, `LOW`, `all`）で検証し、不正な型やパラメータを安全に破棄する。

---

## 4. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] `src/graph/engine.py`:
  - `export_cti_subgraph` および `execute_graph_query` において、`_format_cti_edge` ヘルパーを介して `confidence`, `confidence_tier`, `primary_rule_id`, `applied_rules`, `inference_mechanism`, `evidence_quote`, `evidences` を JSON 出力。
- [ ] `site/dashboard.html`:
  - ツールバー `mesh-toolbar` 内の `ctiFilters` に確信度ボタングループ（`All`, `Med+`, `High Only`）およびルール選択ドロップダウンを追加。
  - JavaScript フィルタ制御 `setEdgeConfidenceFilter(tier)`, `setEdgeRuleFilter(ruleId)` の実装。
  - `applyCtiFilter()` 内でエッジ確信度およびルールによるフィルタリングロジックを統合。
  - Canvas 描画ループ内のエッジ線種（実線/破線、太さ、色）を確信度ティアに応じて動的切り替え。
  - ノード詳細コールアウト (`selectNode`) 内の Relations リストに確信度バッジと引用スニペットを表示。
- [ ] `tests/web/test_dashboard_graph_tab.py`:
  - 確信度コントロール要素（`btnConfAll`, `btnConfMed`, `btnConfHigh`, `selectEdgeRule`）の存在検証。
  - 確信度フィルタおよびエビデンス表示用 JavaScript 関数の整合性検証。
- [ ] `tests/web/test_dashboard_cti_graph.py` / `tests/web/gateway/test_gateway.py`:
  - `/api/graph/cti-mesh` および `/api/graph/query` のレスポンスに拡張エッジ属性が含まれることの検証。

---

## 5. 実装方針 / Implementation Plan
Target Branch: `feat/164-dashboard-graph-edge-confidence-ui`

### 5.1 バックエンド: グラフエッジ直列化の共通化 (`src/graph/engine.py`)
- エッジ直列化用ヘルパー関数 `_format_cti_edge(e: Edge) -> Dict[str, Any]` を定義：
  ```python
  def _format_cti_edge(e: Edge) -> Dict[str, Any]:
      return {
          "source": e.src_id,
          "target": e.dst_id,
          "label": e.label,
          "weight": e.weight,
          "confidence": e.get_confidence(default=1.0),
          "confidence_tier": e.get_confidence_tier(),
          "primary_rule_id": e.get_primary_rule() or "",
          "applied_rules": list(e.properties.get("applied_rules", [])),
          "inference_mechanism": str(e.properties.get("inference_mechanism", "lexical")),
          "evidences": e.get_evidences(),
          "evidence_quote": str(e.properties.get("evidence_quote", "")),
          "tier": e.properties.get("tier", "gold"),
      }
  ```
- `export_cti_subgraph` および `execute_graph_query` の内包表記を `_format_cti_edge` に集約し、Xenon Rank A ($\le 5$) を維持。

### 5.2 フロントエンド UI: 確信度＆ルールツールバーの配置 (`site/dashboard.html`)
- `ctiFilters` 領域に以下の UI コントロールを配置：
  - **CONFIDENCE**: `All` (全件), `Med+` ($\ge 0.5$, 推奨), `High Only` ($\ge 0.8$, 厳格)
  - **RULE**: `All Rules`, `RULE-EDGE-PAPER-TECH-REGEX-01` (Direct Regex), `RULE-EDGE-PAPER-TECH-TITLE-02` (Title Name), `RULE-EDGE-PAPER-TECH-KEYWORD-03` (Title Keyphrase), `RULE-EDGE-PAPER-TECH-ABSTRACT-04` (Abstract Semantic)

### 5.3 フロントエンド ロジック: `applyCtiFilter` の多層フィルタ統合
- グローバルフィルタ状態変数：
  - `let edgeConfidenceFilter = 'all';` (`'all'`, `'MEDIUM'`, `'HIGH'`)
  - `let edgeRuleFilter = 'all';`
- `candidateEdges` のフィルタリング：
  - 確信度判定：`HIGH` の場合は `e.confidence_tier === 'HIGH'`、`MEDIUM` の場合は `e.confidence_tier === 'HIGH' || e.confidence_tier === 'MEDIUM'`。
  - ルール判定：指定ルール ID が `e.primary_rule_id` または `e.applied_rules` に合致するか。
- ノード次数（Degree）のリアルタイム再計算および孤立ノード判定への自然な連動。

### 5.4 描画スタイリングとエビデンス引用表示
- Canvas 描画：
  - `e.confidence_tier === 'HIGH'`: 太実線 (1.8px, 高透明度)
  - `e.confidence_tier === 'MEDIUM'`: 通常実線 (1.2px)
  - `e.confidence_tier === 'LOW'`: 破線 `[3, 3]` (0.9px, 控えめ表示)
- コールアウト Relations 表示：
  - 各エッジに対して `[HIGH 100%]` (緑), `[MEDIUM 80%]` (橙), `[LOW 40%]` (赤) のバッジを付与。
  - 根拠スニペット `“...matched text...”` をイタリック体でインライン表示。

---

## 6. 完了条件 / Success Criteria (DoD)
- [x] `/api/graph/cti-mesh` および `/api/graph/query` のエッジデータに `confidence`, `confidence_tier`, `primary_rule_id`, `evidence_quote` が含まれていること
- [x] `/dashboard?tab=graph` 画面上に確信度ボタングループ（`All`, `Med+`, `High Only`）およびルール選択 UI が表示されること
- [x] 確信度ボタン切替時にエッジが即座に絞り込まれ、ノード次数および探索結果バッジがリアルタイムに再計算されること
- [x] Canvas 描画上で HIGH / MEDIUM / LOW の線種・スタイルが差別化されていること
- [x] ノード選択時の Relations リストに確信度バッジとエビデンス引用スニペットが XSS 安全（`escapeHtml`）に表示されること
- [x] 単体テスト（`tests/web/test_dashboard_graph_tab.py`, `tests/web/test_dashboard_cti_graph.py`）を作成・更新し、100% PASS すること
- [x] `make check_format` および `make static_analysis` (radon, xenon Rank A, flake8, mypy --strict) が 100% PASS すること
