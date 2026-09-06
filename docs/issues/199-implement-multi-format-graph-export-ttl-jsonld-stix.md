---
ID: 199
種別: Feature
優先度: Medium
ステータス: Open (New)
---

# [FEAT/ENH] W3C Turtle (.ttl) / JSON-LD / STIX 2.1 マルチフォーマットエクスポート API および UI ダウンロード機能の実装 (ID: 199)

## 1. 概要 / Summary

統合コンソールの Schema View (TBox) および CTI Knowledge Graph (ABox) において、構築されたセキュリティ知識オントロジーおよび論文・脅威因果ネットワークを、国際標準フォーマット（W3C Turtle `.ttl`、W3C JSON-LD、OASIS STIX 2.1 Bundle JSON）で一括出力・ダウンロードできるエクスポート基盤を実装する。
外部のナレッジグラフ基盤（Protégé, Neo4j, Apache Jena 等）や SIEM/SOAR/TIP ツールへのシームレスなデータ連携を可能にする。

---

## 2. トレーサビリティ / Traceability
- 設計書: [DSN-22 セキュリティおよび脅威インテリジェンス知識オントロジー W3C 仕様書](../designs/DSN-22-security_and_threat_ontology_w3c_specification.md)
- 設計書: [DSN-17 Pure-Python STIX 2.1 CTI 推論 & ATT&CK Navigator レイヤー自動生成基盤設計仕様書](../designs/DSN-17-pure_python_stix_cti_inference_and_navigator.md)
- 設計書: [DSN-21 エンタープライズ統合デザインシステム ＆ クラウドコンソール UI 包括設計書](../designs/DSN-21-enterprise_design_system_and_cloud_console_ui.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [src/ontology/export.py](../../src/ontology/export.py) (新規: マルチフォーマットシリアライザー [Turtle / JSON-LD / STIX 2.1])
- [ ] [src/web/gateway/handlers.py](../../src/web/gateway/handlers.py) (`/api/export/graph?format={ttl|jsonld|stix}` エンドポイント追加)
- [ ] [site/dashboard.html](../../site/dashboard.html) (Graph / Schema コントロールデッキへのエクスポート・ダウンロードボタングループ追加)
- [ ] [tests/ontology/test_export_formats.py](../../tests/ontology/test_export_formats.py) (新規ユニットテスト)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/199-implement-multi-format-graph-export-ttl-jsonld-stix`

1. **Pure-Python マルチフォーマットシリアライザーの実装**:
   - `src/ontology/export.py` において、`GraphStorage` および `OntologyRegistry` からノード・エッジ・属性を取得し、外部ライブラリ（rdflib 等）を用いずピュア Python で W3C 準拠の `.ttl` (Turtle)、`@context` を含む JSON-LD、および OASIS 準拠の STIX 2.1 Bundle JSON を生成するシリアライズ関数を実装。
2. **Web API エクスポートハンドラーの整備**:
   - `src/web/gateway/handlers.py` に `/api/export/graph` を追加。クエリパラメータ `format`（`turtle`, `jsonld`, `stix`）およびフィルタ条件（現在の検索・絞り込みサブグラフのみ、または全体）を受け付け、適切な `Content-Type` と `Content-Disposition: attachment; filename=...` でレスポンスを返却。
3. **UI 操作デッキへのダウンロードメニュー統合**:
   - `site/dashboard.html` の CTI Graph および Schema View のヘッダーコントロールに、ダウンロードアイコン付きのドロップダウンメニューを設置。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] `/api/export/graph?format=turtle` により妥当な W3C Turtle 形式の文字列が出力され、W3C バリデータに適合すること。
- [ ] `/api/export/graph?format=jsonld` により妥当な JSON-LD 形式が出力されること。
- [ ] `/api/export/graph?format=stix` により OASIS STIX 2.1 準拠の Bundle JSON が生成されること。
- [ ] Web コンソールからワンクリックで各フォーマットのファイルがダウンロードできること。
- [ ] テスト全件 PASS および静的解析エラー 0 件であること。
