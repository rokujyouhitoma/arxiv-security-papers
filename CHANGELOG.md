# Changelog

本ドキュメントは、「`arxiv-security-papers`」のファーストコミットから現在に至るすべての注目すべき変更・設計進化・マイルストーンの全軌跡を記録します。

フォーマットは [Keep a Changelog](https://keepachangelog.com/ja/1.1.0/) に基づき、
バージョニングは [Semantic Versioning](https://semver.org/lang/ja/) （メジャー.マイナー.パッチ）に準拠します。

---

## バージョニングポリシー

| バージョン種別 | 変更内容 |
| :--- | :--- |
| **メジャー** (`X.0.0`) | 後方互換性のない大規模な変更（アーキテクチャ全面改修、オントロジーメタモデル導入、データ形式刷新等） |
| **マイナー** (`0.X.0` / `X.Y.0`) | 後方互換性のある新機能の追加（新Spider追加、ストレージエンジン拡張、自律オーケストレーター導入等） |
| **パッチ** (`0.0.X` / `X.Y.Z`) | 後方互換性のあるバグ修正・小改善（キャッシュ最適化、型安全性向上、ドキュメント更新等） |

### 変更カテゴリ

- `[Added]` — 新機能の追加
- `[Changed]` — 既存機能の変更・アーキテクチャ刷新
- `[Deprecated]` — 将来削除予定の機能の案内
- `[Removed]` — 機能の削除・レガシーコードの完全撤廃
- `[Fixed]` — バグ修正・障害対策
- `[Security]` — セキュリティ要件・多層防御・耐障害性の強化
- `[Docs]` — 設計書・台帳・ドキュメントの追加・更新

---

## [Unreleased]

### [Planned]
- **Issue 210**: `src/spider/` からのセキュリティ・OKF ドメインロジック完全分離と純粋クローラー基盤化

---

## [1.1.0] - 2026-09-07

### [Added]
- **外部脅威インテリジェンス（CTI）Pure-Python Spider 群の実装 (Issue 205)**:
  - `CisaKevSpider` (`src/domain/security/spiders/cisa_kev_spider.py`): 米 CISA KEV JSON フィード（`known_exploited_vulnerabilities.json`）専用スパイダー。公式規約遵守の `download_delay = 5.0s`、SSRF 防止のドメインホワイトリスト（`{"cisa.gov", "www.cisa.gov"}`）、およびランサムウェア（`knownRansomwareCampaignUse`）自動タグ付与を実装。
  - `NvdCveSpider` (`src/domain/security/spiders/nvd_cve_spider.py`): 米 NIST NVD REST API 2.0 専用スパイダー。動的レートリミット制御（APIキーなし時 6.5s、あり時 0.8s）、CVSS v3.1/v3.0/v2.0 優先抽出、CWE 分類、CPE 2.3 基準ベンダー・製品抽出、および `resultsPerPage=2000` 再帰的ページネーションを実装。
  - `src/spider/registry.py`: SPI 経由のドメインスパイダー動的自動登録機構（`auto_discover=True`）。
  - `src/domain/security/plugin.py`: `get_spiders()` に CISA KEV / NVD CVE を統合。
  - `src/pipeline/ingestion/adapters/registry.py`: `spider_cisa_kev`, `spider_nvd_cve` インジェストアダプターを登録。
  - `src/spider/spiders/`: 後方互換性リバースエクスポートシムを配置。
- **RFC 7232 条件付き GET & HTTP 304 キャッシュ透過処理 (Issue 209)**:
  - `src/spider/downloader/middleware.py`: `HttpCacheMiddleware` を拡張し、`If-None-Match` (ETag) および `If-Modified-Since` 条件付きリクエストヘッダーを自動注入。リモート 304 受信時にキャッシュ済みボディを取り出し、`meta={'validated_304': True, 'cached': True}` を付与した透過 200 レスポンスを合成。
  - `src/spider/core/downloader.py`: RFC 7230 Section 3.3.2 準拠の `_should_have_body` を実装し、304/204/1xx 応答時のソケット読み込みハングを恒久防止。
  - CWE-113 CRLF インジェクション対策として `_sanitize_header_value` を導入。
- **脆弱性・CTI 多態的 OKF Item Pipeline (Issue 208)**:
  - `src/spider/pipeline/okf_pipeline.py`: `ScrapedItem.payload["type"]` による動的ディスパッチ（`paper`, `vulnerability`, `security_advisory`）を実装。
  - CVE CVSS スコア・重要度・CWE・影響製品・悪用状態（KEV status）を Google OKF v0.2 Markdown フロントマターおよび本文テーブルへ多態的自動展開。
  - 自作データベース `cti_catalog.db` への非同期永続化（`vulnerabilities`, `cve_metadata` テーブル）を統合。
  - CWE-22 パストラバーサル防御 (`_sanitize_path_id`) を完備。
- **HTTP 429/503 指数バックオフ再試行 & SSRF ドメイン防御ミドルウェア (Issue 207)**:
  - `RetryMiddleware`: HTTP 429 (Too Many Requests), 503 (Service Unavailable) 検出時に `Retry-After` ヘッダー（秒数 / RFC 7231 日時）を解析し、ジッター付き指数バックオフ（初期 1.0s, 最大 60.0s, 最大 3 回）による自律再試行ループを実装。
  - `OffsiteMiddleware`: Spider 定義の `allowed_domains` によるリクエスト宛先ホワイトリスト検証。プライベート IP (RFC 1918)、ループバック、およびクラウドメタデータ IP (`169.254.169.254`) への SSRF 通信を事前完全遮断。
- **Response.json() プロパティ追加 & Spider 遅延伝搬機構 (Issue 206)**:
  - `src/spider/core/downloader.py`: `Response.json()` ヘルパーメソッドおよび `Request.params` クエリ文字列自動エンコード機構を実装。
  - `src/spider/runner.py`: Spider クラスの `download_delay` 宣言をダウンローダーの `Scheduler` および `AutoThrottle` へ動的注入する伝搬パイプラインを確立。

### [Docs]
- `docs/designs/DSN-06-distributed_spider_and_crawler.md`: Section 1.1.5, 2.4.4, 4.3, Phase 5 に CISA KEV / NVD CVE Spider、条件付き GET / 304 キャッシュ、再帰ページネーション、および多態的 OKF パイプライン仕様を反映。

---

## [1.0.0] - 2026-09-06

### [Added]
- **全領域統合セキュリティ知識オントロジー (Full-Spectrum SKO) (Issue 178, 179, 180)**:
  - 形式オントロジー言語（OWL 2 DL 準拠）による実脅威・攻撃連鎖・防御コード・前提条件・研究ギャップの包括的メタモデル（TBox/ABox）を策定。
  - Pure-Python Turtle (`.ttl`) 生成エンジンおよびオントロジー宣言 DSL、AST インタプリタ実行エンジンを分離実装。
- **Schema View エクスプローラー & グラフ UI/UX 刷新 (Issue 181, 182, 183, 187, 190, 191, 192)**:
  - `/dashboard?tab=graph` におけるスキーマ・エクスプローラー（Schema View）の新規実装。
  - 二次ベジェ曲線・有向矢印による双方向エッジ重なり解消、CSS カラーバッジ統一、CTI フィルタ（Entity Type / Relation Type）複数同時選択（マルチセレクト）対応。
  - ノード密集を解消する動的斥力・ばね長物理スケーリングおよび衝突回避アルゴリズムの統合。
- **脅威モデル因果連鎖・Claim / Evidence 具現化 (Issue 184, 185, 186, 188)**:
  - STRIDE 脅威モデル因果連鎖、Impact / Consequence、および前提条件無力化（Precondition Neutralization）モデルの実装。
  - 主張（Claim）と実証（Evidence）の具現化（Reification）、エッジ属性確信度、および正規表現データ制約の導入。
  - 論文 ABox グラフへの因果実体自動結合パイプラインを確立。
- **Pure-Python PDF エンジン図表抽出 & 高度ストリームデコーダ (Issue 198, 204)**:
  - PDF 論文中のアーキテクチャ図・フローチャート・評価グラフを純粋 Python のみで抽出する画像抽出基盤（SC-1〜SC-6 多層防御完備）の実装。
  - `/LZWDecode`, `/CCITTFaxDecode`, `/JBIG2Decode` 高度バイナリストリームデコーダ群を統合。
- **ベンチマーク・耐障害性・マルチデータベース統合 (Issue 193, 194, 195, 196, 197, 200, 201)**:
  - BEIR / CTI-Bench IR 評価によるハイブリッド探索（BM25+HNSW+Graph）の定量的 SOTA 性能立証基盤。
  - カオス VFS・電源断シミュレーション・ミューテーションテストによる自作 DB の ARIES クラッシュ復旧完全性証明。
  - 専用独立タブ（`tab=database`）によるマルチデータベース（cti_catalog, analytics, graph）統合インスペクション UI の実装。
  - CISA KEV / NVD CVE リアルタイム動的突合およびグラフ因果リンク拡張。
  - MCP サーバーにおけるオントロジー因果探索・エビデンス推論ツールの拡充。
  - 直近最新論文（2026-09-02〜09-07）の定期フェッチ・5層サマリー・グラフ DB 最新化。

### [Changed]
- **TBox メタモデル仕様の SSOT 一元化 (Issue 202)**:
  - オントロジー述語仕様（TBox/Domain/Range/Labels）を `src/graph/ontology/schema.py` へ SSOT 一元化し、Turtle エンジンを純粋シリアライザーへリファクタリング。
- **SOTA ベンチマークレポート指標抽出の是正 (Issue 203)**:
  - SOTA ベンチマークレポートにおける 0.0000 メトリクス出力および結論矛盾を修正。

---

## [0.9.0] - 2026-09-04

### [Added]
- **専用 Knowledge & CTI Graph 画面（`tab=graph`）の独立実装 (Issue 138, 139, 140)**:
  - `/dashboard` における専用 CTI ナレッジグラフ可視化タブの独立。
  - エッジ接続次数に応じた頂点半径スケーリング（$R \propto \sqrt{1+k}$）およびレイアウト重なり解消。
- **高度グラフ絞り込みフィルタ群の実装 (Issue 143, 144, 145, 146, 147, 148)**:
  - 孤立ノード非表示トグル、最小次数フィルタ（Min-Degree / Hub Filter）、特定ノードのエゴネットワーク抽出モード。
  - エッジ関係性（Relation Type）個別フィルタ、最大連結成分（LCC）抽出、未研究・未対策脅威（Research Gaps Only）専用フィルタの実装。
- **エッジ推論マスター（EIROM）& 確信度・エビデンス付きグラフ探索 (Issue 162, 163, 164, 165)**:
  - Vertex 紐付け推論判定ルール（Edge Inference Rule Ontology Master）のマスターデータ化。
  - 確信度（Confidence Tier: HIGH / MEDIUM / LOW）およびエビデンススニペット属性の統合付与。
  - 全量 OKF 論文アーカイブへの推論ルール適用とグラフ再構築バッチの実装。
- **STIX 2.1 CTI 推論 & ATT&CK Navigator レイヤー自動生成 (Issue 150, 160)**:
  - Pure-Python STIX 2.1 SDO/SRO 推論エンジンおよび ATT&CK Navigator レイヤー JSON 自動生成機能。
  - MITRE ATT&CK CTI 定義取り込み・カタログ SQLite 基盤の構築。
- **6大セキュリティ境界防御（Unified Security Perimeter）の実装 (Issue 154 - 159, 161)**:
  - ネットワーク隔離 & SSRF 防御（`NetworkIsolationGuard`）
  - マジックバイト検証 & Anti-Zip/XML-Bomb パーサー防護
  - エフェメラル暗号化シークレットストア & トークン漏洩ガード
  - スライディングウィンドウレートリミット & DoS サーキットブレーカー
  - HMAC 前方安全ハッシュ連鎖構造化監査ログ
  - エージェント出力ガードレール & ツール呼出 AST ホワイトリスト検証
  - 統一セキュリティ WSGI ミドルウェアの実装。
- **エンタープライズ統合デザインシステム & UI/UX 高度化 (Issue 166, 167, 169, 170, 171, 174, 175, 176)**:
  - Glassmorphic ツールチップ・操作ガイド基盤、Canvas 縦スクロール＆パン/ズーム機能。
  - 左上ピン留め凡例、ズームコントロールボタン、`index.html` と `dashboard.html` のヘッダー統一・画面統合。

### [Fixed]
- **Web サーバーブロッキング・SSE 枯渇障害の解消 (Issue 141, 168, 172)**:
  - `/dashboard` 連打リロード時および SSE ストリーミング接続継続時の Web ワーカー枯渇・ハングアップを解消。
  - `dashboard.html` 内の不要な SSE 接続を撤廃し、ThreadingWSGIServer の非ブロッキング性を確立。
- **グラフクエリのサブグラフ消失バグ修正 (Issue 142, 173)**:
  - 背景同期（Live Mesh Sync）によるクエリ結果リセットを防止し、1-Hop 隣接インシデントエッジの自動展開を実装。
- **マルチソースプレフィックス誤表記の解消 (Issue 177)**:
  - IACR ePrint 論文に対する「arXiv:」プレフィックス誤表記を解消し、動的リンク解決を整備。

---

## [0.8.0] - 2026-08-28

### [Added]
- **高度 SQL サポート & グラフ DB・GraphRAG 完全統合 (Issue 100, 101, 129)**:
  - 自作 DB における JOIN、再帰 CTE（`WITH RECURSIVE`）、JSON 演算子、テーブルエイリアスの完全サポート。
  - 論文パイプラインとグラフ DB・GraphRAG 因果チェーン API の統合。
  - 論文引用ネットワーク（Citation PageRank）と CTI ナレッジグラフを融合したマルチホップ GraphRAG パイプライン。
- **高密度ベクトル ANN 探索エンジン & ハイブリッドリランカー (Issue 123, 124, 125)**:
  - `mmap` / `struct` 駆動 Pure-Python IVF-PQ（転置インデックス積量子化）ANN エンジン。
  - BM25 語彙検索と Dense ANN 探索を統合する相互順位融合（RRF: Reciprocal Rank Fusion）ハイブリッドスコアラー。
  - Late-Interaction（MaxSim）演算機構および SPLADE 風疎表現ターム拡張リランカー。
- **スロットページ & LSM-Tree ストレージ基盤 (Issue 126, 149)**:
  - 固定長 4KB バイナリスロットページ構造と MemTable / WAL / SSTable / Bloom Filter ストレージ。
  - `analytics.db` 等の全 SQLite 利用箇所の `src/database/` 統合。
- **MITRE ATT&CK / CWE ナレッジグラフデータ基盤 (Issue 135, 136, 137)**:
  - arXiv 論文・MITRE ATT&CK・CWE ナレッジグラフおよび `/dashboard` インタラクティブ可視化。
  - Context Mesh におけるエンティティ名寄せ（Entity Resolution）・重複排除（Deduplication）。
  - `/dashboard` Product タブにおける CTI グラフクエリ・コンソール。
- **自動防御シグネチャ生成 & MCP セキュリティゲートウェイ (Issue 130, 131, 132)**:
  - IaC・OpenAPI 解析と論文照合による STRIDE 脅威モデリング MCP ツール。
  - 学術知見からの Semgrep / Sigma / YARA ルール自動生成とインメモリ AST バリデータ。
  - MCP 通信におけるテイント解析・プロンプトインジェクション防御ゲートウェイ。
- **CI 検索品質回帰防止ゲート & 改ざん検知 FIM (Issue 133, 134)**:
  - IR 評価指標（NDCG@10, MRR, MAP）に基づく CI 検索品質回帰防止ゲート（劣化許容度 <= 3%）。
  - Merkle Tree（暗号論的ハッシュ木）駆動の原本・メタデータ改ざん検知（FIM: File Integrity Monitoring）基盤。
- **リアルタイムストリーミング & 分散追跡 (Issue 115, 118)**:
  - Web Gateway における Server-Sent Events (SSE) リアルタイムストリーミング API。
  - 構造化 JSON ログ基盤および W3C Trace Context 準拠 Trace ID 分散追跡。

### [Changed]
- **ドメイン層と基盤層の完全分離 (Issue 105, 151)**:
  - `src/domain/security/` へセキュリティ論文・CTI・Taxonomy ドメインを配置し、`src/database/`, `src/spider/`, `src/search/` 等の基盤層を完全ドメイン非依存化。
- **リポジトリ全体の完全型安全性確立 (Issue 119)**:
  - 全 341 モジュールに対する `mypy --strict` 適合化と型アノテーションの完全補完。
- **Xenon 循環的複雑度（CC）判定基準の最高峰厳格化 (Issue 104)**:
  - 全モジュール、全関数、平均複雑度について最高評価 Grade A (CC <= 5) を強制適用。
- **Web ワーカーのオンメモリ検索インデックス肥大化解消 (Issue 111, 121)**:
  - Web ワーカーでのオンメモリ検索インデックス直接保持を全廃し、Search ワーカー IPC 問い合わせへ完全移行（メモリ消費 15GB $\to$ 1.6GB）。

### [Fixed]
- **API 通信・パイプライン耐障害性強化 (Issue 106, 107, 108, 116)**:
  - arXiv API タイムアウト時の指数バックオフ拡張（8s/16s/32s/64s）および RSS フォールバック遷移ログの明示化。
  - パイプライン実行時の `workspace_dir` 解決不具合の修正。
  - 過去 160 日間大規模バックフィルの自律レジューム＆レートリミット制御バッチ機構の確立。
- **Supervisor プロセスリーク根絶 & メトリクス同期修正 (Issue 099, 112, 113, 114, 122)**:
  - Supervisor 多重起動防止ロック、サービス単位 Graceful Restart、稼働時間 TTL / リクエスト数制限による自律ローテーション、およびワーカーメモリ監視（Memory Watchdog）の実装。
  - プロセス間メトリクス同期による CLI `top` リクエスト件数（REQ）/ RPS 表示の修正。
- **Gateway ハードコード値の全廃 (Issue 102)**:
  - ダミーフォールバック値を全廃し、動的実測メトリクスへの完全切り替えを実施。

---

## [0.7.0] - 2026-08-27

### [Added]
- **普遍的自律型インテリジェンス・オーケストレーションエンジン (Issue 063, 064, 065, 066, 082, 091)**:
  - 汎用・閉ループ自律インテリジェンスエンジン（`src/intelligence/`）の完全実装（DSN-11 準拠）。
  - 仮説駆動型自律調査・検証ループ（Hypothesis-Driven Autonomous Investigation）。
  - 検索評価（IR Eval）駆動型クエリ自己適応ループの実装。
  - 汎用ワークフロー基盤（`src/workflow/`）とインテリジェンス層の完全分離。
- **インテリジェンス高度化サブシステム群 (Issue 085, 087, 088, 089, 090)**:
  - 3-Horizon（戦術・運用・戦略）多層 PIR 管理および動的エスカレーション基盤。
  - NATO STANAG 2022 規格準拠 Admiralty 情報源信憑性スコアリングエンジン。
  - ストリーミング型 DAG & バックプレッシャー制御パイプライン。
  - Event Sourcing 型クラッシュリカバリ WAL & 状態再生エンジン。
  - 自律型自己修復 & 動的ルート変異ハーベスター。
- **Pure-Python PDF エンジン 2カラム認識 & 記号正規化 (Issue 081, DSN-13)**:
  - ゼロ外部依存 PDF エンジンにおける 2 カラム多段組レイアウト自動認識。
  - 暗号・数式記号正規化、読書順序ソート、および行末ハイフネーション自動結合。
- **分散オブザーバビリティ & アナリティクス基盤 (Issue 094, 095, 096, 097)**:
  - ゼロ外部依存 OpenTelemetry & OpenInference 分散トレーシング基盤。
  - 事前バッチ集計アナリティクスエンジン（Pre-Aggregated Analytics Engine）。
  - 3ノード分散データベース同期クラスタ基盤の実装。
  - セキュリティ知識オントロジー（SKO）定義およびグラフデータベース基盤（Issue 098）。
- **エグゼクティブサマリー急上昇キーワードクラスタリング (Issue 084, 109)**:
  - 急上昇キーワード（Surge Keywords）時系列クラスタリンググラフおよび OKF 相互リンク。
  - NLP 重要キーワード抽出・3点構造化要約・横断的動向シンセシスの導入。
- **新興脅威対策 Semgrep パッチ合成エンジン (Issue 083)**:
  - Slopsquatting、EOP モデル汚染、多コミット型改ざんに対応した防御シグネチャ生成。

---

## [0.6.0] - 2026-08-26

### [Added]
- **Gunicorn スタイル Pre-fork プロセススーパーバイザー & 調停基盤 (`src/supervisor/`) (Issue 069, 070, 076, 077, 078)**:
  - マスター Arbiter によるワーカー監視、ヘルスチェック、自動リカバリ、およびシグナル調停。
  - ドメイン非依存・汎用プロセスエンジン抽象化（SyncWorker, GthreadWorker, AsyncWorker）。
  - Supervisor デーモンモード（`-D` / `--daemon`）および CLI `top` リアルタイム監視モニタ。
  - DSN-12 準拠 DAG トポロジカル順序起動、ONESHOT_TASK バッチ管理、および QueueWorker の実装。
- **プロセス間通信（IPC）完全分離アーキテクチャ (Issue 075)**:
  - Unix Domain Socket による DB・Web・Search の完全プロセス分離とゼロシリアライゼーション IPC ラッパー基盤。
- **マルチソース・マルチテーマ対応インテリジェンス基盤 (Issue 057, 067)**:
  - Pluggable Source Adapters（arXiv, IACR ePrint）およびテーマ別パイプライン（Theme-Aware Pipeline）。
  - IACR ePrint フィードの空 URL ハンドリングおよび TLS/SSL 証明書検証フォールバック。
- **ゼロ外部依存・大規模分散 Web クローラー & スパイダー基盤 (Issue 058, DSN-15 / DSN-06)**:
  - `BaseSpider`, `Engine`, `Scheduler`, `Downloader`, `BloomFilter` による分散スパイダーコア基盤。

### [Changed]
- **クリーンアーキテクチャに基づくパッケージ再設計 & レガシー完全削除 (Issue 059, 060, 061, 062)**:
  - `src/` および `tests/` をクリーンアーキテクチャに再編。
  - 後方互換性シム・レガシーエイリアスを完全撤廃。
  - 検索基盤を Engine と Platform の 2 層分離モジュラー構成へ昇格。
  - 設計書体系（`docs/designs/*.md`）を 1:1 パッケージ対応形式へ統一。

### [Fixed]
- **ワーカープロセス管理・クラッシュ障害の根絶 (Issue 071, 072, 073, 074)**:
  - Arbiter 突然死および予期しない PID 変化の修正。
  - `scale` コマンド実行時の DB ワーカー巻き添え停止バグの改修。
  - アイドル状態継続後のワーカー誤判定・ヘルスチェック誤表示およびゾンビプロセス回収不備の修正。

---

## [0.5.0] - 2026-08-21

### [Added]
- **ゼロ外部依存 純粋 Python SQLite 互換 & 分散データベース基盤 (`src/database/`) (Issue 026 - 056, DSN-14)**:
  - **ストレージ層**:
    - 4KB 固定長スロッテッドバイナリページ構造、2Q バッファプール（FIFO In/Out + LRU Main）、ページピニング（Issue 038, 041, 042）
    - ARIES クラッシュリカバリ、先行書き込みログ（WAL）、ファジーチェックポイント（Issue 039, 043）
    - LSM-Tree ストレージ（MemTable, SSTable, Bloom Filter, 多段コンパクション）（Issue 042, 046）
    - CoW（コピーオンライト）B-Tree & LMDB 型シャドウページングエンジン（Issue 043, 045）
    - PAX（Partition Attributes Across）ハイブリッド列指向ストレージ＆アナリティクススキャナ（Issue 044）
  - **トランザクション & 実行層**:
    - MVCC（マルチバージョン同時実行制御）& SS2PL（厳格2相ロック）トランザクションマネージャ（Issue 040）
    - CBO（コストベースオプティマイザ）、ヒストグラム統計、DP（動的計画法）Join 順序最適化（Issue 045）
    - Volcano イテレータモデル & ベクトル化実行エンジン（Issue 046）
    - 純粋 Python VDBE 仮想マシン、SQL パーサー、B+Tree インデックス（Issue 027, 028, 033）
  - **分散合意 & 分散アルゴリズム層**:
    - Lamport / Vector 論理クロックおよび因果一貫性モデル（Issue 047）
    - Phi Accrual 確率的障害検出器 & Gossip プロトコル（Issue 048, 050）
    - Quorum レプリケーション & Read Repair（Issue 049）
    - Merkle ツリー & CRDT アンチエントロピー同期（Issue 050）
    - Raft 分散合意アルゴリズム & 状態マシンレプリケーション（SMR）（Issue 051）
    - 分散 2PC（2相コミット）トランザクション調整 & 分散デッドロック検出器（Issue 052）
    - Saga パターン分散トランザクション（オーケストレーション & 補償トランザクション）（Issue 053）
    - コンシステントハッシュ & 仮想ノード（Virtual Nodes）シャーディング（Issue 054）
  - **テスト検証基盤**:
    - SQLite 互換検証テストスイート、US-01 〜 US-12 & DSN-14 シナリオ 1〜7 E2E テストの拡充（Issue 055, 056）
    - `tests/database/` の `src/database/` 1:1 階層整合。

---

## [0.4.0] - 2026-08-20

### [Added]
- **エンタープライズ・マルチフィールド検索エンジン & 高度インデックス (Issue 010, 012, 016, 017)**:
  - 転置インデックス（Inverted Index）、Okapi BM25、FM-Index（BWT/Suffix Array による部分文字列検索）、Raptor ツリー、論文引用 PageRank の統合。
  - Lucene/Solr パラダイムに基づくマルチフィールドスキーマ、アナライザー、クエリパーサー、および動的ハイライターの実装。
  - 論文トポロジー可視化・近傍グラフエンジン（Issue 011）。
- **4大 MCP サーバー統合スイート (`src/mcp/`) (Issue 015, 019, 023, 024)**:
  - `papers_server.py`: 論文探索・RAG 要約 MCP サーバー
  - `observability_server.py`: AI コーディングエージェント向けプロファイリング・メトリクス MCP サーバー
  - `threat_defense_server.py`: 脅威防御・セキュアパッチ合成 MCP サーバー
  - `tech_radar_server.py`: テクノロジーレーダー・動向分析 MCP サーバー
  - MCP プロンプトテンプレート、動的ページネーション、およびリソース配信の拡充。
- **標準ライブラリ・オブザーバビリティ & セキュリティ防護 (Issue 018, 020, 021, 022, 025)**:
  - 外部依存ゼロのプロファイリングフレームワーク、ホットパス最適化、IR 評価（Precision@K, Recall@K, MAP, MRR, NDCG）。
  - AST セキュリティガードによるコード安全性検証、パストラバーサル防御、および RBAC 認可（Issue 032）。
- **パイプライン ETL アーキテクチャ刷新 (Issue 031, 034)**:
  - 旧フェッチャーを Extract $\to$ Transform $\to$ Load 3段階モジュラーパイプラインへリファクタリング。
  - Web サーバーを API Gateway と UI Presentation に責任分離。

---

## [0.3.0] - 2026-08-16

### [Added]
- **MCP サーバ ＆ ベクトル DB セマンティック検索基盤 (Issue 001)**:
  - 全 OKF 論文ドキュメントを永続インデックス化するセマンティックベクトル＋BM25 ハイブリッド検索エンジンの実装。
  - 標準 Model Context Protocol JSON-RPC サーバの実装。
- **セキュリティ専門用語シノニム拡張 (Issue 002)**:
  - 日英セキュリティ用語を相互展開する `src/synonym_expander.py` の開発・統合。
- **Glassmorphic Web 検索 UI & ポータル (Issue 003)**:
  - REST API および静的配信を提供する Web サーバーの構築。
  - リッチ Glassmorphism ダークモード Web UI（`site/index.html`, `style.css`, `app.js`）の実装。
- **Pure JS マークダウンコンパイラ & Closure Compiler ミニファイ (Issue 004, 005)**:
  - Lexer, Parser, Evaluator, Renderer, Orchestrator による内製マークダウンコンパイラ。
  - Google Closure Compiler ツール統合（`make build_js`）。
- **日本語 IR 特徴語抽出 & PEP 3333 WSGI サポート (Issue 006, 007)**:
  - 自動特徴語抽出・事前注釈機能の実装。
  - PEP 3333 (WSGI v1.0.1) 準拠 `WSGIApplication` の実装。
- **全文アブストラクトインデックス化 (Issue 008)**:
  - 14,000件以上の論文アブストラクトをトークンインデックス化し、本文言及モデル・キーワードの検索再現率を飛躍的向上。
- **Python 3.14.7 ランタイム移行 & Strict 型検査整備 (Issue 009)**:
  - Python 3.14.7 への開発・実行環境アップグレードおよび `.venv` 再構築。
- **Antigravity IDE & 2.0 自動化連携**:
  - `schedule` ツールによる 1 日 4 回（00:00, 06:00, 12:00, 18:00 UTC/JST）バックグラウンド Cron 自動実行。
  - 4大専門 Skill（`paper-trend-analyzer`, `backfill-pipeline`, `threat-model-tagger`, `health-check-monitor`）の導入。
  - 文書管理台帳（[MNG-01]）および `docs/` ディレクトリ統廃合。

---

## [0.2.0] - 2026-08-15

### [Changed]
- **エグゼクティブサマリー 5 階層連続項番化**:
  - 06_semi_annual（半期サマリー）を完全廃止。
  - サマリーディレクトリを 5 階層ソート可能項番（`01_per_run`, `02_daily`, `03_monthly`, `04_quarterly`, `05_annual`）へ再定義。
- **品質ゲートの強化**:
  - `verify-quality-gates` による Python 構文・OKF 仕様・絶対パス排除・冪等性アサーションの自動検査化。

---

## [0.1.0] - 2026-08-14

### [Added]
- **ファーストコミット / コアフェッチエンジン (`arxiv_okf_fetcher.py`) 初期リリース**:
  - arXiv API (`cs.CR`) からのセキュリティ論文メタデータフェッチ、arXiv RSS 自動フォールバック機能。
  - 原本 4 点セット保存（`<clean_id>_meta.json`, `<clean_id>_raw_abstract.txt`, `<clean_id>.pdf`, `<clean_id>.txt`）。
  - Google OKF (Open Knowledge Format) v0.2 スキーマへの自動変換。
  - `processed_papers.json` による重複排除・冪等性管理。
  - 動的テンプレート（`templates/`）による 100% 完全日本語エグゼクティブサマリー自動生成機構。

---

[Unreleased]: https://github.com/rokujyouhitoma/arxiv-security-papers/compare/v1.1.0...HEAD
[1.1.0]: https://github.com/rokujyouhitoma/arxiv-security-papers/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/rokujyouhitoma/arxiv-security-papers/compare/v0.9.0...v1.0.0
[0.9.0]: https://github.com/rokujyouhitoma/arxiv-security-papers/compare/v0.8.0...v0.9.0
[0.8.0]: https://github.com/rokujyouhitoma/arxiv-security-papers/compare/v0.7.0...v0.8.0
[0.7.0]: https://github.com/rokujyouhitoma/arxiv-security-papers/compare/v0.6.0...v0.7.0
[0.6.0]: https://github.com/rokujyouhitoma/arxiv-security-papers/compare/v0.5.0...v0.6.0
[0.5.0]: https://github.com/rokujyouhitoma/arxiv-security-papers/compare/v0.4.0...v0.5.0
[0.4.0]: https://github.com/rokujyouhitoma/arxiv-security-papers/compare/v0.3.0...v0.4.0
[0.3.0]: https://github.com/rokujyouhitoma/arxiv-security-papers/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/rokujyouhitoma/arxiv-security-papers/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/rokujyouhitoma/arxiv-security-papers/releases/tag/v0.1.0
