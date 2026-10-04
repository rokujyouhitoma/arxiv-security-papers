---
ID: 447
種別: Refactoring
優先度: High
ステータス: Closed
---

# [REFACTOR] トップレベルディレクトリの徹底的構造集約とサブシステム統合 (ID: 447)

## 1. 概要 / Summary
`ilisp` の本格実装開始を前に、トップレベルに散在していた補助ディレクトリ群を体系的に整理・集約し、プロジェクトの境界と構造を極限まで美しく整流化した。
具体的には、【方針 B: 徹底的構造集約】に基づき、トップレベルの補助ディレクトリ（`data/`, `migrations/`, `templates/`, `grammars/`, `site/`）をそれぞれの担当サブシステム（`src/database/`, `src/pipeline/`, `tools/`, `src/web/`）へ統合・集約し、トップレベルの非 dot ディレクトリを主要コア群（`src/`, `ilisp/`, `tests/`, `docs/`, `outputs/`, `tools/`, `scripts/`, `config/`）の 8 大ディレクトリに整流化した。

---

## 2. 影響範囲と関連ファイル / Scope and Affected Files
- [x] `data/` -> `.gitignore` への追加および廃止
- [x] `migrations/` -> `src/database/migrations/sql/` への集約
- [x] `templates/` -> `src/pipeline/templates/` への集約
- [x] `grammars/` -> `tools/grammars/` への集約
- [x] `site/` -> `src/web/site/` への集約
- [x] `Makefile` (JS ビルド、PEG コンパイル、クリーンターゲット等)
- [x] `src/` (パス参照箇所: `MigrationManager`, `okf_serializer.py`, `handlers.py`, `server.py`, `storage.py` 等)
- [x] `tests/` (移動先パスへのアサーション同期: `tests/web/`, `tests/core/peg/`, `tests/test_database_migrations_*.py`)
- [x] `docs/issues/README.md`
- [x] `README.md`

---

## 3. 実装方針 / Implementation Plan
Target Branch: `refactor/447-refactor-root-directory-structure-subsystem-consolidation`

1. **事前参照調査 (Grep Analysis)**:
   - `data/`, `migrations/`, `templates/`, `grammars/`, `site/` をハードコード参照しているファイル（`src/`, `tests/`, `Makefile`, `scripts/`）を網羅的に特定。
2. **ディレクトリ移動・統合**:
   - `templates/` -> `src/pipeline/templates/`
   - `migrations/` -> `src/database/migrations/sql/`
   - `grammars/` -> `tools/grammars/`
   - `site/` -> `src/web/site/`
   - `data/` を `.gitignore` に登録してリポジトリルートを清掃。
3. **パス参照の更新**:
   - `src/pipeline/transformer/okf_serializer.py` のデフォルトテンプレートパス。
   - `src/web/` の静的アセットサービングパス（`src/web/site/`）。
   - `Makefile` 内の PEG コンパイルコマンド、フロントエンドビルドコマンド、クリーンターゲット。
   - `tools/peg/` 内の文法ファイル参照パス。
4. **テスト・品質検証**:
   - `make check_format` (100% PASS)
   - `make py_compile` (100% PASS)
   - `make test` (全テストスイート PASS)
   - `make static_analysis` (radon, xenon, mypy strict 100% PASS)
   - 相対パスリンクガバナンスの検証。
5. **ドキュメント・README同期**:
   - `README.md` のディレクトリ構造マップを最新の整流化構造に更新。

---

## 4. 完了条件 / Success Criteria (DoD)
- [x] `data/`, `migrations/`, `templates/`, `grammars/`, `site/` がトップレベルから移動・集約されていること
- [x] `src/pipeline/templates/` から Markdown テンプレートが正常にロードされること
- [x] `tools/grammars/` から PEG 文法が正常に読み込まれ、ビルドできること
- [x] `src/web/site/` から Web UI アセットが正常に配信できること
- [x] `make test` (pytest) が 100% PASS すること
- [x] `make check_format` および `make static_analysis` が 100% PASS すること
- [x] `README.md` の構成図が新構造と完全一致していること
