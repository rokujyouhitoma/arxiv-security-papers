---
ID: 057
種別: Feature
優先度: High
ステータス: Open (In Progress)
---

# [FEAT] マルチソース・マルチテーマ対応インテリジェンスプラットフォーム基盤（Pluggable Source Adapters & Theme-Aware Pipeline）の実装 (ID: 057)

## 1. 概要 / Summary
現在の `arxiv-security-papers` は arXiv の `cs.CR`（情報セキュリティ）カテゴリに特化して設計されています。
本 Issue では、収集対象ソース（arXiv 各種カテゴリ、IACR ePrint、汎用 RSS/Atom フィード等）の抽象化と、収集・分析テーマ（セキュリティ、AI Safety / LLM セキュリティ、ソフトウェア工学等）を設定駆動（JSON/YAML）で自在に切り替え・拡張できる「プラガブル・データソース・アダプタ」および「テーマ対応型パイプライン」を実装します。

既存の `cs.CR` 向け動作および 5層エグゼクティブサマリー・OKF v0.2 生成の後方互換性を100%維持した上で、複数テーマの独立収集・分析を可能にします。

---

## 2. トレーサビリティ / Traceability
- [DSN-14: 次世代データベースエンジン包括的アーキテクチャ設計書](../designs/DSN-14-database_engine_architecture.md)
- [ITストラテジスト（ST）マルチソース・マルチテーマ拡張検討書](../../.agents/AGENTS.md)
- Google OKF (Open Knowledge Format) v0.2 仕様

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [src/fetcher/ingestion/adapters/base.py](../../src/fetcher/ingestion/adapters/base.py) (新規: 共通 SourceAdapter 抽象基底クラス & データモデル)
- [x] [src/fetcher/ingestion/adapters/arxiv_adapter.py](../../src/fetcher/ingestion/adapters/arxiv_adapter.py) (新規: 多カテゴリ対応 arXiv アダプタ)
- [x] [src/fetcher/ingestion/adapters/iacr_adapter.py](../../src/fetcher/ingestion/adapters/iacr_adapter.py) (新規: IACR ePrint 暗号プレプリントアダプタ)
- [x] [src/fetcher/ingestion/adapters/feed_adapter.py](../../src/fetcher/ingestion/adapters/feed_adapter.py) (新規: 汎用 RSS/Atom フィードアダプタ)
- [x] [src/fetcher/ingestion/adapters/registry.py](../../src/fetcher/ingestion/adapters/registry.py) (新規: アダプタレジストリ)
- [x] [src/fetcher/ingestion/adapters/__init__.py](../../src/fetcher/ingestion/adapters/__init__.py) (新規: パッケージエクスポート)
- [x] [src/fetcher/transformer/theme.py](../../src/fetcher/transformer/theme.py) (新規: テーマ・タクソノミー動的設定マネージャ)
- [x] [src/fetcher/arxiv_okf_fetcher.py](../../src/fetcher/arxiv_okf_fetcher.py) (変更: マルチテーマ CLI 引数 `--theme` / `--all-themes` およびオーケストレーション)
- [x] [src/fetcher/ingestion/__init__.py](../../src/fetcher/ingestion/__init__.py) (変更: 新アダプタのエクスポート)
- [x] [src/fetcher/transformer/__init__.py](../../src/fetcher/transformer/__init__.py) (変更: テーママネージャのエクスポート)
- [x] [tests/fetcher/test_source_adapters.py](../../tests/fetcher/test_source_adapters.py) (新規: 各種アダプタの単体・統合テスト)
- [x] [tests/fetcher/test_multi_theme_pipeline.py](../../tests/fetcher/test_multi_theme_pipeline.py) (新規: マルチテーマパイプライン E2E テスト)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/057-pluggable-source-adapters-and-multi-theme-pipeline`

1. **Source Adapter インターフェース策定 (`src/fetcher/ingestion/adapters/base.py`)**:
   - `RawItem`: 取得メタデータおよびコンテンツを格納するデータクラス（`source_id`, `title`, `abstract`, `authors`, `published_date`, `url`, `content_type`, `pdf_url` 等）。
   - `BaseSourceAdapter`: `fetch_items(query, since, max_results)` および `fetch_content(item, output_dir)` を備えた抽象基底クラス。
2. **具象アダプタの実装**:
   - `ArxivSourceAdapter`: 既存の arXiv API & RSS フォールバックを統合し、`categories` 引数により `cs.CR`, `cs.AI`, `cs.LG`, `cs.SE` 等を任意にフェッチ。
   - `IacrEprintSourceAdapter`: IACR ePrint RSS/Atom フィード (`https://eprint.iacr.org/rss/rss.xml`) から暗号学論文をフェッチ。
   - `FeedSourceAdapter`: 任意の RSS 2.0 / Atom フィード URL からメタデータと本文をフェッチ。
   - `SourceRegistry`: アダプタ名（`arxiv`, `iacr`, `rss` 等）からアダプタインスタンスを取得するシングルトンレジストリ。
3. **テーマ管理エンジン (`src/fetcher/transformer/theme.py`)**:
   - `ThemeConfig`: テーマ名、対象ソース、クエリ条件、キーワードフィルタ、タクソノミー規則、出力ルートパスを保持。
   - 組み込みテーマ:
     - `security` (デフォルト): `cs.CR` + IACR ePrint、MITRE ATT&CK / STRIDE / CWE 分類。
     - `ai_safety`: `cs.AI`, `cs.LG`, `stat.ML`、OWASP Top 10 for LLM / MITRE ATLAS 分類。
     - `software_engineering`: `cs.SE`、セキュアコーディング・静的解析タクソノミー。
   - 外部 JSON 設定ファイルからのカスタムテーマ動的ロード対応。
4. **パイプラインオーケストレータ統合 (`src/fetcher/arxiv_okf_fetcher.py`)**:
   - `--theme <id>` および `--all-themes` CLI オプションの追加。
   - テーマごとの独立した状態管理 (`processed_papers_<theme>.json` または単一 JSON でのテーマ属性管理)。
   - テーマに応じた 5層エグゼクティブサマリー・OKF ディレクトリ生成。
   - 既存の引数指定なし実行時はデフォルトで `security` テーマ（`outputs/` 直下）として 100% 互換動作。
5. **テストスイートの実装**:
   - `tests/fetcher/test_source_adapters.py`: 各アダプタのパース、フォールバック、例外ハンドリングの検証。
   - `tests/fetcher/test_multi_theme_pipeline.py`: テーマ切り替え、ドライラン、複数テーマ実行時の出力整合性検証。

---

## 5. 完了条件 / Success Criteria (DoD)
- [x] `BaseSourceAdapter`, `ArxivSourceAdapter`, `IacrEprintSourceAdapter`, `FeedSourceAdapter`, `SourceRegistry` が実装されていること。
- [x] `ThemeManager` により `security`, `ai_safety`, `software_engineering` およびカスタムテーマのロード・解決が動作すること。
- [x] CLI から `--theme` および `--all-themes` でテーマ別パイプラインが実行可能であること。
- [x] 従来の `python3 src/fetcher/arxiv_okf_fetcher.py` / `make run` が一切の破壊的変更なく動作すること。
- [x] 新規テスト（`test_source_adapters.py`, `test_multi_theme_pipeline.py`）を含む全テストが PASS すること。
- [x] `make check_format` および `make static_analysis` (radon, xenon, mypy --strict, py_compile) が 100% PASS すること。
