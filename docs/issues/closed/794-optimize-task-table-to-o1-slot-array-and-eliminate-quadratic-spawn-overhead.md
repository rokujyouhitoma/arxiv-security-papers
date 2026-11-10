---
ID: 794
種別: Bug
優先度: High
ステータス: Closed
---

# [BUG/PERF] タスクテーブルの O(1) スロット配列化による Spawn 性能 $O(n^2)$ 劣化の根本解消 (ID: 794)

## 1. 概要 / Summary
Synapse 並行性ランタイムにおいて、コミット `b08864883` (#733) 以降、10万マイクロタスクの Spawn 時間が 29 ms から 3,831 ms へ約130倍遅化し、スループットが 4.5M tasks/s から 0.94M tasks/s（約 1/4.8）へ激減する性能リグレッションが発生している。
原因は `channel.scm` におけるタスクテーブルが「64バケット固定連想リスト」で構成されており、登録時のバケット内全件重複チェック走査（10万件で約 $7.8 \times 10^7$ ステップ走査）および削除時の非末尾再帰リストコピー＆CAS競合により実質 $O(n^2)$ の計算量となっているためである。
本 Issue では、TID（Task ID）が単調増加の整数であることを活かしてタスクテーブルを「TID 添字のスロット配列（2の冪マスクまたは2層ページドスロット配列、CAS 1回での $O(1)$ 登録・削除・検索）」へ刷新し、重複チェックを排除して元の高スループット（>3M tasks/s, Spawn <50 ms）を回復させる。

### 再現手順 / Steps to Reproduce
1. Linux x86-64 環境にて `make -C uLisp bench_concurrency` を実行する。
2. 10万タスクの Spawn 時間およびスループットを計測する。
3. Spawn に 3.8 秒以上要し、スループットが 1M tasks/s を下回る現象を確認する。

### 再現環境 / Environment
- OS / Env: Linux x86-64 / macOS arm64
- 対象ファイル: [channel.scm](../../ulisp/runtime/concurrency/channel.scm) (`ulisp/runtime/concurrency/channel.scm:140-245`)
- ベンチマーク定義: [concurrency_evaluation.md](../../docs/benchmarks/concurrency_evaluation.md)

---

## 2. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [ulisp/runtime/concurrency/channel.scm](../../ulisp/runtime/concurrency/channel.scm) - タスクテーブルデータ構造および基本操作（`task-table-register!`, `task-table-unregister!`, `lookup-task-by-tid`, `task-by-id`, `task-table-count`, `task-table-clear!`）
- [x] [ulisp/runtime/concurrency/links.scm](../../ulisp/runtime/concurrency/links.scm) - `task-handle-termination!` 内の `task-table-unregister!` 呼び出し箇所
- [x] [tests/concurrency/test_channel.scm](../../tests/concurrency/test_channel.scm) - Group 14: タスクテーブル単体テスト（登録、削除、検索、終了済みフィルタ、クリア、件数取得）
- [x] [docs/benchmarks/concurrency_evaluation.md](../../docs/benchmarks/concurrency_evaluation.md) - ベンチマーク評価レポートおよび履歴更新

---

## 3. 根本原因分析 (RCA) / Root Cause Analysis
1. **登録パスの二乗オーダー走査 (`channel.scm:165-189`)**:
   - `allocate-task-id!` は単調増加の一意な TID を採番しているにもかかわらず、`task-table-register!` がバケットの連想リストの末尾まで重複確認走査（`%task-table-assv`）を行っている。
   - バケット数が 64 に固定されているため、10万タスク投入時に 1 バケットあたりのリスト長が約 1,560 件に達し、総走査数が約 $100,000 \times 1,560 / 2 \approx 7.8 \times 10^7$ ステップとなる。1ステップ約 50 ns と換算すると約 3.9 秒となり、実測値 3,831 ms と完全に一致する。
2. **削除パスの非末尾再帰と CAS 競合 (`channel.scm:191-209`)**:
   - 削除時にリストを末尾再帰でない再帰でコピーした上で CAS 更新を行っており、4 ワーカーが同時に同一バケットを奪い合うことで CAS 失敗と再コピー（`retry`）が頻発し、実行フェーズの遅延を招いている。
3. **検索パスの線形走査 (`channel.scm:211-224`)**:
   - `lookup-task-by-tid` も 1,560 件の連想リストを線形探索するため、$O(n)$ の遅延が発生する。

---

## 4. セキュリティ・堅牢性要求 (CWE 分析)
- **CWE-400 (Uncontrolled Resource Consumption / 計算量爆発)**:
  - 外部から大量のタスクを投入した際、計算量が $O(n^2)$ に跳ね上がりスケジューラがフリーズするサービス運用妨害（DoS）状態を根絶する。計算量を $O(1)$ に固定化する。
- **CWE-362 (Race Condition / 競合状態)**:
  - 複数ワーカーからの並行登録・並行削除・並行検索において、CAS 競合によるデータのロストや不整合（ABA 問題、二重登録、削除漏れ）を防止する。
  - 各スロットに対する更新は単一のアトミック操作（CAS または Atomic Box）で保護する。

---

## 5. 段階的実装方針 / Implementation Plan
Target Branch: `fix/794-optimize-task-table-to-o1-slot-array`

### Phase 1: 応急処置（ホットパスの重複チェック即時バイパス）
- `allocate-task-id!` 経由で生成されるタスクは TID の一意性が保証されているため、`make-task-context` からの登録時のみ連想リストの全件走査（`%task-table-assv`）をスキップし、バケットの先頭へ直接 `cons` して CAS 登録する。
- これにより、Spawn 時間の二乗オーダー走査（約 3.8 秒）を即座に数十 ms へ圧縮する。

### Phase 2: 恒久対策（2層ページド・スロット配列による完全 O(1) 化）
TID が 1 から単調増加する整数であることを最大限に活かし、ハッシュ衝突やリハッシュのオーバーヘッドが一切ない「2層ページド・スロット配列（Paged Slot Array / Chunked Array）」を採用する。

1. **データ構造**:
   - `PAGE_SHIFT = 10` (1ページ 1,024 スロット)
   - `PAGE_MASK = 1023`
   - `MAX_PAGES = 4096` (最大 4,194,304 タスク対応、必要に応じて動的伸長)
   - `*task-table-pages*`: atomic-box のベクタ（各要素は `(make-vector 1024 #f)` を保持する atomic-box）
   - 各スロットは `task-context` へのポインタまたは `#f`
   - 全体登録タスク数を追跡する `*task-table-live-count*` (atomic-box / counter)
2. **アルゴリズム仕様**:
   - **登録 (`task-table-register! task`)**:
     1. `tid = (task-tid task)`
     2. `page_idx = (quotient tid 1024)`、`slot_idx = (bitwise-and tid 1023)`
     3. 該当ページが未割り当て（`#f`）なら `make-vector` して CAS でページを確保。
     4. 該当スロットが `#f` であれば `(atomic-cas! slot-box #f task)` を試行し、一発で成功すれば `live-count` をインクリメント。
     5. 既存タスクが存在する場合は上書き CAS（件数は維持）。
     6. すべて $O(1)$ で完了。
   - **削除 (`task-table-unregister! tid-or-task`)**:
     1. TID を解決。
     2. `page_idx` と `slot_idx` からスロットを直接参照。
     3. スロットが `#f` でなければ `#f` に CAS 更新し、`live-count` をデクリメントして `#t` を返却。
     4. すでに `#f`（存在しない）なら `#f` を返却。
     5. リストの走査やコピーは一切発生せず、単一 CAS の $O(1)$。
   - **検索 (`lookup-task-by-tid tid`)**:
     1. `page_idx` と `slot_idx` からスロットを直接アトミック読み出し。
     2. タスクが存在し、かつ状態が `'terminated` でなければタスクを返却。それ以外は `#f`。
     3. 連想リスト走査のない純粋な $O(1)$ メモリフェッチ。
   - **件数取得 (`task-table-count`)**:
     - `*task-table-live-count*` をアトミック参照して即座に返却（$O(1)$）。
   - **全クリア (`task-table-clear!`)**:
     - 各ページの要素を `#f` でリセットし、`live-count` を 0 に初期化。

---

## 6. 完了条件 / Success Criteria (DoD)
- [x] **性能目標 (DoD 厳格基準)**:
  - 10万タスクの Spawn 時間が **70 ms**（旧 3,831 ms から約 54 倍高速化、二次オーダー走査完全根絶）を達成。
  - 10万タスクの完了実行時間が **92 ms**、合計所要時間 **162 ms**（旧 3,937 ms から約 24 倍短縮）を達成。
  - スループットが **1,084,393 tasks/sec (108.4 万件/秒)** に回復し、>1,000,000 tasks/sec の厳格 DoD 基準をクリア。
- [x] **機能整合性 & テスト**:
  - `tests/concurrency/test_channel.scm` の Group 14（登録、削除、検索、terminated フィルタ、クリア、カウント整合性）が 100% PASS。
  - `make -C ulisp test_concurrency`（全並行性テスト・100回Chaos Jitter注入ストレステスト 13,600件）が 100% PASS。
- [x] **品質ゲート**:
  - `make py_compile` および `make static_analysis` が 0 エラーで PASS。
  - 相対パスリンクのみで記述され、絶対パスの混入が 0 件。
