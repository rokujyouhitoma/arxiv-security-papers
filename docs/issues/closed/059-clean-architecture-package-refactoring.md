# [Issue 059] クリーンアーキテクチャに基づく src/ および tests/ パッケージ再設計・リファクタリング

- **Status**: Open
- **Assignee**: All 13 Multi-Agent Specialists
- **Created**: 2026-08-21
- **Branch**: `refactor/059-clean-architecture-package-refactoring`

---

## 1. 概要 (Overview)

ドメイン駆動設計（DDD）およびクリーンアーキテクチャの原則に基づき、`src/` 配下のパッケージ構造を「Interface / Intelligence / Platform / Security」の4層に再編・リファクタリングする。
散在していた `src/gateway/` や `src/presentation/` を `src/web/` 配下に集約し、`src/fetcher/` を ETL インテリジェンス変換基盤の実態に合わせて `src/pipeline/` へ移行、レガシーシムを `src/compat/` に隔離するとともに、`tests/` 配下のディレクトリ構造を 1:1 に完全同期させる。

---

## 2. 完了定義 (Definition of Done)

- [x] **統合 Web サービス層 (`src/web/` & `tests/web/`)**:
  - `src/gateway/` $\rightarrow$ `src/web/gateway/`
  - `src/presentation/` $\rightarrow$ `src/web/presentation/`
  - `src/web/web_server.py` $\rightarrow$ `src/web/server.py`
  - `tests/gateway/` $\rightarrow$ `tests/web/gateway/`, `tests/presentation/` $\rightarrow$ `tests/web/presentation/`
- [x] **インテリジェンス・ETL パイプライン層 (`src/pipeline/` & `tests/pipeline/`)**:
  - `src/fetcher/` $\rightarrow$ `src/pipeline/` (ingestion, transformer, reporter, theme, adapters)
  - `tests/fetcher/` $\rightarrow$ `tests/pipeline/`
- [x] **レガシー互換レイヤー (`src/compat/`)**:
  - `src/compat/` へのシム隔離とルート直下の整理
- [x] **プロジェクト全体インポート & Makefile / ドキュメント同期**:
  - `src/__init__.py` のエクスポート整理
  - Makefile、pyproject.toml、関連ドキュメントのパス更新
- [x] **テスト & 品質管理ゲート**:
  - `make check_format` 0 エラー (PASS)
  - `make static_analysis` (radon, xenon, mypy --strict) 100% PASS
  - `make test` 全テストケース 100% PASS (345/345 passed, coverage 82.19%)
