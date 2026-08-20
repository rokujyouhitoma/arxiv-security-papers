---
ID: 056
種別: Test
優先度: High
ステータス: In Progress
担当: Database / QA Specialist
開始日: 2026-08-20
---

# [TEST] SQLite 互換 DB 包括的検証テストスイート & 次世代 DB エンジン E2E シナリオ（US-01 〜 US-12 & DSN-14 シナリオ 1〜7）の拡充 (ID: 056)

## 1. 概要 / Summary

SQLite 互換データベース（`src/database/`）の網羅的な振る舞い検証および次世代データベースエンジン設計書（[DSN-14]）のアーキテクチャ・マイルストーンを検証するための包括的ユーザーシナリオ（User Scenarios & Acceptance Criteria）を策定・実装する。
単一ノードのストレージ基盤（Slotted-Page, LSM-Tree, PAX, CoW B-Tree）から分散合意・クラッシュリカバリ（Raft, Quorum, ARIES, Saga）まで、実運用ワークロードを模した End-to-End の検証フローを網羅する。

---

## 2. SQLite 互換ユーザーストーリー (US-01 〜 US-12)

| ユーザーストーリー | テストファイル | `src/database/` 検証対象モジュール |
| :--- | :--- | :--- |
| **US-01: テーブル定義と型アフィニティ** | `test_us01_schema_and_affinity.py` | `SQLParser`, `TableCatalog`, `SQLExecutor`, `driver.connect` |
| **US-02: 基本CRUDと動的データ操作** | `test_us02_crud_and_dynamic_typing.py` | `SQLExecutor`, `VectorStorage`, `TableCatalog` |
| **US-03: 主キー・RowID・B+Tree** | `test_us03_primary_key_and_rowid.py` | `BPlusTree`, `BTreeNode`, `ScalarKey` |
| **US-04: 結合・集計・Volcanoイテレータ** | `test_us04_joins_subqueries_and_cte.py` | `NestedLoopJoinIterator`, `HashJoinIterator`, `FilterIterator`, `ProjectionIterator`, `LimitIterator` |
| **US-05: 組み込み関数・KNN・LIKE** | `test_us05_builtin_functions_and_operators.py` | `SQLExecutor` (KNN, LIKE, Expression Eval) |
| **US-06: インデックスとCBO実行計画** | `test_us06_indexes_and_explain_plan.py` | `QueryPlanner`, `TableStats`, `SQLCompiler` (EXPLAIN) |
| **US-07: トランザクション・ロールバック** | `test_us07_transactions_and_savepoints.py` | `TransactionManager`, `MVCCManager`, `SQLExecutor` |
| **US-08: 同時実行制御・2PL・デッドロック** | `test_us08_concurrency_and_locking.py` | `LockManager` (SS2PL), `WaitForGraph`, `DeadlockError` |
| **US-09: クラッシュリカバリ・ARIES** | `test_us09_crash_recovery_and_durability.py` | `ARIESRecoveryManager`, `WALWriter`, `Pager` |
| **US-10: メタ情報照会・RBAC・プロファイラ** | `test_us10_pragma_commands.py` | `TableCatalog`, `AccessController` (RBAC), `DatabaseProfiler` |
| **US-11: インメモリVFS・一時セッション** | `test_us11_in_memory_and_temp_tables.py` | `MemoryVFS`, `Pager` (:memory:), Session Isolation |
| **US-12: E2E データベースライフサイクル** | `test_us12_e2e_database_lifecycle.py` | `driver.connect`, `SQLExecutor`, `TableCatalog`, `VectorStorage` (Step 1〜7) |

---

## 3. 次世代 DB エンジン（DSN-14）包括的検証シナリオ (Scenarios 1〜7)

### シナリオ 1: 大規模インジェスチョンとスロット化ページ永続化（LSM / Slotted-Page）
- **ペルソナ**: データエンジニア / バッチ処理システム
- **背景**: 160日分の論文メタデータおよび固定長ベクトル（Float32 128次元）の一括バックフィルを実行する。
- **実行フロー**:
  1. クライアントが数万件規模のメタデータ（可変長日本語要約を含む）とベクトルを連続投入する。
  2. システムはメモリ上の MemTable（ロックフリー SkipList）へシーケンシャル追記し、同時に WAL ログをディスクへ記録する。
  3. MemTable 満杯時、Immutable MemTable を経由してバックグラウンドで SSTable（4KB Slotted Page 形式）へソート順にフラッシュ（Minor Compaction）する。
  4. 4KB を超える巨大抽出テキストは自動的にオーバーフローページ連鎖へ退避される。
