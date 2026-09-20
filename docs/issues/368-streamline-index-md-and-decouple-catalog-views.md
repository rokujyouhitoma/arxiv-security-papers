---
ID: 368
種別: Refactor
優先度: Medium
ステータス: Open (In Progress)
---

# [REFACTOR] 巨大単一ファイル `outputs/index.md` (6.8MB) のスリム化および `papers_catalog.json` / Web UI との責務分離 (ID: 368)

## 1. 概要 / Summary

現在、`outputs/index.md` は全収集論文（数千件）を1つの Markdown テーブルに追記し続ける方式となっており、ファイルサイズが約 6.8MB に膨れ上がっている。このため、毎回のパイプライン実行で巨大なテキスト差分が Git リポジトリに生じ、コミット履歴の肥大化と IDE 表示遅延の原因となっている。

現在、全件の高度な検索・フィルタリング・閲覧機能は `outputs/database/papers_catalog.json`（3.4MB）、Web UI（`site/`）、および 5階層エグゼクティブサマリー（`outputs/executive_summaries/01_per_run` 〜 `05_annual`）に移行・完備されている。

本 Issue では、`outputs/index.md` の役割を「全件ダンプ」から「直近重要論文のハイライト＋各階層サマリー・Web UI・カタログへのナビゲーションポータル」として再定義・スリム化（または月別インデックス等への分割）し、Git の肥大化を防止するとともにドキュメント責務の明確化を達成する。

---

## 2. トレーサビリティ / Traceability

- 関連 Issue: [Issue 361: レガシー重複台帳 processed_papers.json の完全廃止](closed/361-deprecate-and-purge-legacy-processed-papers-json.md)
- 関連規定: `.agents/AGENTS.md` Section 5 (5-Tier Executive Summaries) & Section 7 (Root Index Synchronization)
- 関連コード: `src/pipeline/reporter/index_updater.py`

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files

### レポート生成エンジン
- [ ] `src/pipeline/reporter/index_updater.py`
- [ ] `src/pipeline/arxiv_okf_fetcher.py`

### 生成対象ファイル
- [ ] `outputs/index.md` (スリム化・再構成)

### テストスイート
- [ ] `tests/pipeline/reporter/test_index_updater.py`

---

## 4. 実装方針 / Implementation Plan

Target Branch: `refactor/368-streamline-index-md`

1. **`index_updater.py` の再設計**:
   - 全件レコードを単一 Markdown に展開するロジックを改修。
   - ポータル構成へ変更：
     - ① プロジェクト概要およびステータスサマリー
     - ② 直近 N 件（例: 最新 50〜100 件）のピックアップテーブル
     - ③ 年別・月別サマリー（`outputs/executive_summaries/`）への目次リンク
     - ④ 全件検索用 Web UI（`site/index.html`）および `papers_catalog.json` へのナビゲーション
2. **`outputs/index.md` の軽量再生成**:
   - 新ロジックにより `outputs/index.md` を数十KB程度にスリム化して再生成。
3. **テストの同期**:
   - `test_index_updater.py` における出力構造や行数アサーションを新仕様に合わせて更新。
4. **品質ゲートの検証**:
   - `make static_analysis`
   - `make test`

---

## 5. 完了条件 / Success Criteria (DoD)

- [ ] `outputs/index.md` が巨大な全件ダンプから軽量なナビゲーションポータルにスリム化されること（MB単位からKB単位へ縮小）。
- [ ] 毎回のパイプライン実行時に差分が局所化されること。
- [ ] `index_updater.py` のユニットテストが 100% PASS すること。
