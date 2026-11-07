---
ID: 750
種別: Feature
優先度: High
ステータス: Closed
関連 Issue: #726, #741, #743, #749, #751, #752
---

# [FEAT/SEC] タスクメールボックスの O(1) FIFO キュー化および上限設定 (CWE-400 対策) (ID: 750)

## 1. 概要 / Summary

Synapse 並行性ランタイムにおいて、`<task-context>` が保持する通知・メッセージ受け取り口（メールボックス / `handoff-box`）は、Issue #726 にて単一スロットから FIFO リスト構造へ拡張された。
しかし、現在の実装（[`ulisp/runtime/concurrency/channel.scm`](../../ulisp/runtime/concurrency/channel.scm)）には以下の2つの深刻な課題が存在する：

1. **無制限なリソース消費とメモリ枯渇脆弱性 (CWE-400 / DoS)**:
   メールボックスに保持できるメッセージ数に上限（Capacity / Bound）が設定されていない。外部または並行タスクから高速にメッセージが送信され続けた場合、メモリが際限なく消費され、GC 停止頻発や OOM (Out Of Memory) クラッシュを引き起こす。
2. **`append` による $O(n)$ 線形劣化と過剰なメモリコピー**:
   メッセージの追加処理（`task-set-handoff!` / `task-mailbox-enqueue!`）が単方向リストに対する `(append cur-list (list entry))` で実装されている。蓄積メッセージ数 $n$ に対し、1回のエンキューごとに $O(n)$ の走査とリスト全体の再コピーが発生し、メッセージ数が増えるにつれてスループットが劇的に低下する。また、`task-mailbox-size` も `(length cur)` で $O(n)$ を要している。

本 Issue では、単一のアトミックボックス（`atomic-cas!`）で更新可能な **2-List FIFO キュー（Banker's Queue / Batched Queue）構造** を導入し、**エンキュー $O(1)$、デキュー償却 $O(1)$、サイズ取得 $O(1)$** を達成する。
同時に、**タスクごとの容量制限（Bounded Mailbox）** および上限超過時の防御ポリシー（拒絶 / バックプレッシャー）を実装し、CWE-400 脅威を根本解消する。さらに、システム重要シグナル（`DOWN`, `EXIT`, `poisoned`）が通常メッセージの氾濫によって喪失・破棄されない優先保証機構を確立する。

---

## 2. 脅威モデル分析とセキュリティ影響 (STRIDE & CWE)

| 脅威分類 (STRIDE) | 対象 CWE | 影響度 | 脅威シナリオと脆弱性のメカニズム |
| :--- | :--- | :---: | :--- |
| **Denial of Service (DoS)** | **CWE-400**: Uncontrolled Resource Consumption | High | 悪意のある、または過負荷な送信タスクが、受信タスクに対して大量のメッセージを連続送信。メールボックスが無制限に肥大化し、メモリ枯渇 (OOM) や長時間 GC 停止を誘発しシステム全体を麻痺させる。 |
| **Denial of Service (DoS)** | **CWE-400**: Excessive Algorithmic Complexity | High | メッセージ蓄積時に `task-set-handoff!` が毎回 $O(n)$ でリスト末尾まで走査・コピーするため、1,000 件の蓄積で延べ 500,000 回のペア確保・走査が発生。CPU を独占しスケジューラスループットが激減する。 |
| **Tampering (改ざん)** / Deadlock | **CWE-400**: Missing Critical Signal Delivery | High | 上限設定時に通常メッセージと死活監視シグナル（`DOWN`, `EXIT`, `poisoned`）を無差別に拒絶・破棄した場合、親プロセスや Supervisor が子のクラッシュを検知できず、ゾンビタスクの残留やデッドロックに至る。 |

---

## 3. 根本原因分析 (RCA) / Root Cause Analysis

