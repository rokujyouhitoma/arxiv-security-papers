# Issue 151: ドメイン層（src/domain/security/）へのCTI・Taxonomy知識体系の再配置とセキュリティ基盤（src/security/）の責務分離

- ID: 151
- 種別: Refactor / Architecture
- 優先度: High
- ステータス: Closed
- ブランチ: refactor/151-reorganize-domain-security-cti-taxonomy-boundaries

## 1. 概要 (Overview)

`src/security/` 配下に配置されていた MITRE ATT&CK CTI (`src/security/cti/`) およびセキュリティ分類体系 (`src/security/taxonomy/`) は、システムの保護機構（認可、ASTサンドボックス、改ざん検知等）ではなく、本システム（arXiv Security Papers）が取り扱う業務ドメインの知識体系（Domain Knowledge / Domain Taxonomy）である。

Issue 105 で確立されたドメイン層と再利用可能基盤層のレイヤー分離の設計原則に基づき、コード実体を `src/domain/security/` 配下に再配置した。同時に、既存の全参照元への影響をゼロに保つため、`src/security/` 側には完全透過な後方互換性 Shim（再エクスポート）を配置した。

---

## 2. 達成目標と受け入れ基準 (Definition of Done: DoD)

- [x] **1. ドメイン層への実体移行 (`src/domain/security/`)**:
  - `src/domain/security/cti/`: `__init__.py`, `sync.py`, `parser.py`, `storage.py`, `registry.py` を移行。
  - `src/domain/security/taxonomy/`: `__init__.py`, `cwe.py`, `mitre.py`, `stride.py` を移行。
  - `storage.py` 内の `DEFAULT_DB_PATH` を 4 階層親 (`outputs/database/catalog/cti_catalog.db`) に適合。
- [x] **2. 完全後方互換性 Shim の提供 (`src/security/`)**:
  - `src/security/cti/` および `src/security/taxonomy/` 配下に、`domain.security` からインポート・再エクスポートする Shim を配置。
  - 既存の全モジュールからの `from security.cti import ...` および `from security.taxonomy import ...` が一切警告・エラーなく動作すること。
- [x] **3. ドメインプラグインとの統合**:
  - `src/domain/security/plugin.py` および `src/domain/security/__init__.py` から CTI Registry や Taxonomy へのアクセサを提供。
- [x] **4. 品質ゲートの完全通過**:
  - `make xenon` (Rank A 100%)。
  - `make mypy` (`--strict src` 0 errors)。
  - `make check_format flake8` (0 errors)。
  - 全単体・結合テストが 100% PASS すること (194 tests passed)。

---

## 3. 対象ファイル (Target Files)

- `[NEW] src/domain/security/cti/__init__.py`
- `[NEW] src/domain/security/cti/sync.py`
- `[NEW] src/domain/security/cti/parser.py`
- `[NEW] src/domain/security/cti/storage.py`
- `[NEW] src/domain/security/cti/registry.py`
- `[NEW] src/domain/security/taxonomy/__init__.py`
- `[NEW] src/domain/security/taxonomy/cwe.py`
- `[NEW] src/domain/security/taxonomy/mitre.py`
- `[NEW] src/domain/security/taxonomy/stride.py`
- `[MODIFY] src/domain/security/__init__.py`
- `[MODIFY] src/domain/security/plugin.py`
- `[MODIFY] src/security/cti/__init__.py`
- `[MODIFY] src/security/cti/sync.py`
- `[MODIFY] src/security/cti/parser.py`
- `[MODIFY] src/security/cti/storage.py`
- `[MODIFY] src/security/cti/registry.py`
- `[MODIFY] src/security/taxonomy/__init__.py`
- `[MODIFY] src/security/taxonomy/cwe.py`
- `[MODIFY] src/security/taxonomy/mitre.py`
- `[MODIFY] src/security/taxonomy/stride.py`
- `[NEW] tests/domain/test_domain_security_cti_taxonomy.py`
