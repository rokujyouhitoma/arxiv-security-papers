---
ID: 368
種別: Refactor
優先度: Medium
ステータス: Closed
---

# [REFACTOR] 巨大単一ファイル `outputs/index.md` (6.8MB) のスリム化および `papers_catalog.json` / Web UI との責務分離 (ID: 368)

## 1. 概要 / Summary

現在、`outputs/index.md` は全収集論文（数千件）を1つの Markdown テーブルに追記し続ける方式となっており、ファイルサイズが約 6.8MB に膨れ上がっていた。このため、毎回のパイプライン実行で巨大なテキスト差分が Git リポジトリに生じ、コミット履歴の肥大化と IDE 表示遅延の原因となっていた。

現在、全件の高度な検索・フィルタリング・閲覧機能は `outputs/database/papers_catalog.json`（3.4MB）、Web UI（`site/`）、および 5階層エグゼクティブサマリー（`outputs/executive_summaries/01_per_run` 〜 `05_annual`）に移行・完備されている。

本 Issue では、`outputs/index.md` の役割を「全件ダンプ」から「直近重要論文のハイライト＋各階層サマリー・Web UI・カタログへのナビゲーションポータル」として再定義・スリム化し、ファイルサイズを 6.8MB から約 21KB へと劇的に縮小（99.7% 削減）し、Git の肥大化防止とドキュメント責務の明確化を達成した。

---

## 2. トレーサビリティ / Traceability

- 関連 Issue: [Issue 361: レガシー重複台帳 processed_papers.json の完全廃止](361-deprecate-and-purge-legacy-processed-papers-json.md)
- 関連規定: `.agents/AGENTS.md` Section 5 (5-Tier Executive Summaries) & Section 7 (Root Index Synchronization)
- 関連コード: `src/pipeline/reporter/index_updater.py`
- 関連テスト: `tests/pipeline/test_index_updater.py`, `tests/pipeline/test_reporter.py`

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files

### レポート生成エンジン
- [x] `src/pipeline/reporter/index_updater.py`
- [x] `src/pipeline/arxiv_okf_fetcher.py`

### 生成対象ファイル
- [x] `outputs/index.md` (スリム化・ポータル再構成: 6.8MB -> 21KB)

### テストスイート
- [x] `tests/pipeline/test_index_updater.py`
- [x] `tests/pipeline/test_reporter.py`

---

## 4. 実装方針 / Implementation Plan

Target Branch: `refactor/368-streamline-index-md`

1. **`index_updater.py` の再設計**:
   - `MAX_INDEX_PAPERS = 50` を導入し、直近50件のハイライトに絞り込み。
   - ポータル構成へ変更：
     - ① プロジェクト概要およびステータスサマリー
     - ② 全件検索・データアクセス基盤（Web Console / papers_catalog.json / okf_papers / raw_data）への相対リンクナビゲーション
     - ③ ソート済みエグゼクティブサマリー層（01_per_run 〜 05_annual）への目次リンク
     - ④ 直近登録論文ハイライト（最新 50 件）
     - ⑤ 全論文の検索・閲覧について（Web コンソールおよびカタログ JSON への案内フッター）
2. **`outputs/index.md` の軽量再生成**:
   - 新ロジックにより `outputs/index.md` を 21KB にスリム化して再生成。
3. **テストの同期**:
   - `tests/pipeline/test_index_updater.py` を新規追加し、ポータル構成・50件上限・アトミック書き込みを検証。
4. **品質ゲートの検証**:
   - `make static_analysis` (xenon Rank A, mypy strict, flake8, black, isort) 100% PASS。
   - `make test` 100% PASS。

---

## 5. 完了条件 / Success Criteria (DoD)

- [x] `outputs/index.md` が巨大な全件ダンプから軽量なナビゲーションポータルにスリム化されること（6.8MBから21KBへ縮小）。
- [x] 毎回のパイプライン実行時に差分が局所化されること。
- [x] `index_updater.py` のユニットテストが 100% PASS すること。
