# Issue 台帳 (Issue Ledger)

本ドキュメントは、`arxiv-security-papers` プロジェクトにおけるタスク、新機能開発、リファクタリング、および障害修正の全 Issue 台帳です。

---

## 1. アクティブ Issue 一覧 (Active Issues)

| Issue ID | タイトル | 種別 | 優先度 | ステータス | 詳細リンク |
| :---: | --- | :---: | :---: | :---: | :---: |
| **075** | Unix Domain Socket による DB・Web・Search の完全プロセス分離と IPC ラッパー基盤の実装 | Feature / Refactor | High | New | [075-implement-unix-domain-socket-ipc-wrapper-for-db-web-search.md](075-implement-unix-domain-socket-ipc-wrapper-for-db-web-search.md) |
| **076** | Supervisor のドメイン非依存・汎用プロセスエンジン化と宣言的 Worker/Service 抽象化 | Feature / Refactor | High | New | [076-decouple-domain-workers-from-supervisor-generic-engine.md](076-decouple-domain-workers-from-supervisor-generic-engine.md) |

---

## 2. 完了・クローズ済み Issue 一覧 (Closed Issues)

| Issue ID | タイトル | 種別 | 完了日 | 詳細リンク |
| :---: | --- | :---: | :---: | :---: |
| **074** | アイドル状態継続後のワーカー誤判定・ヘルスチェック誤表示およびゾンビプロセス回収不備の根絶 | Bug / Refactor | 2026-08-26 | [074-fix-idle-worker-death-and-zombie-reaping.md](closed/074-fix-idle-worker-death-and-zombie-reaping.md) |
| **073** | Web と Search Engine のプロセス分離・独立ワーカー化によるメモリ肥大化（15 GB → 1.6 GB）の根絶 | Bug / Refactor | 2026-08-26 | [073-fix-worker-rss-memory-bloat-on-startup.md](closed/073-fix-worker-rss-memory-bloat-on-startup.md) |
| **072** | `scale` コマンド実行時に DB ワーカーが巻き添えで停止・消滅する問題の修正および Web/DB プール分離管理 | Bug | 2026-08-26 | [072-fix-scale-command-kills-db-worker.md](closed/072-fix-scale-command-kills-db-worker.md) |
| **071** | Arbiter（親プロセス）の突然死・クラッシュおよび予期しない PID 変化の修正 | Bug | 2026-08-26 | [071-fix-arbiter-crash-and-unexpected-restart.md](closed/071-fix-arbiter-crash-and-unexpected-restart.md) |
| **070** | Supervisor CLI top リアルタイムモニタリング機能の実装 | Feature | 2026-08-23 | [070-implement-supervisor-cli-top-monitoring.md](closed/070-implement-supervisor-cli-top-monitoring.md) |
| **069** | Gunicorn スタイル Pre-fork プロセススーパーバイザー & 調停基盤 (src/supervisor/) の実装 | Feature | 2026-08-23 | [069-implement-gunicorn-style-process-supervisor-and-arbiter.md](closed/069-implement-gunicorn-style-process-supervisor-and-arbiter.md) |
| **068** | 検索インデックス生成 (14,349件) および VectorEngine CLI・ハンドラ自動ロード改修 | Bugfix / Ops | 2026-08-22 | [068-build-search-vector-index-and-fix-cli-entrypoints.md](closed/068-build-search-vector-index-and-fix-cli-entrypoints.md) |
| **067** | IACR ePrint 空URLハンドリング修正および TLS/SSL 証明書検証フォールバックの実装 | Bugfix | 2026-08-22 | [067-fix-iacr-feed-url-and-tls-cert-verification.md](closed/067-fix-iacr-feed-url-and-tls-cert-verification.md) |
| **066** | 普遍的自律型インテリジェンス・オーケストレーションエンジン (src/orchestrator/) の完全実装 | Feature | 2026-08-22 | [066-implement-universal-intelligence-orchestrator.md](closed/066-implement-universal-intelligence-orchestrator.md) |
| **065** | 全体高位アーキテクチャ設計書 (DSN-01) および README.md へのインテリジェンス・オーケストレーション (DSN-11) の完全反映 | Docs / Arch | 2026-08-22 | [065-integrate-dsn-11-into-dsn-01-hld.md](closed/065-integrate-dsn-11-into-dsn-01-hld.md) |
| **064** | 汎用・ドメイン非依存インテリジェンス・オーケストレーション包括設計書 (DSN-11) への高抽象度化 | Feature / Docs | 2026-08-22 | [064-generalize-intelligence-orchestration-architecture.md](closed/064-generalize-intelligence-orchestration-architecture.md) |
| **063** | 自律型インテリジェンス・オーケストレーションエンジン設計書 (DSN-11) の策定 | Feature / Docs | 2026-08-22 | [063-design-intelligence-orchestration-engine.md](closed/063-design-intelligence-orchestration-engine.md) |
| **062** | 設計書体系 (docs/designs/*.md) の包括的リファクタリングと DSN-14 形式統一 (1:1 パッケージ対応) | Docs / Arch | 2026-08-22 | [062-reorganize-and-standardize-design-docs.md](closed/062-reorganize-and-standardize-design-docs.md) |
| **061** | 2層分離検索アーキテクチャ (Engine & Platform) の実装と機能完備 | Refactor | 2026-08-22 | [061-search-engine-and-platform-modular-architecture.md](closed/061-search-engine-and-platform-modular-architecture.md) |
| **060** | 後方互換性機能・シム・レガシーエイリアスの完全削除 | Refactor | 2026-08-22 | [060-remove-legacy-backward-compatibility.md](closed/060-remove-legacy-backward-compatibility.md) |
| **059** | クリーンアーキテクチャに基づく src/ および tests/ パッケージ再設計・リファクタリング | Refactor | 2026-08-21 | [059-clean-architecture-package-refactoring.md](closed/059-clean-architecture-package-refactoring.md) |
| **058** | [ゼロ外部依存・大規模分散Webクローラー・スパイダー基盤（DSN-15 準拠）の実装](closed/058-implement-distributed-spider-and-crawler-platform.md) | Feature | 2026-08-21 | [058-implement-distributed-spider-and-crawler-platform.md](closed/058-implement-distributed-spider-and-crawler-platform.md) |
| **057** | [マルチソース・マルチテーマ対応インテリジェンスプラットフォーム基盤（Pluggable Source Adapters & Theme-Aware Pipeline）の実装](closed/057-implement-pluggable-source-adapters-and-multi-theme-pipeline.md) | Feature | 2026-08-21 | [057-implement-pluggable-source-adapters-and-multi-theme-pipeline.md](closed/057-implement-pluggable-source-adapters-and-multi-theme-pipeline.md) |
| **056** | [SQLite 互換 DB 包括的検証テストスイート & 次世代 DB エンジン E2E シナリオ（US-01 〜 US-12 & DSN-14 シナリオ 1〜7）の拡充](closed/056-expand-sqlite-compatibility-test-suite.md) | Test | 2026-08-20 | [056-expand-sqlite-compatibility-test-suite.md](closed/056-expand-sqlite-compatibility-test-suite.md) |
| **055** | [tests/database/ ディレクトリ階層の src/database/ 同一構造化](closed/055-restructure-database-test-directory-hierarchy.md) | Refactor | 2026-08-20 | [055-restructure-database-test-directory-hierarchy.md](closed/055-restructure-database-test-directory-hierarchy.md) |
| **054** | [コンシステントハッシュ（Consistent Hashing）& 仮想ノード（Virtual Nodes）分散シャーディングの実装](closed/054-implement-consistent-hashing-and-sharding.md) | Feature | 2026-08-20 | [054-implement-consistent-hashing-and-sharding.md](closed/054-implement-consistent-hashing-and-sharding.md) |
| **053** | [2PC（2相コミット）分散トランザクション調整基盤の実装](closed/053-implement-2pc-distributed-transactions.md) | Feature | 2026-08-20 | [053-implement-2pc-distributed-transactions.md](closed/053-implement-2pc-distributed-transactions.md) |
| **052** | [Saga パターン分散トランザクション（補償トランザクション・オーケストレーション）の実装](closed/052-implement-saga-distributed-transactions.md) | Feature | 2026-08-20 | [052-implement-saga-distributed-transactions.md](closed/052-implement-saga-distributed-transactions.md) |
| **051** | [Raft 分散合意アルゴリズム基盤の実装](closed/051-implement-raft-consensus-algorithm.md) | Feature | 2026-08-20 | [051-implement-raft-consensus-algorithm.md](closed/051-implement-raft-consensus-algorithm.md) |
| **050** | [Phi Accrual 確率的障害検出器 & Gossip プロトコル基盤の実装](closed/050-implement-phi-accrual-and-gossip-protocol.md) | Feature | 2026-08-20 | [050-implement-phi-accrual-and-gossip-protocol.md](closed/050-implement-phi-accrual-and-gossip-protocol.md) |
| **049** | [Bully アルゴリズム & リングリーダー選出基盤の実装](closed/049-implement-bully-and-ring-leader-election.md) | Feature | 2026-08-20 | [049-implement-bully-and-ring-leader-election.md](closed/049-implement-bully-and-ring-leader-election.md) |
| **048** | [バージョンベクトル・CRDT・Merkle ツリーアンチエントロピー基盤の実装](closed/048-implement-version-vectors-crdt-and-merkle-anti-entropy.md) | Feature | 2026-08-20 | [048-implement-version-vectors-crdt-and-merkle-anti-entropy.md](closed/048-implement-version-vectors-crdt-and-merkle-anti-entropy.md) |
| **047** | [論理クロック（Lamport / Vector）および一貫性モデル基盤の実装](closed/047-implement-logical-clocks-and-consistency-models.md) | Feature | 2026-08-20 | [047-implement-logical-clocks-and-consistency-models.md](closed/047-implement-logical-clocks-and-consistency-models.md) |
| **046** | [LSM-Tree ストレージエンジン（MemTable・SSTable・Bloom Filter・コンパクション）の実装](closed/046-implement-lsm-tree-storage-engine.md) | Feature | 2026-08-20 | [046-implement-lsm-tree-storage-engine.md](closed/046-implement-lsm-tree-storage-engine.md) |
| **045** | [CoW（コピーオンライト）B-Tree & LMDB 型シャドウページングエンジンの実装](closed/045-implement-cow-btree-storage-engine.md) | Feature | 2026-08-20 | [045-implement-cow-btree-storage-engine.md](closed/045-implement-cow-btree-storage-engine.md) |
| **044** | [PAX（Partition Attributes Across）ハイブリッド列指向ストレージエンジンの実装](closed/044-implement-pax-hybrid-columnar-storage-engine.md) | Feature | 2026-08-20 | [044-implement-pax-hybrid-columnar-storage-engine.md](closed/044-implement-pax-hybrid-columnar-storage-engine.md) |
| **043** | [ARIES クラッシュリカバリ・先行書き込みログ（WAL）およびファジーチェックポイントの実装](closed/043-implement-aries-crash-recovery-and-wal.md) | Feature | 2026-08-20 | [043-implement-aries-crash-recovery-and-wal.md](closed/043-implement-aries-crash-recovery-and-wal.md) |
| **042** | [4KB スロッテッドページ・B+Tree・2Q バッファプールのゼロ外部依存実装](closed/042-implement-slotted-page-btree-and-buffer-pool.md) | Feature | 2026-08-20 | [042-implement-slotted-page-btree-and-buffer-pool.md](closed/042-implement-slotted-page-btree-and-buffer-pool.md) |
| **041** | [ゼロ外部依存 純粋 Python SQLite 互換 & 分散ベクトルデータベース基盤（DSN-14 準拠）の包括的実装](closed/041-implement-pure-python-sqlite-and-distributed-vector-db.md) | Feature | 2026-08-20 | [041-implement-pure-python-sqlite-and-distributed-vector-db.md](closed/041-implement-pure-python-sqlite-and-distributed-vector-db.md) |
| **040** | [次世代データベースエンジン（src/database/）包括的アーキテクチャ設計書（DSN-14）の策定](closed/040-design-next-gen-database-engine-architecture.md) | Docs / Arch | 2026-08-20 | [040-design-next-gen-database-engine-architecture.md](closed/040-design-next-gen-database-engine-architecture.md) |
| **039** | [全13大専門エージェントの合意に基づく最先端機能設計書（DSN-08〜DSN-13）の策定](closed/039-formulate-cutting-edge-design-specifications.md) | Docs / Arch | 2026-08-20 | [039-formulate-cutting-edge-design-specifications.md](closed/039-formulate-cutting-edge-design-specifications.md) |