### なぜこの問題が存在しているか
1. **Issue #726 の暫定拡張実装 (`channel.scm` L427-443)**:
   ```scheme
   (define (task-set-handoff! t val)
     ...
     (let* ((cur (atomic-ref box))
            (cur-list (cond
                        ((not (pair? cur)) '())
                        ((boolean? (car cur)) (list cur))
                        (else cur)))
            (next-list (append cur-list (list entry))))
       (if (atomic-cas! box cur next-list) ... (retry))))
   ```
   Issue #726 では「通知の上書き消失防止」が主目的であったため、単一スロットをリスト化する最もシンプルな方法として `append` が採用され、要素数追跡や上限制御が未実装のまま残された。
2. **単一 `atomic-box` に対する Head/Tail 整合性の難しさ**:
   Michael-Scott MPMC キュー（`queue.scm`）のように Head と Tail を個別の `atomic-box` に分離すると、`<task-context>` の `handoff-box` 単一スロットとの互換性が損なわれ、また容量制限（Bounded Queue）における厳密なサイズ整合性 CAS が複雑化するため、単一リストが維持されていた。

---

## 4. 恒久対策アーキテクチャ設計 (Bounded 2-List FIFO Mailbox)

### 4.1 2-List FIFO キュー（Banker's Queue）内部レイアウト
単一の `atomic-box` の内部に、以下のベクタまたはレコード構造体を格納する：
```
#(%%task-mailbox <count> <capacity> <front-list> <rear-list> <dropped-count> <policy>)
```
- `<count>`: 現在キューに格納されているメッセージ数 ($O(1)$ 取得)
- `<capacity>`: メールボックスの最大保持数 (正の整数、または `-1` で無制限。デフォルト: 1024)
- `<front-list>`: デキュー側リスト（古い順: `(head1 head2 ...)`）
- `<rear-list>`: エンキュー側リスト（新しい順: `(newest ... new1)`）
- `<dropped-count>`: 容量超過によりドロップ/拒絶されたメッセージ数の累計カウンタ
- `<policy>`: 容量超過時の動作ポリシー (`'reject`, `'drop-oldest`, `'drop-newest`。デフォルト: `'reject`)

### 4.2 計算量の保証
- **エンキュー ($O(1)$)**:
  `rear-list` の先頭に `(cons #t val)` を `cons` するだけ（リスト反転や `append` 不要）。
  `next = #(%%task-mailbox (+ count 1) capacity front-list (cons (cons #t val) rear-list) dropped-count policy)`
  `atomic-cas!` で単一ステップ更新。
- **デキュー (償却 $O(1)$)**:
  - `front-list` が非空の場合: `(car front-list)` を取り出し、`new-front = (cdr front-list)` とする。
  - `front-list` が空かつ `rear-list` が非空の場合: `(reverse rear-list)` を新たな `front-list` とし、`rear-list` を `'()` とする。
- **サイズ取得 ($O(1)$)**:
  `<count>` スロットを直接参照するため、従来の `(length cur)` のようなリスト走査は一切不要。
- **空判定 ($O(1)$)**:
  `(= count 0)` の判定のみ。

### 4.3 容量制限（Bounded Mailbox）とシステム緊急シグナル保護
- **通常メッセージ**:
  `count >= capacity` かつ `capacity > 0` の場合、ポリシーに従って拒絶またはドロップを行う：
  - `'reject` (デフォルト): エンキュー失敗。`task-mailbox-try-enqueue!` は `#f` を返す。`task-set-handoff!` / `task-mailbox-enqueue!` は `(error 'mailbox-full ...)` を発生させるか、非ブロッキング試行で安全に拒絶。
  - `'drop-oldest`: `front-list` から最古のメッセージを1件破棄して新規メッセージを格納。
  - `'drop-newest`: 新規メッセージを破棄し、`dropped-count` をインクリメント。
- **緊急シグナル保護 (High-Priority System Signal Bypass)**:
  メッセージがシステム重要通知（`(DOWN ...)`、`(EXIT ...)`、`(cons 'poisoned ...)`、`(cons 'io_complete ...)`）である場合、上限超過時であっても**緊急許容バッファ（例: capacity の 1.25 倍まで、またはシステムシグナル専用スロット）**により配送を保証し、Supervisor や Monitor の麻痺（CWE-400 による二次障害）を防止する。

