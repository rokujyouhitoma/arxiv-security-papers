---
ID: 164
種別: Feature
優先度: High
ステータス: Open (New)
---

# [FEAT/ENH] /dashboard tab=graph におけるエッジ確信度（Confidence Tier）＆推論ルール絞り込みフィルタとエビデンス（スニペット）表示の実装 (ID: 164)

## 1. 概要 / Summary
Issue 162 および Issue 163 により、グラフデータベース（`PropertyGraphEngine`）内の Edge に「判定ルール（Rule ID/Name）」「推論機構（Inference Mechanism）」「確信度ティア（Confidence Tier: HIGH / MEDIUM / LOW）」「根拠エビデンス（引用スニペット・マッチ語彙）」が完全に刻印された。

本課題では、これらの説明責任メタデータを `/dashboard?tab=graph` の Web UI 可視化画面に統合し、アナリスト・運用者が画面上で直感的に探索・検証できるようにする：
1. **確信度ティア絞り込みコントロール**:
   - 「確信度 HIGH のみ（厳格・誤検知ゼロモード）」「MEDIUM 以上（推奨デフォルト）」「全件表示（低確信度・探索モード）」を切り替えるトグル/ドロップダウンの追加。
2. **推論ルール（EIROM）別エッジフィルタ**:
   - 「正規表現直接一致（RULE-EDGE-PAPER-TECH-REGEX-01）」「タイトル親和性」「アブストラクト語彙」等、適用ルール種別に応じたエッジ表示・非表示フィルタリング。
3. **エッジホバー / クリック時のエビデンス・ツールチップ表示**:
   - グラフ上のエッジをホバーまたはクリックした際に、ルール名、推論機構、確信度スコア、および論文本文から抽出された「根拠引用スニペット（Evidence Snippet）」を表示する情報パネル・ツールチップの実装。
4. **既存エッジフィルタ（Issue 146: Relation Type Filter）との整合性**:
   - 既存のラベル別（`TARGETS`, `PROPOSES_DEFENSE`, `DISCUSSES` 等）フィルタと複合適用可能な構造とする。

---

## 2. トレーサビリティ / Traceability
- 関連資料:
  - `docs/designs/DSN-17-security_knowledge_ontology.md` (Rev 2.0 Section 6 & 11)
  - `docs/designs/DSN-18-property_graph_database_engine.md`
  - `docs/issues/closed/162-enhance-graph-edge-inference-mechanism-and-confidence-attributes.md`
  - `docs/issues/closed/163-implement-edge-inference-rule-ontology-master.md`
  - `docs/issues/146-implement-edge-relation-type-filter-in-graph-tab.md`
  - `src/web/presentation/` (HTML/JS グラフ描画テンプレート)
  - `src/web/gateway/handlers.py` (グラフデータ提供 API)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] `src/web/gateway/handlers.py`: `/api/graph` および `/dashboard` 用エッジデータシリアライザに確信度・ルール・エビデンス属性を含める
- [ ] `src/web/presentation/template.py` / `src/web/presentation/` (グラフタブ HTML/JS):
  - 確信度セレクタ（`High Only`, `Medium+`, `All`）UI
  - ルール別トグルUI
  - SVG/Canvas/D3 エッジ描画時の確信度線種・透明度差別化（HIGH=太実線, MEDIUM=通常, LOW=点線等）
  - エッジクリック時のエビデンス詳細モーダル / ツールチップ
- [ ] `tests/web/test_dashboard_graph_tab.py`: 確信度フィルタおよびエビデンス描画のテスト追加
- [ ] `tests/web/gateway/test_gateway.py`: API エッジ属性レスポンスのテスト追加

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/164-dashboard-graph-edge-confidence-ui`

1. **API レスポンスのエッジプロパティ拡張**:
   - Web Gateway ハンドラにおいて、グラフのエッジ辞書に `confidence`, `confidence_tier`, `primary_rule_id`, `inference_mechanism`, `evidence_quote` を含めて JSON シリアライズする。
2. **フロントエンド描画ロジックの改修**:
   - JavaScript 側でエッジ描画時に `min_tier` フィルタ条件判定を実施。
   - エッジ線種・スタイルを確信度に応じて動的調整。
   - エッジ選択イベントでエビデンス引用文を表示。
3. **品質ゲートとテスト**:
   - `make check_format` および `make static_analysis` (Xenon Rank A, Mypy `--strict`) 適合。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] `/dashboard?tab=graph` 画面で確信度（HIGH / MEDIUM / LOW）によるエッジ絞り込みがリアルタイムに動作すること
- [ ] エッジホバー/クリック時に判定ルール・確信度スコア・根拠スニペットが表示されること
- [ ] API レスポンスにエッジ推論メタデータが正しくシリアライズされていること
- [ ] 単体テスト・回帰テストが 100% PASS すること
- [ ] `make check_format` および `make static_analysis` が 100% PASS すること
