---
ID: 366
種別: Refactor
優先度: Medium
ステータス: Open (In Progress)
---

# [REFACTOR] ルート `config.json` の `config/` ディレクトリ配下への集約および設定ロード体系の統一 (ID: 366)

## 1. 概要 / Summary

プロジェクトの設定ファイル体系において、パイプラインの主要設定である `config.json` がリポジトリのルート直下に単独で配置されている一方、Supervisor 関連の設定は `config/supervisor.json` やサンプル設定が `config/` ディレクトリ配下に配置されており、設定の管理場所が分散・非対称になっている。

本 Issue では、ルートの `config.json` を `config/pipeline.json`（または `config/default.json`）として `config/` ディレクトリ配下に統合・集約し、設定ローダー側で `config/` 配下を一元的に参照する標準的な構成にリファクタリングする。

---

## 2. トレーサビリティ / Traceability

- 関連 Issue: [Issue 361: レガシー重複台帳 processed_papers.json の完全廃止](closed/361-deprecate-and-purge-legacy-processed-papers-json.md)
- 関連設定: `config.json`, `config/supervisor.json`
- 関連コード: `src/settings.py`, `src/pipeline/arxiv_okf_fetcher.py`

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files

### 設定ファイル
- [ ] `config.json` (移動・削除)
- [ ] `config/pipeline.json` (新規配置・移行)

### パイプライン・コア設定ローダー
- [ ] `src/settings.py`
- [ ] `src/pipeline/arxiv_okf_fetcher.py`
- [ ] `Makefile` (引数指定箇所の同期)
- [ ] `manage.py`

### テストスイート
- [ ] `tests/test_settings_timezone.py`
- [ ] `tests/pipeline/` 配下の設定読み込みテスト

---

## 4. 実装方針 / Implementation Plan

Target Branch: `refactor/366-unify-config-files`

1. **設定ローダーの探索パス拡張**:
   - 設定読み込み処理において、`config/pipeline.json` を第一優先とし、存在しない場合のフォールバックとしてルートの `config.json` を参照する互換ロジックを実装。
2. **ファイルの移動と配置**:
   - `git mv config.json config/pipeline.json` を実行。
3. **Makefile および CLI コマンドの更新**:
   - `Makefile`、`manage.py`、および関連スクリプト内で `--config config.json` と直指定されている箇所を `--config config/pipeline.json` へ同期。
4. **テストの更新と実行**:
   - 設定ファイルを指定・読み込む全ユニットテストを新パスに同期し、実行。
5. **品質ゲートの検証**:
   - `make check_format`
   - `make static_analysis`
   - `make test`

---

## 5. 完了条件 / Success Criteria (DoD)

- [ ] リポジトリルートから `config.json` が解消され、`config/` ディレクトリ配下に集約されていること。
- [ ] パイプライン実行（`make run` や各種 CLI）が `config/pipeline.json` を正常にロードできること。
- [ ] 全ユニットテストが 100% PASS すること。
