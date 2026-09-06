---
ID: 190
種別: Bug
優先度: High
ステータス: Closed
---

# [BUG/SEC] Schema View における Edge の undefined [HIGH] 表示および Vertex の全黒色化不具合の改修 (ID: 190)

## 1. 概要 / Summary
Web ダッシュボード（`/dashboard`）の「📐 Schema View（W3C OWL TBox メタモデル）」において、以下の 2 点の視覚的・論理的不具合が発生していた：
1. Vertex 間をつなぐエッジのハイライト表示が `undefined [HIGH]` となり、オントロジー関係述語（例: `sec:hasImpact`, `sec:mitigates` 等）が表示されない。
2. 全ての Vertex が真っ黒（`#2b2b2b`）で描画され、「📐 W3C OWL TBox Schema」凡例で定義されているオントロジークラス別カラー（Indigo, Orange, Pink, Green, Violet 等）が反映されない。

### 再現手順 / Steps to Reproduce
1. `make run_web` または `make run_dashboard` を実行し、ブラウザで `http://localhost:8000/dashboard` を開く。
2. ヘッダー上部のモード切替で「📐 Schema View」をクリックする。
3. ノードまたはエッジにホバー・クリックすると、エッジラベルに `undefined [HIGH]` と表示される。
4. 全ノードの背景色が真っ黒（#2b2b2b）で描画されている。

### 再現環境 / Environment
- OS / Env: Linux / Any modern browser
- File: [site/dashboard.html](../../site/dashboard.html), [docs/manuals/USR-01-user_manual.md](../../docs/manuals/USR-01-user_manual.md)

---

## 2. トレーサビリティ / Traceability
- 関連要求: [REQ-ONT-01](../../docs/requirements/REQ-ONT-01-security-paper-ontology.md), [REQ-UI-01](../../docs/requirements/REQ-01-system_requirements.md)
- 設計仕様: [DSN-21 エンタープライズデザインシステム](../../docs/designs/DSN-21-enterprise_design_system_and_unified_console.md), [DSN-22 セキュリティオントロジー W3C 仕様書](../../docs/designs/DSN-22-security_and_threat_ontology_w3c_specification.md)
- 関連Issue: [Issue 187](187-implement-ontology-tbox-graph-ingestion-and-schema-view.md), [Issue 189](189-update-user-manual-commands.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [site/dashboard.html](../../site/dashboard.html) (エッジオブジェクト生成、Canvas ノード/エッジ描画ロジック、CLUSTERS 定義)
- [x] [docs/manuals/USR-01-user_manual.md](../../docs/manuals/USR-01-user_manual.md) (Schema View のカラーパレットおよびエッジ表現体系の追記)
- [x] [docs/issues/README.md](README.md) (Issue 台帳への登録と進捗管理)

---

## 4. 根本原因分析 (RCA) / Root Cause Analysis

### ① Edge が `undefined [HIGH]` となる原因:
- **`rel` プロパティの欠落**:
  `site/dashboard.html` の `applySchemaGraph()` 関数内で `edgeObj` を構築する際、Canvas 描画処理が参照する `rel` プロパティが代入されておらず（`label` と `type` のみ）、描画ループ内の `e.rel` が `undefined` と評価されていた。
- **メタモデルへの推論確信度の誤付与**:
  TBox メタモデルスキーマはクラス体系の公理構造であり、確率的推論の信頼水準（Confidence Tier）は存在しない。しかし `confidence_tier: 'HIGH'` がハードコードされていたため、`e.rel + (e.confidence_tier ? ' [' + e.confidence_tier + ']' : '')` によって **`undefined [HIGH]`** と連結表示されていた。

### ② すべての Vertex が黒色 (`#2b2b2b`) になる原因:
- **CTI モード限定のカラー判定**:
  Canvas ノード描画ループ（Line 3079）のカラー決定式が `const nodeColor = currentGraphMode === 'cti' ? (n.color || '#9CA3AF') : clusterCfg.color;` となっており、`currentGraphMode === 'schema'` の場合でも `clusterCfg.color` が参照されていた。
- **フォールバックによる黒色強制適用**:
  定数 `CLUSTERS` に `schema` クラスタが登録されておらず、フォールバックの `CLUSTERS.entity.color`（`#2b2b2b` = 黒色）が全ノードに強制適用されていた。

---

## 5. 暫定対処と恒久対策 / Workaround & Permanent Fix
* **暫定対処 (Workaround)**: サイドバー Drawer のインスペクター（`nodeCallout`）からクラス詳細とオントロジー関係を確認。
* **恒久対策 (Permanent Fix)**:
  1. `applySchemaGraph()` で `rel: e.label || e.type || 'relates'` を代入し、`confidence_tier` のハードコードを撤廃。
  2. Canvas エッジ描画に `currentGraphMode === 'schema'` 分岐を新設し、因果関係（赤実線）、具現化エビデンス（紫破線）、クラス継承（灰点線）、標準述語（インディゴ実線）と凡例どおりの線種を適用。エッジハイライト時は `[HIGH]` なしで述語名を表示。
  3. Canvas ノード色決定ロジックで `currentGraphMode === 'schema'` も対象に含め、`n.color`（バックエンドの `ONTOLOGY_CLASS_COLORS`）を適用。`CLUSTERS.schema` も定義。

---

## 6. 実装方針 / Implementation Plan
Target Branch: `fix/190-fix-schema-view-edge-undefined-and-vertex-colors`

1. **`site/dashboard.html` の改修**:
   - `CLUSTERS` 定数に `schema: { color: '#8b5cf6', label: 'SCHEMA' }` を追加。
   - `applySchemaGraph()` の `edgeObj` に `rel: relName` を設定。
   - Canvas エッジ描画ループに Schema View 専用スタイル分岐を追加し、ハイライト表示ラベルを最適化。
   - Canvas ノード描画ループで `currentGraphMode === 'schema'` 時に `n.color` を適用。
2. **Web サーバーへの反映と動作確認**:
   - `make reload_supervisor` によるローリングリロード。
   - `curl http://localhost:8000/dashboard` による配信検証。
3. **ドキュメント更新**:
   - `docs/manuals/USR-01-user_manual.md` に各クラスの配色パレットとエッジ表現体系を追記。

---

## 7. 完了条件 / Success Criteria (DoD)
- [x] Schema View でエッジホバー・ハイライト時に `undefined [HIGH]` が表示されず、正しい関係述語が表示されること。
- [x] Schema View の各 Vertex が黒色ではなく、「📐 W3C OWL TBox Schema」凡例どおりのカラフルな色分けで描画されること。
- [x] 因果関係、具現化エビデンス関係、継承関係のエッジ線種が凡例に合致していること。
- [x] `make build_js` および関連テストが全件 PASS すること。
- [x] `docs/manuals/USR-01-user_manual.md` に Schema View の表現体系が追記されていること。
- [x] `docs/issues/README.md` に登録・追跡されていること。
