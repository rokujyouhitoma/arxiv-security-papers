---
ID: 630
種別: Feature
優先度: High
ステータス: Closed (Completed)
---

# [FEAT] プロセスローカル・エフェメラルアリーナおよび O(1) 瞬時全破棄機構の実装 (ID: 630)

## 1. 概要 / Summary

[DSN-37](../../designs/DSN-37-synapse_dual_plane_concurrent_runtime_architecture.md) Phase 0 Task 0.1 に基づき、アフィン部分言語コア（ASC: Affine Sub-language Core）並列タスク用の極小**プロセスローカル・エフェメラルアリーナ（Process-Local Ephemeral Arena：初期 2KB〜8KB）**を Pure Scheme で実装する。

従来の共有ヒープ型言語ランタイムでは、短命な並列マイクロタスクが大量の一時オブジェクト（cons セル、タプル、中間ベクタ）を生成するたびにグローバル GC ヒープへの割り当て競合と Stop-The-World (STW) GC 停止を引き起こす構造的課題があった。
本 Issue では、Erlang BEAM のプロセス独立ヒープ思想と領域ベースメモリ管理（Region-Based Memory Management）を融合し、各並列タスクが OS スレッドスタックおよびホスト GC ヒープから完全に隔離された専用メモリ空間（初期容量 2KB〜8KB、デフォルト 4KB）を保持する基盤を確立する。

タスク実行中のメモリ確保は単一オフセットポインタのバンプ加算（8 バイト境界アライメント）のみで完結し、タスク完了時（または世代ロールバックによる強制アボート時）にはオフセットを `0` に巻き戻すだけで全ローカルオブジェクトを一括破棄する **$O(1)$ 瞬時解放**を実現する。また、初期アリーナ容量を超過した場合でもグローバルヒープへ漏出させず、8KB の拡張チャンク連鎖（Chained Arena Chunks）へフォールバックし、リセット時に一括回収する安全機構を備える。

---

## 2. ガバナンス・専門エージェント多角レビュー / Governance & Reviews

本 Issue は、リポジトリ統治規約（[`.agents/AGENTS.md`](../../../.agents/AGENTS.md)）に従い、PM 主導のもと全 16 専門エージェントによる多角的設計レビューを統合して策定された。

- **Project Manager (PM) (Chair / Governance)**:
  - Phase 0（メモリ＆アトミック基底）の最優先マイルストーン（Task 0.1）として、後続のチャネル通信（Issue 633）、ワークスティーリングスケジューラ（Issue 635）、境界ディープコピーサニタイザ（Issue 641）、および Dual-Mode 評価アダプタ（Issue 644）の共通土台となる。外部 C ライブラリに一切依存しない Pure Scheme 実装とし、100 万回アロケーション耐久テストを完了条件（DoD）として厳格に管理する。
- **IT Specialist (Programming Languages & Compilers / PLC)**:
  - R7RS `define-record-type` により `<task-arena>` および拡張チャンク `<arena-chunk>` を純粋な Scheme レコードとして定義する。これにより uLisp AOT ネイティブコンパイラ環境と ILisp インタプリタ環境（Dual-Mode）の双方で同一コード・同一セマンティクスを完全共有できる。
  - uLisp のタグ付きポインタ規約（下位 3 ビットをタグに使用）との整合性を維持するため、すべての割り当てアドレスが厳密に 8 バイト境界（$\text{addr} \equiv 0 \pmod 8$）にアラインされることを不変条件とする。
- **Systems Architect (SA)**:
  - ホスト・カーネル分離型アーキテクチャにおいて、Layer 2（ASC 計算プレーン）が STW-GC ゼロを達成するための最重要コンポーネントである。プライマリアリーナ（2KB〜8KB）の高速パス（Fast Path）と、容量超過時の 8KB 拡張チャンク連鎖スローパス（Overflow Fallback）を明確に分離し、通常時の $O(1)$ バンプ確保・$O(1)$ リセット性能を損なわない構造とする。
