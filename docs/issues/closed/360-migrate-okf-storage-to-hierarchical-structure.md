---
ID: 360
種別: Refactor
優先度: High
ステータス: Closed
---

# [REFACTOR] OKFストレージ階層の再編 (outputs/okf/papers, outputs/okf/cves) および okf_papers 配下 CVE-*.md の安全移管・完全削除 (ID: 360)

## 1. 概要 / Summary

現在、`outputs/okf_papers/` 配下に学術論文（arXiv論文）に加えて、過去に CISA KEV から取得された 1,713件の脆弱性情報 (`CVE-*.md`) が混入している。また、脆弱性 OKF データは `outputs/okf_vulnerabilities/`（NVD CVE）にも保管されており、弱点 OKF データは `outputs/okf_weaknesses/`（CWE）に分離されている。

本 Issue では、ストレージ階層を整理し、学術論文と脆弱性データを明確に分離・統一体系化する。

具体的には以下の2フェーズを実施する：
- **Phase 1: CVE-*.md の安全移管と okf_papers からの完全削除**
  - `outputs/okf_papers/*/CVE-*.md` (1,713件) を現在の CVE 保管領域 (`outputs/okf_vulnerabilities/`) へ安全に移動・マージ（CISA KEV データの救出・統合）。
  - `outputs/okf_papers/` から `CVE-*.md` および空になった年代ディレクトリを完全削除。
- **Phase 2: 統一階層 `outputs/okf/papers/`, `outputs/okf/cves/` への完全移行**
  - `outputs/okf_papers/` -> `outputs/okf/papers/`
  - `outputs/okf_vulnerabilities/` -> `outputs/okf/cves/`
  - `outputs/okf_weaknesses/` -> `outputs/okf/cwes/`
  - Python パイプライン、設定、Web Gateway、フロントエンド、インデックス・サマリー、テストスイート、エージェントルールのパス参照を新階層へ一括リファクタリング。
  - 後方互換性シンボリックリンクを設置し、外部参照や旧キャッシュへの耐性を確保。

---

## 2. 影響範囲と関連ファイル / Scope and Affected Files

### ストレージ・データ
- [ ] `outputs/okf_papers/` -> `outputs/okf/papers/`
- [ ] `outputs/okf_vulnerabilities/` -> `outputs/okf/cves/`
- [ ] `outputs/okf_weaknesses/` -> `outputs/okf/cwes/`
- [ ] `processed_papers.json`（論文 OKF パス参照）
- [ ] `outputs/index.md`（論文リンク）
- [ ] `outputs/executive_summaries/`（各階層サマリー内論文リンク）

### Python コア・パイプライン・バックエンド
- [ ] `src/domain/security/pipeline/okf_pipeline.py`
- [ ] `src/settings.py`
- [ ] `src/pipeline/arxiv_okf_fetcher.py`
- [ ] `src/pipeline/transformer/okf_serializer.py`
- [ ] `src/pipeline/cti_backfill.py`
- [ ] `src/pipeline/reporter/index_updater.py`
- [ ] `src/pipeline/reporter/summary_generator.py`
- [ ] `src/web/gateway/handlers.py`
- [ ] `src/analytics/aggregator.py`
- [ ] `src/ontology/seeder.py`
- [ ] `src/mcp/papers_server.py`
- [ ] `src/search/vector_engine.py`
- [ ] `src/cli/commands/dbshell.py`
- [ ] `src/cli/commands/dbsync.py`

### フロントエンド
- [ ] `site/app.js`
- [ ] `site/externs.js`
- [ ] `site/app-min.js` (再コンパイル)

### テストスイート
- [ ] `tests/domain/security/test_okf_pipeline_isolation.py`
- [ ] `tests/web/gateway/test_gateway.py`
- [ ] `tests/web/test_web_server.py`
- [ ] `tests/web/test_dashboard_html.py`
- [ ] `tests/web/presentation/test_presentation.py`
- [ ] `tests/web/test_database_real_introspection.py`
- [ ] `tests/pipeline/test_reporter.py`
- [ ] `tests/pipeline/test_transformer.py`
- [ ] `tests/pipeline/test_cti_backfill.py`
- [ ] `tests/analytics/test_aggregator.py`
- [ ] `tests/test_settings_timezone.py`
- [ ] `tests/mcp/test_security_hardening.py`
- [ ] `tests/database/test_show_statements.py`

### ドキュメント & ルール
- [ ] `.agents/AGENTS.md`
- [ ] `.agents/skills/okf-converter/SKILL.md`
- [ ] `.agents/skills/verify-quality-gates/SKILL.md`
- [ ] `docs/designs/DSN-02-low_level_design.md`
- [ ] `docs/designs/DSN-03-pipeline_architecture.md`
- [ ] `docs/designs/DSN-14-graph_engineering_dashboard.md`

---

## 3. 実装方針 / Implementation Plan

Target Branch: `refactor/360-hierarchical-okf-storage`

### Step 1: Phase 1 - CVE ファイルの安全移管と okf_papers からの完全削除
1. `outputs/okf_papers/` 配下の `CVE-*.md` (1,713件) を抽出し、`outputs/okf_vulnerabilities/YYYY-MM-DD/` へ移動・マージ。
2. `outputs/okf_papers/` から `CVE-*.md` を完全削除。
3. 論文が存在せず CVE のみであった空の日付ディレクトリを削除。
4. `outputs/okf_papers` には学術論文のみが残っていることを確認。

### Step 2: Phase 2 - 新階層構造へのディレクトリ移動と互換リンク
1. `outputs/okf/` ディレクトリを作成。
2. ディレクトリを移動：
   - `outputs/okf_papers` -> `outputs/okf/papers`
   - `outputs/okf_vulnerabilities` -> `outputs/okf/cves`
   - `outputs/okf_weaknesses` -> `outputs/okf/cwes`
3. 後方互換性のためのシンボリックリンクを作成：
   - `outputs/okf_papers -> okf/papers`
   - `outputs/okf_vulnerabilities -> okf/cves`
   - `outputs/okf_weaknesses -> okf/cwes`

### Step 3: Python コード・設定・Web Gateway・テストの更新
1. パス定数を `outputs/okf/papers`, `outputs/okf/cves`, `outputs/okf/cwes` に更新。
2. Web Gateway の静的ファイルハンドラー `/okf/papers/...`, `/okf/cves/...` をサポート。
3. 全ユニットテスト内のパス記述を更新。
4. `processed_papers.json`、`outputs/index.md`、サマリーファイルのリンクを置換。
5. フロントエンド JS を再ビルド (`make build_js`)。

### Step 4: 品質ゲート検証
1. `make py_compile`
2. `make format`
3. `make static_analysis`
4. `make test`
5. `make verify_quality`

---

## 4. 完了条件 / Success Criteria (DoD)

- [x] `outputs/okf/papers/` 配下に学術論文のみが保管され、`CVE-*.md` が 0件 であること。
- [x] CISA KEV 由来の `CVE-*.md` (1,713件) が `outputs/okf/cves/` 配下に欠損なく安全に統合されていること。
- [x] OKF パイプライン (`okf_pipeline.py`) がアイテム種別（paper, vulnerability, weakness）に応じて `outputs/okf/papers`, `outputs/okf/cves`, `outputs/okf/cwes` に正しく自動振り分けすること。
- [x] 全テスト（`tests/`）が PASS すること。
- [x] `make verify_quality` の全品質ゲート（フォーマット、静的解析、型検査、テスト、JSビルド）が 100% PASS すること。
