---
ID: 199
種別: Feature
優先度: Medium
ステータス: Open (In Progress)
---

# [FEAT] W3C Turtle (.ttl) / JSON-LD / STIX 2.1 マルチフォーマットエクスポート API および UI ダウンロード機能の実装 (ID: 199)

## 1. 概要 / Summary

統合コンソールの Schema View (TBox) および CTI Knowledge Graph (ABox) において、構築されたセキュリティ知識オントロジーおよび論文・脅威因果ネットワークを、国際標準フォーマット（W3C Turtle `.ttl`、W3C JSON-LD、OASIS STIX 2.1 Bundle JSON）で一括出力・ダウンロードできるエクスポート基盤を完成させる。
外部のナレッジグラフ基盤（Protégé, Neo4j, Apache Jena 等）や SIEM/SOAR/TIP ツールへのシームレスなデータ連携を可能にする。

### 調査結果と現状分析 (2026-09 最新コードベース照合)
本 Issue の初回起票以降、バックエンドのコアエンジンおよび Web API は先行して実装・単体テスト済みであるが、UI のダウンロードコンポーネントおよび Gateway レベルの結合テストが未実装のまま残されている。

1. **実装完了済み**:
   - `src/ontology/export.py`: Pure-Python（外部依存ゼロ）のマルチフォーマットシリアライザー（`GraphExporter`, `TurtleSerializer`, `JSONLDSerializer`, `STIXSerializer`）
   - `src/web/gateway/handlers.py`: `/api/export/graph?format={turtle|jsonld|stix}` エンドポイント
   - `tests/ontology/test_export_formats.py`: 34件の単体テスト（100% PASS）
2. **未実装（本 Issue の主対象）**:
   - `site/dashboard.html`: Graph / Schema コントロールデッキへのエクスポート・ダウンロードUIボタングループの設置
   - `tests/web/test_graph_export_api.py`: Web Gateway 経由のエクスポート HTTP API 結合テスト（Content-Type, Content-Disposition, 400 Bad Request ハンドリング）

---

## 2. トレーサビリティ / Traceability
- 設計書: [DSN-22 セキュリティおよび脅威インテリジェンス知識オントロジー W3C 仕様書](../designs/DSN-22-security_and_threat_ontology_w3c_specification.md)
- 設計書: [DSN-17 セキュリティ知識オントロジー & CTI 推論基盤設計仕様書](../designs/DSN-17-security_knowledge_ontology.md)
- 設計書: [DSN-21 エンタープライズ統合デザインシステム ＆ 統合コンソール UI 包括設計書](../designs/DSN-21-enterprise_design_system_and_unified_console.md)

---

## 3. 脅威モデルとセキュリティ要件 / Threat Modeling & Security Requirements

1. **パラメータインジェクション / 不正入力**:
   - 脅威: `format` クエリパラメータに対する不正文字列や過長入力。
   - 対策: `exporter.export(fmt)` におけるホワイトリスト検証（`turtle`, `ttl`, `jsonld`, `json-ld`, `stix`, `stix21` のみ許容、それ以外は `ValueError` -> `400 Bad Request`）。
2. **ヘッダーインジェクション (CRLF Injection)**:
   - 脅威: `Content-Disposition: attachment; filename="..."` への改行コード混入。
   - 対策: 固定文字列（`graph.ttl`, `graph.jsonld`, `graph_stix_bundle.json`）のみを使用し、外部入力をファイル名に一切反映しない。
3. **DoS (Denial of Service) / メモリ枯渇**:
   - 脅威: 巨大ナレッジグラフに対する過剰なエクスポートリクエストによるメモリ圧迫。
   - 対策: `Cache-Control: no-store` の設定、PropertyGraphEngine のリソース適切な解放（`engine.close()`）、ストリーミング親和性の確保。
4. **XSS (Cross-Site Scripting)**:
   - 脅威: UI ダウンロードボタンにおける不適切なスクリプト実行。
   - 対策: Vanilla JS による安全なリンク生成（`window.location.href` または `<a>` タグによるダイレクトダウンロード、HTMLインジェクションなし）。

---