- **Software Development (SWD)**:
  - アライメント計算は 2 の補数ビット演算 `(bitwise-and (+ size (- align 1)) (bitwise-not (- align 1)))`（8 バイト境界時は `(bitwise-and (+ size 7) -8)`）で分岐なしに計算する。また、ILisp / Gauche / uLisp AOT の全処理系でポータブルに動作するようビット演算互換ヘルパーを整備する。
- **Information Security Specialist (SEC)**:
  - メモリアロケータ固有の脅威（整数オーバーフロー CWE-190、無制限チャンク拡張による OOM DoS CWE-400/CWE-770、リセット後の残留データ漏洩 CWE-212）に対する防御機構を設計に組み込む。特に拡張チャンク数に上限（`*arena-max-chunks*`）を設け、暴走タスクによるホストメモリ枯渇を遮断する。また、機密データ処理タスク向けにゼロクリア付きリセット `arena-secure-reset!` を提供する。
- **Software Quality Assurance Specialist (SQA)**:
  - 単体テストスイート `tests/concurrency/test_arena.scm` において、8 バイト／16 バイト／64 バイト境界アライメント検証、境界値（容量ちょうどの割り当て）、チャンク連鎖フォールバックと回収、不正サイズ（負数・ゼロ・上限超過）のガード検証、および **100 万回連続アロケーション＆リセットによるメモリリーク 0 バイト検証**を自動実行可能にする。
- **Database Specialist (DB)** / **Network Specialist (NET)** / **IT Specialist (NLP & IR)**:
  - クエリ実行時のタプル中間バッファ、ネットワークパケットのゼロコピー移譲前ステージング、および大量テキスト走査時の短命 AST ノード確保領域として、2KB〜8KB の初期サイズと 8KB チャンク拡張の組み合わせがキャッシュ局所性（L1d キャッシュ 32KB〜48KB 内への収まり）の観点で最適であることを確認。
- **Embedded Systems Specialist (EMB)** / **IT Service Manager (SM)** / **Systems Auditor (AU)**:
  - 極小フットプリント（2KB 最小構成可能）を維持しつつ、運用可観測性（Observability）のため総割り当てバイト数（`total-allocated`）、リセット回数（`reset-count`）、現在チャンク数（`chunk-count`）の統計アクセサを `<task-arena>` に備え、リーク監査とテレメトリ採取を容易にする。

---

## 3. 脅威分析とセキュリティ要件 / Threat Modeling & Security Requirements

| 脅威分類 (STRIDE) | 脆弱性タイプ (CWE) | 潜在リスク・攻撃シナリオ | 防護策・緩和設計 (Mitigation) |
| :--- | :--- | :--- | :--- |
| **Tampering / Elevation of Privilege** | CWE-190 (Integer Overflow or Wraparound) / CWE-682 | 負のサイズや極端に巨大な `size` が `arena-allocate!` に渡された際、アライメント加算 `(+ size 7)` やオフセット加算でオーバーフローまたはオフセット逆行が発生し、既使用メモリ領域を上書きする。 | `size <= 0` または単一割り当て上限（`*arena-max-alloc-size*`）を超える要求を事前検証で即座に拒絶し、オフセットが単調増加すること（`next-off > current-off`）を保証する。 |
| **Denial of Service** | CWE-400 / CWE-770 (Allocation of Resources Without Limits or Throttling) | 悪意ある、またはバグを含むタスクが無限にメモリ確保を繰り返し、`arena-overflow-fallback!` による 8KB チャンク連鎖が無制限に伸長してホスト全体のメモリ（OOM）を枯渇させる。 | タスクあたりの最大拡張チャンク数 `*arena-max-chunks*`（デフォルト 64 チャンク＝最大 512KB）を設定し、上限到達時は決定論的にエラーを送出してタスクを安全にアボートさせる。 |
| **Information Disclosure** | CWE-212 (Improper Removal of Sensitive Information Before Storage or Transfer) | 暗号鍵やトークンを扱ったタスクが完了して `arena-reset!` された後、再利用されたアリーナメモリから別タスクが残留バイト列を読み取る。 | 高速な $O(1)$ ポインタリセット `arena-reset!` に加え、使用済み領域 `[0, offset)` および拡張チャンクを完全にゼロ埋め消去する `arena-secure-reset!` を提供する。 |
| **Denial of Service / Memory Corruption** | CWE-787 (Out-of-bounds Write) / Bus Error | 非 8 バイト境界のアドレスが返却されることで、uLisp のタグ付きポインタ（下位 3 bit タグ）が破損し、型混同（Type Confusion）や不正メモリアクセスを引き起こす。 | ベースアドレスおよびすべての割り当てサイズに対して最小 8 バイト（または指定された 2 の累乗 $\ge 8$）のアライメント切り上げを強制する。 |