### 4.4 後方互換性の完全維持
- 既存の外部 API および内部呼び出し：
  - `task-set-handoff!`
  - `task-take-handoff!`
  - `task-has-handoff?`
  - `task-handoff`
  - `task-mailbox-enqueue!`
  - `task-mailbox-dequeue!`
  - `task-mailbox-peek`
  - `task-mailbox-empty?`
  - `task-mailbox-size`
- 旧来の形式（`#f` や単一ペア `(cons #t val)`、旧リスト形式）が万が一 `atomic-ref` された場合でも自動アップグレードして透過的に処理するフォールバックロジックを具備。

---

## 5. 影響範囲と関連ファイル / Scope and Affected Files

- [x] [`ulisp/runtime/concurrency/channel.scm`](../../ulisp/runtime/concurrency/channel.scm):
  - `%%make-task-mailbox`, `%%task-mailbox?` 内部アクセサの実装
  - `*task-mailbox-default-capacity*` (デフォルト: 1024) 定数の定義
  - `task-mailbox-capacity`, `task-mailbox-capacity-set!` の実装
  - `task-mailbox-policy`, `task-mailbox-policy-set!` の実装
  - `task-mailbox-dropped-count` の実装
  - `task-set-handoff!` / `task-mailbox-enqueue!` の 2-list O(1) 化および容量制限・システムシグナルバイパスの実装
  - `task-mailbox-try-enqueue!` の追加
  - `task-take-handoff!` / `task-mailbox-dequeue!` の 2-list O(1) デキュー化
  - `task-handoff` / `task-mailbox-peek` の 2-list 対応
  - `task-has-handoff?`, `task-mailbox-empty?`, `task-mailbox-size` の O(1) 化
- [x] [`ulisp/lib/ulisp/concurrency/channel.sld`](../../ulisp/lib/ulisp/concurrency/channel.sld):
  - 新規 API（`task-mailbox-capacity`, `task-mailbox-capacity-set!`, `task-mailbox-try-enqueue!`, `task-mailbox-policy`, `task-mailbox-policy-set!`, `task-mailbox-dropped-count`, `*task-mailbox-default-capacity*`）のエクスポート追加
- [x] [`tests/concurrency/test_links_monitors.scm`](../../tests/concurrency/test_links_monitors.scm):
  - 既存 Group 8 のテストが 100% 互換性を保ち PASS することを確認
- [x] [`tests/concurrency/test_task_mailbox.scm`](../../tests/concurrency/test_task_mailbox.scm):
  - 新規テストスイートの作成（O(1) 大量エンキュー/デキュー検証、容量超過時の reject/drop 動作、緊急シグナル保護検証、並行スレッド競合耐性）

---

## 6. 実装方針 / Implementation Plan

Target Branch: `feat/750-implement-bounded-fifo-task-mailbox-queue`

### Step 1: 2-List メールボックスデータ構造とヘルパー関数の定義
[`ulisp/runtime/concurrency/channel.scm`](../../ulisp/runtime/concurrency/channel.scm) にて以下を実装：
```scheme
(define *task-mailbox-default-capacity* 1024)

(define (%%make-task-mailbox count capacity front rear dropped policy)
  (vector '%%task-mailbox count capacity front rear dropped policy))

(define (%%task-mailbox? obj)
  (and (vector? obj)
       (>= (vector-length obj) 7)
       (eq? (vector-ref obj 0) '%%task-mailbox)))

(define (%%is-critical-signal? val)
  (cond
    ((pair? val)
     (let ((k (car val)))
       (or (eq? k 'DOWN)
           (eq? k 'EXIT)
           (eq? k 'poisoned)
           (eq? k 'io_complete))))
    (else #f)))
```

