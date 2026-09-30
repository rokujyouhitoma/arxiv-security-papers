---
ID: 404
種別: Feature
優先度: Medium
ステータス: Open (New)
---

# [FEAT/ENH] 最新OKF収集データの5階層エグゼクティブサマリー自動集約と動的Mermaidトレンド同期 (ID: 404)

## 1. 概要 / Summary

プロジェクトでは、arXiv 論文、CVE 脆弱性、CWE 弱点などのセキュリティインテリジェンスが継続的にスパイダーおよびバックフィル機構によって収集され、`outputs/okf/` 配下に蓄積されている。
しかし、これら収集成果物を統括する 5 階層エグゼクティブサマリー（`outputs/executive_summaries/01_per_run`, `02_daily`, `03_monthly`, `04_quarterly`, `05_annual`）および `outputs/index.md` は、手動または特定バッチ実行時のみ更新される運用となっており、直近の CVE/CWE 収集データとの動的同期や、最新脅威動向を反映した Mermaid ナレッジマップ・技術トレンド図の自動更新が追随していない。

本 Issue では、収集された OKF ドキュメント群を対象に、Google OKF v0.2 仕様およびプロジェクトガバナンス（100% 日本語表記、相対パスリンク、Mermaid 構成図）に完全準拠した 5 階層サマリー自動更新パイプラインを確立し、最新の攻撃手法・脅威トレンドを視覚的に要約・同期する。

---

## 2. トレーサビリティ / Traceability

- **関連 Issue**:
  - [Issue 368 (Closed): 巨大単一ファイル outputs/index.md のスリム化および papers_catalog.json / Web UI との責務分離](closed/368-streamline-index-md-and-decouple-catalog-views.md)
  - [Issue 360 (Closed): OKFストレージ階層の再編 (outputs/okf/papers, outputs/okf/cves) およびデータ移管](closed/360-migrate-okf-storage-to-hierarchical-structure.md)
  - [Issue 199 (Closed): W3C Turtle / JSON-LD / STIX 2.1 マルチフォーマットエクスポート API の実装](closed/199-implement-multi-format-graph-export-ttl-jsonld-stix.md)
- **アーキテクチャ規約**:
  - Google OKF v0.2 仕様準拠
  - 5-Tier Executive Summaries (01_per_run 〜 05_annual) 順序ディレクトリ規約
  - 100% 完全日本語要約・Markdown 表形式・相対パスリンク強制

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files

- [ ] [src/summary/executive_generator.py](../../src/summary/executive_generator.py) (5階層サマリー集約生成エンジンの OKF/CVE/CWE 対応拡張)
- [ ] [src/summary/trend_analyzer.py](../../src/summary/trend_analyzer.py) (セキュリティドメイン急上昇キーワード抽出および Mermaid マインドマップ自動生成)
- [ ] [src/summary/index_synchronizer.py](../../src/summary/index_synchronizer.py) (`outputs/index.md` およびナビゲーション目次の自動同期)
- [ ] [outputs/executive_summaries/](../../outputs/executive_summaries/) (01〜05 階層のサマリーファイル生成)
- [ ] [tests/summary/test_executive_summaries.py](../../tests/summary/test_executive_summaries.py) (相対リンク、日本語率、Mermaid 構文整合性テスト)
- [ ] [docs/issues/README.md](README.md) (Issue 台帳の進捗更新)

---

## 4. 実装方針 / Implementation Plan

Target Branch: `feat/404-okf-5-tier-executive-summary-sync-and-trend-analysis`

1. **マルチソース集約**:
   - `outputs/okf/papers/`, `outputs/okf/cves/`, `outputs/okf/cwes/` の YAML フロントマターからタグ・タイトル・要約・公開日を高速インデックス化。
2. **Mermaid トレンド図生成**:
   - 出現頻度の高い MITRE ATT&CK 手法、CWE 分類、暗号・LLM セキュリティ等のクラスタリングを行い、月次（`03_monthly`）・四半期（`04_quarterly`）サマリー用の Mermaid Mindmap を自動描画。
3. **品質検証自動化**:
   - 全内部リンクが相対パス（`../`）であること、Markdown 表の全カラムが日本語であること、絶対パスが 0 件であることを `verify-quality-gates` スキルで検証。

---

## 5. 完了条件 / Success Criteria (DoD)

- [ ] `01_per_run/` から `05_annual/` までの全 5 階層で最新 OKF データを反映した日本語サマリーが生成・更新される。
- [ ] サマリー内のリンクが全て相対パスであり、リンク切れ・絶対パスが 0 件であること。
- [ ] 月次・四半期サマリーに最新セキュリティ動向の Mermaid 構成図が正しく埋め込まれること。
- [ ] `make static_analysis` (mypy --strict, xenon CC <= 3) および全テストが 100% PASS すること。