## 4. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [site/dashboard.html](../../site/dashboard.html) (Graph / Schema コントロールデッキへのエクスポート・ダウンロードドロップダウン / ボタングループ追加)
- [ ] [tests/web/test_graph_export_api.py](../../tests/web/test_graph_export_api.py) (新規: Gateway レベルのエクスポート結合テスト)
- [x] [src/ontology/export.py](../../src/ontology/export.py) (実装済み: マルチフォーマットシリアライザー [Turtle / JSON-LD / STIX 2.1])
- [x] [src/web/gateway/handlers.py](../../src/web/gateway/handlers.py) (実装済み: `/api/export/graph?format={turtle|jsonld|stix}`)
- [x] [tests/ontology/test_export_formats.py](../../tests/ontology/test_export_formats.py) (実装済み: 34件の単体テスト)

---

## 5. 実装方針 / Implementation Plan
Target Branch: `feat/199-implement-multi-format-graph-export-ttl-jsonld-stix`

### Phase 1: Web Gateway API 結合テストの整備
1. `tests/web/test_graph_export_api.py` を作成。
2. 以下のテストケースを実装・検証:
   - `test_export_turtle_endpoint`: `/api/export/graph?format=turtle` -> 200 OK, `Content-Type: text/turtle`, `filename="graph.ttl"`
   - `test_export_jsonld_endpoint`: `/api/export/graph?format=jsonld` -> 200 OK, `Content-Type: application/ld+json`, `filename="graph.jsonld"`
   - `test_export_stix_endpoint`: `/api/export/graph?format=stix` -> 200 OK, `Content-Type: application/json`, `filename="graph_stix_bundle.json"`
   - `test_export_default_format`: フォーマット省略時にデフォルト `turtle` が返却されること
   - `test_export_invalid_format`: 未知のフォーマット（例: `format=xml`）指定時に 400 Bad Request が返却されること
   - `test_export_cors_and_security_headers`: CORS ヘッダーおよびセキュリティヘッダー（X-Content-Type-Options 等）の検証

### Phase 2: UI ダウンロードインターフェースの統合 (`site/dashboard.html`)
1. **HTML コントロールデッキへのボタングループ追加**:
   - `graph-controls-row` のボタングループ（`spacingSlider` や `MIN DEGREE` の右側）に、洗練されたエクスポートドロップダウンメニュー `btnExportGraph` を配置。
   - メニュー項目:
     - 🐢 **W3C Turtle (.ttl)**: RDF 1.1 / OWL オントロジー
     - 🌐 **JSON-LD (.jsonld)**: Linked Data 構造化グラフ
     - 🛡️ **STIX 2.1 (.json)**: OASIS CTI 脅威インテリジェンスバンドル
2. **JavaScript ダウンロード処理の実装**:
   - `exportGraph(format)` 関数を実装。
   - `/api/export/graph?format=${format}` へのブラウザダウンロード起動。
   - ダウンロード開始時のトースト通知 / フィードバック表示。
   - キーボードショートカット（例: Alt+E でエクスポートメニュー開閉）の対応。
3. **デザインシステム適合**:
   - [DSN-21](../designs/DSN-21-enterprise_design_system_and_unified_console.md) に準拠した Glassmorphic & Brutalist ハイブリッドデザイン（ホバーエフェクト、ツールチップ、キーボードアクセシビリティ）。

### Phase 3: 品質ゲート & 回帰検証
1. `make check_format` (black, isort, flake8)
2. `make static_analysis` (xenon Rank A, mypy --strict, bandit)
3. 新規テストおよび関連テストの実行 (`pytest tests/ontology/test_export_formats.py tests/web/test_graph_export_api.py`)
4. ブラウザでの実機動作確認（`/api/export/graph` のダウンロード発火確認）

---

## 6. 完了条件 / Success Criteria (DoD)
- [ ] `/api/export/graph?format={turtle|jsonld|stix}` の Gateway 結合テストがすべて PASS すること。
- [ ] 不正なフォーマット指定時に適切なエラーメッセージと 400 Bad Request が返却されること。
- [ ] `site/dashboard.html` の CTI Graph および Schema View から、ワンクリックで Turtle, JSON-LD, STIX 2.1 のファイルがダウンロードできること。
- [ ] DSN-21 デザインシステムに適合した UI デザイン・アクセシビリティが担保されていること。
- [ ] 全品質ゲート（フォーマット、静的解析、型検査、テスト）が 100% PASS すること。