### Step 2: O(1) エンキューと容量上限チェック (`task-set-handoff!` / `task-mailbox-enqueue!`)
1. 現在のメールボックス状態を取得。`#f` または旧形式の場合は `%%make-task-mailbox` へ正規化。
2. `count >= capacity` の場合：
   - `(%%is-critical-signal? val)` が真であれば、緊急許容バッファ（`(* capacity 2)` 等）まで特別許可。
   - 通常メッセージの場合、`policy` に応じて処理（`'reject` なら `#f` または例外、`'drop-oldest` なら `front` から1件破棄、`'drop-newest` なら破棄して `dropped` カウンタ加算）。
3. `rear` の先頭に `(cons #t val)` を追加し、`count` をインクリメント。
4. `atomic-cas!` でアトミック更新。失敗時はリトライ。

### Step 3: O(1) デキューと Peek の実装 (`task-take-handoff!` / `task-mailbox-dequeue!`)
1. `front` が空かつ `rear` が非空の場合、`(reverse rear)` を新たな `front` とし、`rear` を `'()` に再編成。
2. `front` の先頭要素を取り出し、`new-front = (cdr front)`、`count = (- count 1)`。
3. `count = 0` の場合は空状態として更新。
4. `atomic-cas!` でアトミック更新。

### Step 4: メールボックス設定 API の拡充
- `task-mailbox-capacity`, `task-mailbox-capacity-set!`
- `task-mailbox-policy`, `task-mailbox-policy-set!`
- `task-mailbox-dropped-count`
- `task-mailbox-try-enqueue!` (上限超過時にブロッキングせず `#f` を返す非例外 API)

### Step 5: テストの作成と総合検証
1. `tests/concurrency/test_task_mailbox.scm` を新規作成：
   - 10,000 件のメッセージ連続エンキュー・デキューにおける O(1) 実行検証（線形劣化なし）。
   - Capacity 上限設定時の挙動検証（reject, drop-oldest, drop-newest）。
   - メッセージ上限到達時における `DOWN` / `EXIT` / `io_complete` 緊急シグナルの優先配送保護検証。
   - マルチスレッド並行エンキューにおける CAS 競合・整合性検証。
2. `make -C ulisp test_links_monitors` PASS。
3. `make -C ulisp test_concurrency_ci` PASS。
4. `make -C ulisp test` PASS。
5. `make verify_quality` PASS。

---

## 7. 完了条件 / Success Criteria (DoD)

- [x] **O(1) FIFO キュー化の達成**:
  - `task-mailbox-enqueue!` / `task-set-handoff!` が `append` を使わず $O(1)$ 時間で完了すること。
  - `task-mailbox-size` がリスト走査なしで $O(1)$ で取得できること。
- [x] **Bounded Mailbox (容量制限) と CWE-400 対策の実装**:
  - デフォルト上限 `*task-mailbox-default-capacity*` (1024) が機能し、無制限なメモリ蓄積が防御されること。
  - タスクごとに `task-mailbox-capacity-set!` で容量を変更可能であること。
- [x] **緊急システムシグナルの保護**:
  - メールボックスが通常メッセージで満杯であっても、`DOWN`, `EXIT`, `poisoned`, `io_complete` 等のシステム死活シグナルが破棄されず配送されること。
- [x] **後方互換性の完全保証**:
  - 既存の `task-set-handoff!`, `task-take-handoff!`, `task-has-handoff?`, `task-handoff` を使用する全モジュール（`links.scm`, `supervisor.scm`, `channel.scm`, `io_uring.scm`, `registry.scm`）が修正なしで正常稼働すること。
- [x] **テストスイートの作成と完全合格**:
  - `tests/concurrency/test_task_mailbox.scm` が新規作成され、全テスト項目が PASS すること。
  - `make -C ulisp test_links_monitors` および `make -C ulisp test_concurrency_ci` が PASS すること。
  - `make -C ulisp test`（Nanopass 38パス、セルフホスティング bit-for-bit）が 100% PASS すること。
  - `make verify_quality`（2,766+ テスト、静的解析）が 100% PASS すること。