---

## 4. トレーサビリティ / Traceability

- **正典設計仕様書**:
  - [DSN-37: ホスト・カーネル分離型 階層 CSP/アクター・ハイブリッド並行処理基盤 ＆ AOT コンパイルパイプライン包括的アーキテクチャ設計書](../../designs/DSN-37-synapse_dual_plane_concurrent_runtime_architecture.md#5-メモリモデルプロセスローカルエフェメラルアリーナ) (第 5 章 メモリモデル：プロセスローカル・エフェメラルアリーナ、第 13.4 節 モジュール構成とロード規約、第 14.2 節 Phase 0 Task 0.1)
  - [DSN-36: Zero-libc Pure Scheme ベアメタルランタイム包括設計仕様書](../../designs/DSN-36-zero_libc_pure_scheme_bare_metal_runtime.md)
  - [DSN-33: uLisp x86-64 ネイティブ AOT コンパイラ包括設計仕様書](../../designs/DSN-33-ulisp_underlying_x86_native_aot_compiler_architecture_specification.md)
- **関連・後続 Issue**:
  - [Issue 631: Scheme 低レベルアトミック命令 (atomic-cas! / atomic-box) の提供](../631-implement-synapse-low-level-atomic-primitives.md)
  - [Issue 633: 線形所有権移譲チャネルおよび有界バックプレッシャー機構の実装](../633-implement-synapse-first-class-p2p-channel.md)
  - [Issue 635: 分散 M:N ワークスティーリングスケジューラおよび Chase-Lev Deque の実装](../635-implement-synapse-work-stealing-scheduler.md)
  - [Issue 638: アフィン線形所有権静的検査パス (check-affine-types) および自動 RAII Drop の実装](../638-implement-nanopass-check-affine-types-and-raii-drop.md)
  - [Issue 641: ホスト・カーネル境界サニタイザおよびディープコピー機構の実装](../641-implement-synapse-boundary-sanitizer-and-deep-copy.md)
  - [Issue 642: 世代管理型投機タスク破棄および待機タスク世代ゲート検証の実装](../642-implement-synapse-epoch-fencing-distributed-rollback.md)
  - [Issue 643: 10 万並行マイクロタスク耐久ベンチマークおよび STW-GC ゼロ検証スイートの実装](../643-implement-synapse-benchmark-suite-and-stw-gc-verification.md)
  - [Issue 644: インタプリタ向け Dual-Mode 評価アダプタ (eval_adapter.scm) の実装](../644-implement-synapse-interpreter-dual-mode-eval-adapter.md)

---

## 5. 影響範囲と関連ファイル / Scope and Affected Files

- [x] [ulisp/runtime/concurrency/arena.scm](../../../ulisp/runtime/concurrency/arena.scm) (新規作成)
  - `<arena-chunk>` および `<task-arena>` レコード型定義
  - 8 バイト／任意 2 累乗境界アライメント演算（`arena-align-up`, `bitwise-not` 互換サポート）
  - 高速バンプ割り当て `arena-allocate!` および容量超過時の 8KB 拡張チャンク連鎖 `arena-overflow-fallback!`
  - $O(1)$ 瞬時全破棄 `arena-reset!` およびゼロクリア付き `arena-secure-reset!`
  - アリーナ内データ読み書き・統計プリミティブ（`arena-u8-ref`, `arena-u8-set!`, `arena-u64-ref`, `arena-u64-set!`, `arena-used-bytes`, `arena-stats`）
- [x] [ulisp/lib/ulisp/concurrency/arena.sld](../../../ulisp/lib/ulisp/concurrency/arena.sld) (新規作成)
  - R7RS `(import (ulisp concurrency arena))` 用のライブラリ定義ラッパー（公開 API シンボルの `export` と `ulisp/runtime/concurrency/arena.scm` の `include`）
- [x] [tests/concurrency/test_arena.scm](../../../tests/concurrency/test_arena.scm) (新規作成)
  - `(load "ulisp/runtime/concurrency/arena.scm")` / `(include "ulisp/runtime/concurrency/arena.scm")` / `(import (ulisp concurrency arena))` によるオンデマンドモジュール読み込み検証
  - アリーナ生成・初期状態検証、8 バイト境界アライメント検証、チャンク連鎖フォールバック検証、セキュアリセット検証、異常系ガード検証、および 100 万回アロケーション＆リセット反復リーク検証テスト
- [x] [ulisp/frontend/010_library.scm](../../../ulisp/frontend/010_library.scm) (変更)
  - DSN-37 第 13.4 節に基づき、トップレベルの定数文字列 `(load "...")` を `include` と等価に静的展開する互換サポート、`"ulisp/"` プレフィックス正規化解決、および外部 `.sld` ライブラリのオンデマンド自動解決を追加（`stdlib_entry.scm` や `ULISP_RUNTIME_LIBS` は一切汚染しない）
- [x] [ulisp/Makefile](../../../ulisp/Makefile) (変更)
  - 標準ランタイム（`ULISP_RUNTIME_LIBS`）に常時結合することなく、独立テストとしてコンパイル・実行する `make test_arena` ターゲットの追加

---

## 6. 実装方針 / Implementation Plan

Target Branch: `feat/630-process-local-ephemeral-arena`

### Step 1: 定数およびデータ構造（`<arena-chunk>`, `<task-arena>`）の定義 (`ulisp/runtime/concurrency/arena.scm`)
1. **基本パラメータ定数の定義**:
   - `*arena-min-capacity*`: `2048` (2KB: 最小初期容量)
   - `*arena-default-capacity*`: `4096` (4KB: 標準初期容量)
   - `*arena-max-initial-capacity*`: `8192` (8KB: 標準初期上限)
   - `*arena-overflow-chunk-size*`: `8192` (8KB: 枯渇時拡張チャンク標準サイズ)
   - `*arena-default-align*`: `8` (8 バイト境界アライメント)
   - `*arena-max-chunks*`: `64` (最大拡張チャンク数＝512KB フェイルセーフ上限)
   - `*arena-max-alloc-size*`: `1048576` (単一アロケーション最大安全上限 1MB)
2. **拡張チャンクレコード `<arena-chunk>`**:
   ```scheme
   (define-record-type <arena-chunk>
     (make-arena-chunk base offset capacity buffer next)
     arena-chunk?
     (base     arena-chunk-base)
     (offset   arena-chunk-offset   arena-chunk-offset-set!)
     (capacity arena-chunk-capacity)
     (buffer   arena-chunk-buffer)
     (next     arena-chunk-next     arena-chunk-next-set!))
   ```
3. **タスクアリーナ本体レコード `<task-arena>`**:
   - DSN-37 第 5.2 節の仕様 `(make-task-arena [initial-capacity [base-addr]])` およびアクセサ `task-arena?`, `arena-base`, `arena-offset`, `arena-offset-set!`, `arena-capacity`, `arena-capacity-set!` を完全提供しつつ、チャンク連鎖リストと可観測性カウンタを保持する：
   ```scheme
   (define-record-type <task-arena>
     (%make-task-arena base offset capacity buffer chunks chunk-count max-chunks total-allocated reset-count)
     task-arena?
     (base            arena-base            arena-base-set!)
     (offset          arena-offset          arena-offset-set!)
     (capacity        arena-capacity        arena-capacity-set!)
     (buffer          arena-buffer          arena-buffer-set!)
     (chunks          arena-chunks          arena-chunks-set!)
     (chunk-count     arena-chunk-count     arena-chunk-count-set!)
     (max-chunks      arena-max-chunks      arena-max-chunks-set!)
     (total-allocated arena-total-allocated arena-total-allocated-set!)
     (reset-count     arena-reset-count     arena-reset-count-set!))
   ```
   - コンストラクタ `make-task-arena` は以下の呼び出し形式をすべてサポートする（後方互換・DSN-37 スニペット互換）：
     - `(make-task-arena)`: デフォルト容量（4096 バイト）、8 バイト境界ベースアドレスで初期化。
     - `(make-task-arena initial-capacity)`: 指定容量（8 バイト境界へ切り上げ）で初期化。
     - `(make-task-arena base offset capacity)`: DSN-37 第 5.2 節の 3 引数コンストラクタ形式 `(make-task-arena base offset capacity)` でも直接生成可能にする。

### Step 2: 8 バイト境界アライメントと高速バンプ割り当て (`arena-allocate!`)
1. **ビット演算・アライメントヘルパー**:
   - 2 の補数表現における `(bitwise-not x)`（`= (- -1 x)`）および `(arena-align-up size align)` を定義：
   ```scheme
   (define (bitwise-not x) (- -1 x))

   (define (arena-align-up size align)
     (let ((mask (- align 1)))
       (bitwise-and (+ size mask) (bitwise-not mask))))
   ```
2. **高速バンプ割り当て (`arena-allocate!`)**:
   - `(arena-allocate! arena size [align])`（`align` 省略時は `8`）：
   - 入力検証：`size <= 0` または `size > *arena-max-alloc-size*` の場合はエラーを送出。`align` が 8 未満の場合は 8 に正規化。
   - `aligned-size` を `(bitwise-and (+ size (- align 1)) (bitwise-not (- align 1)))` で算出。
   - **Fast Path ($O(1)$)**:
     - チャンク連鎖が未使用（`(null? (arena-chunks arena))`）かつ `(+ (arena-offset arena) aligned-size) <= (arena-capacity arena)` の場合：
     - `current-off` を取得し、`(arena-offset-set! arena (+ current-off aligned-size))` を実行。
     - `(+ (arena-base arena) current-off)` を返却（厳密に 8 バイト境界のアドレス）。
   - **Slow Path (`arena-overflow-fallback!`)**:
     - プライマリ容量を超過した場合、`arena-overflow-fallback!` を呼び出す。

### Step 3: アリーナ枯渇時のチャンク連鎖フォールバック (`arena-overflow-fallback!`)
1. 現在の先頭拡張チャンク（`(car (arena-chunks arena))`）に `aligned-size` 分の空きがある場合は、その拡張チャンクのオフセットをバンプしてアドレスを返却。
2. 空きがない場合（または初回オーバーフロー時）：
   - `(>= (arena-chunk-count arena) (arena-max-chunks arena))` であれば、メモリ枯渇保護（CWE-400 防御）としてエラーを送出。
   - 新規チャンクサイズ `chunk-cap` を `(max *arena-overflow-chunk-size* aligned-size)` として決定。
   - 新規チャンクのベースアドレスを既存の最終アドレス空間と重複しない 8 バイト境界アドレス（`(+ (arena-base arena) (* (+ (arena-chunk-count arena) 1) 65536))` 等、または実アドレス）に設定し、`<arena-chunk>` を生成して `arena-chunks` リスト先頭へ cons 連結。
   - `chunk-count` を `+1` し、新チャンクの先頭アドレスを返却。

### Step 4: $O(1)$ 瞬時全破棄 (`arena-reset!`) とセキュア消去 (`arena-secure-reset!`)
1. **`(arena-reset! arena)`**:
   - `(arena-offset-set! arena 0)`
   - `(arena-chunks-set! arena '())`
   - `(arena-chunk-count-set! arena 0)`
   - `(arena-reset-count-set! arena (+ (arena-reset-count arena) 1))`
   - これにより、プライマリ領域のオフセット巻き戻しと拡張チャンク連鎖の切り離しがポインタ操作のみの $O(1)$ で完了し、チャンクに紐づくバッファは次回の再利用または回収に委ねられる。
2. **`(arena-secure-reset! arena)`**:
   - プライマリ `buffer` の `[0, offset)` 範囲、および各拡張チャンク `buffer` の `[0, chunk-offset)` 範囲を `bytevector-u8-set!` で `0` クリアした上で `(arena-reset! arena)` を呼び出す。

### Step 5: Dual-Mode モジュールロード規約の整備 (`010_library.scm`, `arena.sld`)
1. **標準ランタイム非汚染の維持**:
   - `ulisp/stdlib_entry.scm` および `ULISP_RUNTIME_LIBS` には `arena.scm` を常時バンドルせず、オンデマンド読み込みとする（DSN-37 第 13.4 節準拠）。
2. **`include` / `load` / `import` の 3 層対応**:
   - 正典構文 `(include "ulisp/runtime/concurrency/arena.scm")` に加え、`ulisp/frontend/010_library.scm` の `include-form?` および `find-included-file` を拡張し、トップレベルの定数文字列 `(load "ulisp/runtime/concurrency/arena.scm")` も AOT コンパイル時に静的展開可能にする。また、作業ディレクトリがプロジェクトルートであっても `ulisp/` サブディレクトリであっても `"ulisp/runtime/..."` と `"runtime/..."` の双方を透過的に解決する。
   - 名前空間カプセル化用の R7RS ライブラリ定義 `ulisp/lib/ulisp/concurrency/arena.sld`（`(define-library (ulisp concurrency arena) ...)`）を提供する。

### Step 6: 単体テスト・100 万回耐久リーク検証スイートの実装 (`tests/concurrency/test_arena.scm`)
1. **基本機能・アライメント検証**:
   - 初期容量（2KB, 4KB, 8KB）での生成と `task-arena?` 述語検証。
   - 非アラインサイズ（1, 3, 5, 7, 9, 13, 15, 17, 24 バイト等）を連続確保した際、返却される全アドレスが `(= (modulo addr 8) 0)`（8 バイト境界）を満たし、かつ領域が重複しないことを検証。
   - 16 バイトおよび 64 バイト（キャッシュライン境界）指定時のカスタムアライメント検証。
2. **メモリアクセス・データ保持整合性検証**:
   - 確保したアドレスに対して `arena-u8-set!` / `arena-u64-set!` で値を書き込み、`arena-u8-ref` / `arena-u64-ref` で正確に読み出せること（隣接領域への破壊がないこと）を検証。
3. **チャンク連鎖フォールバック検証**:
   - 2KB（2048 バイト）アリーナに対し、512 バイト × 10 回（計 5120 バイト）の割り当てを実行し、拡張チャンク（8KB）が自動的に連鎖確保され、`arena-chunk-count` が増加し、`arena-reset!` により `offset = 0`, `chunk-count = 0`, `chunks = '()` へ瞬時復帰することを検証。
4. **セキュリティ境界・異常系検証**:
   - サイズ `0`、負数 `-8`、上限超過サイズ、および `max-chunks` 超過時に適切にエラーが検出されることを検証。
   - `arena-secure-reset!` 実行後にバッファ内の旧データが `0` にクリアされていることを検証。
5. **100 万回アロケーション＆リセット耐久・メモリリーク 0 バイト検証**:
   - ループ内で `arena-allocate!` と `arena-reset!` を合計 1,000,000 回反復実行し、実行完了後の `arena-offset` が `0`、`arena-chunk-count` が `0`、アリーナの保留メモリ増加量（リーク）が厳密に `0` バイトであることを検証。

---

## 7. 完了条件 / Success Criteria (DoD)

- [x] `ulisp/runtime/concurrency/arena.scm` が実装され、`stdlib_entry.scm` を汚染せず `(include "ulisp/runtime/concurrency/arena.scm")` / `(load "ulisp/runtime/concurrency/arena.scm")` / `(import (ulisp concurrency arena))` によりオンデマンド利用できること
- [x] `<task-arena>`、`<arena-chunk>`、`make-task-arena`、`arena-allocate!`、`arena-reset!`、`arena-secure-reset!`、`arena-overflow-fallback!` が仕様通りに動作すること
- [x] `(arena-allocate! arena size)` が任意の正整数サイズに対して常に 8 バイト境界（$\text{addr} \equiv 0 \pmod 8$）のアドレスを返却すること
- [x] `(arena-reset! arena)` が $O(1)$ でオフセットを `0` にリセットし、拡張チャンク連鎖を一括解放すること
- [x] `(arena-secure-reset! arena)` が使用済みメモリ領域をゼロクリアした上でオフセットを `0` にリセットすること
- [x] `tests/concurrency/test_arena.scm` において、100 万回のアロケーションおよびリセット反復テストが PASS し、未解放領域（メモリリーク）が 0 バイトであること
- [x] `make format`、`make static_analysis`、`make test`（および S 式構文リンタ `lint_sexpr`）がすべてエラー 0 件で PASS すること
- [x] すべての内部リンクが相対パスリンク規約（`.agents/AGENTS.md` 第 7 項）に 100% 準拠していること

---

## 8. 実装結果と検証サマリー / Implementation Results

1. **Pure Scheme プロセスローカル・エフェメラルアリーナ実装 (`ulisp/runtime/concurrency/arena.scm`)**:
   - `<arena-chunk>` および `<task-arena>` を R7RS `define-record-type` で定義し、初期容量 2KB〜8KB（デフォルト 4KB）、8 バイト境界アライメント（任意の 2 の累乗 $\ge 8$ 指定にも対応）、8KB 拡張チャンク連鎖フォールバック `arena-overflow-fallback!`、$O(1)$ 瞬時全破棄 `arena-reset!`、および CWE-212 緩和のゼロクリア付き `arena-secure-reset!` を実装した。
   - CWE-190（整数オーバーフロー・不正サイズ検証）、CWE-400（最大チャンク数 `*arena-max-chunks*` 上限ガード）、CWE-787（割り当て範囲外メモリアクセス検証）の各セキュリティガードを組み込んだ。
2. **3 層モジュールロード規約の確立 (`ulisp/frontend/010_library.scm`, `ulisp/lib/ulisp/concurrency/arena.sld`)**:
   - DSN-37 第 13.4 節に基づき、`ulisp/stdlib_entry.scm` や `ULISP_RUNTIME_LIBS` に常時バンドルせず、① `(include "ulisp/runtime/concurrency/arena.scm")`、② トップレベル `(load "ulisp/runtime/concurrency/arena.scm")`、③ R7RS ライブラリ `(import (ulisp concurrency arena))` の 3 通りすべてで uLisp からオンデマンド読み込み可能にした。
3. **100 万回アロケーション耐久・リーク 0 バイト検証 (`tests/concurrency/test_arena.scm`)**:
   - `make -C ulisp test_arena` により、10,000 サイクル × 100 回（計 1,000,000 回、累計 24,000,000 バイト）の連続バンプ割り当てと $O(1)$ リセットを実行し、残留オフセット 0 バイト・残留チャンク 0 個・メモリリーク 0 バイトを検証した。