- **受け入れ基準（Acceptance Criteria）**:
  - [ ] 可変長テキストの削除・更新を行っても、ページ内スロット再利用（In-Place Compaction）により外部断片化が発生しないこと。
  - [ ] 事前配置された Bloom フィルタにより、存在しないキーに対する不必要なディスク I/O が 99% 抑制されること。

### シナリオ 2: 複合検索・OLAP集計とゼロコピー高速参照（B+Tree / PAX / mmap）
- **ペルソナ**: セキュリティリサーチャー / アナリスト
- **背景**: 過去数年分の脆弱性データ（CVE/タグ）の範囲検索および年次別集計をリアルタイムに実行する。
- **実行フロー**:
  1. リサーチツールから日付範囲検索（`WHERE published_date >= '2020-01' AND ...`）とハイブリッド類似度検索が発行される。
  2. QueryPlanner（CBO）が統計情報（`TableStats`）に基づき、B+Tree インデックス走査を選択する。
  3. Pager（2Q アルゴリズム）が 4KB ページをフェッチし、フルスキャンによるキャッシュ汚染（Scan Pollution）を防止する。
  4. カラムナー集計クエリ（`GROUP BY category` 等）では、PAX レイアウトと辞書化・RLE 圧縮された列ブロックのみを読み取り、不要なベクトル列の I/O をスキップする。
  5. 読み取り専用クエリに対し、OS mmap を経由したゼロコピー（Zero-Copy Read）でデータを取得する。
- **受け入れ基準**:
  - [ ] B+Tree のリーフ間双方向リンクにより、範囲走査がランダムシークなしでシーケンシャルに実行されること。
  - [ ] mmap によるゼロコピー参照時、Python ヒープへの余計なメモリアロケーションオーバーヘッドが発生しないこと。

### シナリオ 3: 高並行トランザクションとデッドロック回避（MVCC / SS2PL）
- **ペルソナ**: マルチスレッド API サーバ
- **背景**: 多数のワーカーが論文評価スコアの更新とメタデータ参照を同時に高頻度で実行する。
- **実行フロー**:
  1. 参照トランザクションは MVCC スナップショットアイソレーション（SI）に基づき、トランザクション開始時点の `xmin` / `xmax` 可視性に従ってロックフリーでデータを読み取る。
  2. 同時に複数ワーカーが同一ノード配下のレコード更新を試行し、SS2PL ロックマネージャが排他ロック（X Latch/Lock）を調停する。
  3. 2スレッド間で循環ロック待機が発生した場合、バックグラウンドのデッドロック検出器（Wait-For Graph）が閉路を検知する。
  4. コストの低い側のトランザクションが犠牲者（Victim）として自動アボートされ、クライアントへ再試行エラーを返す。
- **受け入れ基準**:
  - [ ] 読み取りトランザクションが更新トランザクションによって一切ブロックされないこと。
  - [ ] デッドロック発生時にシステムが永久ハングせず、ミリ秒単位で閉路が検出・解消されること。

### シナリオ 4: 電源断シミュレーションとクラッシュリカバリ（WAL / ARIES）
- **ペルソナ**: SRE / データベース管理者
- **背景**: 大量書き込みトランザクション実行中に、ハードウェア電源断（SIGKILL 相当）が発生した状況からの復旧。
- **実行フロー**:
  1. トランザクション群が STEAL / NO-FORCE ポリシー下で更新処理を実行（一部の未コミットダーティページはディスク退避済み、一部のコミット済みページは未退避）。
  2. プロセスが強制終了（Crash）し、再起動シーケンスへ移行する。
  3. リカバリマネージャ（ARIES）が起動し、以下の3フェーズを実行する：
     - **Analysis Phase**: 最新の Fuzzy Checkpoint から WAL を走査し、未コミット Tx（Losers）とダーティページテーブル（DPT）を特定。
     - **Redo Phase (Repeat History)**: 最小 RecLSN からクラッシュ直前までの全変更（Losers 含む）をそのまま再現。
     - **Undo Phase**: Losers の変更を逆順にロールバックし、補償ログレコード（CLR）を WAL に追記。
- **受け入れ基準**:
  - [ ] コミット済みトランザクションのデータが 100% 永続化（Durability）されていること。
  - [ ] 未コミットの変更が完全に巻き戻され、データベースの不整合や破損（Corruption）が残らないこと。
  - [ ] Undo 処理中に再クラッシュが発生しても、CLR の UndoNextLSN により二重 Undo を起こさず復旧できること。

