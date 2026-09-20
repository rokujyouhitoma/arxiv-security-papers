---
ID: 361
種別: Refactor
優先度: High
ステータス: Closed
---

# [REFACTOR] レガシー重複台帳 processed_papers.json (7.2MB) の完全廃止および outputs/database/papers_catalog.json への一本化 (ID: 361)

## 1. 概要 / Summary

プロジェクト初期に作成された単一の論文重複防止台帳 `processed_papers.json`（約7.2MB）は、DSN-03（2.4節）および Issue 228 により `PipelineStateManager` と `outputs/database/papers_catalog.json`（3.4MB）へマスターデータが完全移行されている。

しかし、`config.json`、`src/settings.py`、`src/web/gateway/handlers.py`、`src/cli/commands/dbshell.py` 等でレガシーファイルへの参照が一部残存しており、7.2MB の巨大 JSON が Git リポジトリのルートに存続していた。

本 Issue では、`processed_papers.json` を完全に廃止・削除し、データストアを `outputs/database/papers_catalog.json` に一本化することで、Git リポジトリの大幅な軽量化とデータ二重管理の根絶を達成する。

---

## 2. 影響範囲と関連ファイル / Scope and Affected Files

- [x] `processed_papers.json` (完全削除)
- [x] `config.json` (`state_file` のパス更新)
- [x] `src/settings.py` (`processed_papers` 仮想テーブルの LOCATION 更新)
- [x] `src/web/gateway/handlers.py` (`_load_processed_papers_stat`, `_introspect_processed_papers_table` 等の参照先更新)
- [x] `src/pipeline/arxiv_okf_fetcher.py` (レガシーダンプ処理の整理)
- [x] `src/cli/commands/dbshell.py` (`_mount_json_tables` の参照先更新)
- [x] `src/analytics/aggregator.py` (`_calculate_token_savings` の参照先更新)
- [x] `tests/web/test_dashboard_rapid_reload.py` (SSE ストリーム teardown デッドロック防止)

---

## 3. 実装方針 / Implementation Plan

Target Branch: `refactor/361-purge-legacy-processed-papers`

1. **参照先の切り替え**:
   - `config.json` の `paths.state_file` を `"outputs/database/papers_catalog.json"` に変更。
   - `src/settings.py` の `processed_papers` の `LOCATION` を `outputs/database/papers_catalog.json` に変更。
   - `src/web/gateway/handlers.py` で `outputs/database/papers_catalog.json` を優先・直接参照するように更新。
   - `src/cli/commands/dbshell.py` の `cat_json` で `outputs/database/papers_catalog.json` を直接参照。
   - `src/analytics/aggregator.py` で `outputs/database/papers_catalog.json` を直接参照。
2. **`processed_papers.json` の安全な削除**:
   - `outputs/database/papers_catalog.json` の件数・整合性を確認（14,681件の clean_id が 100% 網羅され、欠損ゼロであることを実証）した上で、`git rm processed_papers.json` を実行。
3. **テストスイートの同期**:
   - `tests/web/test_dashboard_rapid_reload.py` の teardown で `httpd.shutdown()` にタイムアウトを導入しテスト安定化。
4. **品質ゲートの検証**:
   - `make check_format` 100% PASS
   - `make static_analysis` (radon, xenon CC rank A, mypy --strict) 100% PASS
   - `make test` 100% PASS

---

## 4. 完了条件 / Success Criteria (DoD)

- [x] `processed_papers.json` がリポジトリから完全に削除されていること。
- [x] `settings.py` の `processed_papers` 仮想テーブルが `outputs/database/papers_catalog.json` を指していること。
- [x] `config.json` の `state_file` が `outputs/database/papers_catalog.json` に更新されていること。
- [x] Web Gateway および CLI dbshell が `papers_catalog.json` から正常に論文数・メタデータを取得できること。
- [x] 全ユニットテストおよび静的解析（xenon CC rank A, mypy）が 100% PASS すること。
