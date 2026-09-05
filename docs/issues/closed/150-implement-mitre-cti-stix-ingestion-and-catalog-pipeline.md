# Issue 150: MITRE ATT&CK CTI (STIX 2.0/2.1) 定義取り込み・SQLiteカタログ基盤および抽出・オントロジー連携の実装

- ID: 150
- 種別: Feature / Architecture
- 優先度: High
- ステータス: Closed
- 完了日: 2026-09-05

## 1. 概要 (Overview)

公式リポジトリ [mitre/cti (https://github.com/mitre/cti)](https://github.com/mitre/cti) が提供する MITRE ATT&CK® および CAPEC™ のサイバー脅威インテリジェンス（CTI）定義（STIX 2.0 / STIX 2.1 形式）を、Python 標準ライブラリのみ（Zero External Runtime Dependencies）で安全にフェッチ・パースし、ローカル SQLite カタログ (`cti_catalog.db`) に格納・インデックス化（FTS5 全文検索）するインジェストパイプラインを実装する。

さらに、取り込んだ 700+ 件の ATT&CK テクニック、戦術 (Tactics)、緩和策 (Mitigations)、および関連性 (Relationships) を、既存の論文 Technique 抽出 (`ate.py` / `taxonomy/mitre.py`)、オントロジーシード (`seeder.py`)、および Threat Defense MCP (`threat_defense_server.py`) とシームレスに連携させる。

---

## 2. 達成目標と受け入れ基準 (Definition of Done: DoD)

- [x] **1. Zero External Dependencies & No Ignore**:
  - `stix2` 等の外部 pip パッケージを追加せず、Python 標準ライブラリ (`urllib.request`, `json`, `sqlite3`, `dataclasses`) のみで実装されていること。
  - `# noqa: E402` を含む linter ignore コメントを一切追加・使用しないこと。
- [x] **2. CTI Ingestion Pipeline (`src/security/cti/`)**:
  - `sync.py`: GitHub Raw から `enterprise-attack.json` を安全にストリーミングダウンロード・一時ファイル検証（ETag / If-Modified-Since 対応）。
  - `parser.py`: STIX 2.0 / 2.1 JSON Bundle から `attack-pattern`, `course-of-action`, `x-mitre-tactic`, `relationship` (subtechnique-of, mitigates) を抽出・バリデーション。
  - `storage.py`: SQLite (`src/database` または標準 `sqlite3`) を用いた `cti_tactics`, `cti_techniques`, `cti_mitigations`, `cti_relationships`, および `cti_techniques_fts` (FTS5) テーブルの生成とアトミック投入。
  - `registry.py`: `MITRECTIRegistry` による O(1) キャッシュ、ID/Tactics/FTS5 検索、および未同期時の組み込みコアデータへの自動フォールバック。
- [x] **3. 既存システムとの連携**:
  - `src/security/taxonomy/mitre.py`: `MITRE_TECHNIQUES_MAP` と `MITRECTIRegistry` の統合。
  - `src/ontology/primus/ate.py`: CTI 全件とのキーワード・FTS5 照合による論文 Technique 抽出の強化。
  - `src/ontology/seeder.py`: `seed_ontology_from_cti(graph_engine)` の追加。
  - `src/mcp/threat_defense_server.py`: 全 14 Tactics のカバレッジ診断および Playbook 生成の強化。
- [x] **4. CLI / Makefile 統合**:
  - `make sync_cti` コマンドでワンタッチ実行・同期可能であること。
- [x] **5. 品質ゲート完全通過**:
  - `make check_format` (flake8, black) エラー 0 件。
  - `make static_analysis` (mypy --strict, radon, xenon Rank A) エラー 0 件。
  - 単体テスト (`tests/security/test_cti_*.py`) が 100% PASS すること。

---

## 3. 対象ファイル (Target Files)

- `[NEW] src/security/cti/__init__.py`
- `[NEW] src/security/cti/sync.py`
- `[NEW] src/security/cti/parser.py`
- `[NEW] src/security/cti/storage.py`
- `[NEW] src/security/cti/registry.py`
- `[NEW] tests/security/test_cti_ingestion.py`
- `[MODIFY] src/security/taxonomy/mitre.py`
- `[MODIFY] src/ontology/seeder.py`
- `[MODIFY] src/mcp/threat_defense_server.py`
- `[MODIFY] Makefile`
- `[MODIFY] docs/issues/README.md`