### シナリオ 5: 分散ネットワーク分断と障害検出・リーダー選出（$\Phi$ Accrual / Raft）
- **ペルソナ**: クラスタ運用オーケストレータ
- **背景**: 3ノード構成（Node A, B, C）のクラスタにおいて、リーダーノード A の一時的なネットワーク遅延・停止が発生する。
- **実行フロー**:
  1. フォロワーノード（Node B, C）の $\Phi$ Accrual 障害検出器が、ノード A からのハートビート間隔の統計的遅延を計算する。
  2. $\Phi \ge 12$ に達した段階で、Node B がノード A を障害と判定し、選挙タイムアウトを発火させる。
  3. Node B は任期（Term）をインクリメントし、RequestVote RPC をブロードキャストする。
  4. Node C が過半数（Quorum）の合意票を返し、Node B が新リーダーに昇格して AppendEntries（ハートビート）を開始する。
  5. 遅延から復帰した旧リーダー Node A が古い Term のメッセージを送信するが、新 Term 番号による Epoch Fencing により拒否され、Node A はフォロワーへ降格する。
- **受け入れ基準**:
  - [ ] ネットワークのゆらぎによる偽陽性フェイルオーバーが防止されること。
  - [ ] スプリットブレインが完全に排除され、常に単一の正当なリーダーのみが書き込みを受け付けること。

### シナリオ 6: クォーラム更新と Merkle Tree による自律修復（Strict Quorum / Anti-Entropy）
- **ペルソナ**: 高可用性分散ノードシステム
- **背景**: 厳格なクォーラム（$N=3, W=2, R=2$）環境で、1ノードが一時的にオフラインになった後のデータ整合性回復。
- **実行フロー**:
  1. Node 3 がオフラインの間、クライアントは Node 1, Node 2 に書き込みを行い、$W=2$ の ACK でコミット完了（線形化可能性を維持）。
  2. 一時更新を受け付けたノードは、CRDT（OR-Set）およびバージョンベクトルを用いてタグ・メタデータの更新履歴を管理する。
  3. Node 3 が再起動してネットワークに復帰する。
  4. バックグラウンドのアンチエントロピープロセスが起動し、Node 1 と Node 3 の間でトークンレンジごとの Merkle Tree（ハッシュ木）のルートハッシュ（32B）を比較する。
  5. ハッシュ不一致の分岐ノードのみを二分探索で下降走査（$O(\log N)$）し、欠損していたレコード差分のみをピンポイントで Node 3 へ転送・同期する。
- **受け入れ基準**:
  - [ ] クライアントの読み取り時（$R=2$）、最新データが確実に返却されること。
  - [ ] 全件スキャンを伴うネットワーク帯域消費を起こさず、最小限の差分データ転送で Node 3 の同期が完了すること。

### シナリオ 7: 長時間実行パイプラインの補償トランザクション（Orchestration Saga）
- **ペルソナ**: 論文データ収集・解析ワークフローワーカー
- **背景**: 「メタデータ登録 $\to$ PDF全文抽出 $\to$ ベクトル生成」という長時間にわたる分散パイプラインの途中で障害が発生する。
- **実行フロー**:
  1. Saga オーケストレータがステップ $T_1$（メタデータ登録）をローカル DB にコミットする（ロック即解放）。
  2. ステップ $T_2$（PDF全文抽出とキャッシュ格納）が正常に完了する。
  3. ステップ $T_3$（外部 LLM / ベクトル推論基盤への接続）でリトライ上限超過のエラーが発生する。
  4. オーケストレータがロールバックフローを開始し、補償トランザクションを逆順に実行する：
     - **補償 $C_2$**: 抽出キャッシュを破棄。
     - **補償 $C_1$**: 登録済みメタデータを論理削除（Tombstone マーク付与）。
- **受け入れ基準**:
  - [ ] 長時間ロックを保持することによる DB リソース枯渇が発生しないこと。
  - [ ] パイプライン途中失敗時に中途半端なゴミデータが残存せず、論理的な初期状態へ完全に復元されること。

---

## 4. 完了条件 (Definition of Done)

- [x] US-01 〜 US-12 の SQLite 互換テストケースが `tests/database/compatibility/` に実装され 100% 成功していること。
- [ ] DSN-14 シナリオ 1〜7 に対応する E2E 検証テスト群が実装され、すべての受け入れ基準を満たして 100% PASS すること。
- [ ] `make check`（フォーマット・型検査・全単体結合テスト）が 100% PASS すること。
