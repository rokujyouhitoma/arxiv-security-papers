---
title: "[FEAT] System V AMD64 Callee-saved 極小スタック・ネイティブコンテキストスイッチの実装 (ID: 634)"
ステータス: Closed (Completed 2026-10-31)
優先度: High (P1)
担当エージェント:
  - Project Manager (PM) (Chair / Governance)
  - IT Specialist (Programming Languages & Compilers / PLC)
  - Software Development (SWD)
  - Systems Architect
  - Embedded Systems Specialist
  - Information Security Specialist
  - Software Quality Assurance Specialist
作成日: 2026-10-31
更新日: 2026-10-31
---

# Issue #634: [FEAT] System V AMD64 Callee-saved 極小スタック・ネイティブコンテキストスイッチの実装

## 1. 概要 (Summary)

[DSN-37: Synapse Dual-Plane Concurrent Runtime Architecture](../../designs/DSN-37-synapse_dual_plane_concurrent_runtime_architecture.md)（第 5 章「メモリモデル」、第 7.3 節「極小スタック・コルーチンコンテキストスイッチ」、第 13.4 節「並行ランタイムモジュールのロード設計」、および第 14.4 節 Phase 2 Task 2.1）に基づき、x86-64 System V AMD64 ABI に準拠した**超軽量（15 命令）ネイティブコンテキストスイッチルーチン (`swap_context`)** および **極小タスクスタック管理機構 (`4KB〜16KB`)** を実装した。

アフィン部分言語コア（ASC）内のマイクロタスクは `call/cc` による任意時点のスタック丸ごとコピーを排除しているため、各タスクは `mmap`（またはタスクアリーナ）で確保された 4KB〜16KB の独立した極小スタックを保持し、System V AMD64 ABI の Callee-saved レジスタ（`rbp`, `rbx`, `r12`, `r13`, `r14`, `r15`）とスタックポインタ（`rsp`）の交換のみで数ナノ秒でコンテキストを切り替えることができる。

先行する [Issue #630](630-implement-synapse-task-independent-bump-arena.md)・[Issue #631](631-implement-synapse-low-level-atomic-primitives.md)・[Issue #632](632-implement-synapse-michael-scott-lockfree-queue.md)・[Issue #633](633-implement-synapse-first-class-p2p-channel.md) と同様、**uLisp 専用スコープ**（`ilisp/` への組み込みや `tests/ilisp/` でのテストは行わない）および [DSN-37 セクション 13.4](../../designs/DSN-37-synapse_dual_plane_concurrent_runtime_architecture.md) の**オンデマンド・モジュールロード設計**（コアランタイムにはバンドルせず、`include` / `load` / `import` の 3 方式で利用可能）を厳格に遵守した。

---

## 2. ガバナンス・専門エージェント多角レビュー (Governance & Multi-Agent Reviews)

1. **Project Manager (PM) [Chair]**:
   - DSN-37 Phase 2（M:N スケジューラ & 強プリエンプション）の最初のマイルストーン（Task 2.1）。後続の [Issue #635: 分散 M:N ワークスティーリングスケジューラ (`scheduler.scm`)](../635-implement-synapse-work-stealing-scheduler.md) および [Issue #636: リダクション方式セーフポイント注入とプリエンプション機構](../636-implement-synapse-fuel-preemption-mechanism.md) がタスク実行を切り替える直接の基盤となる。スコープは uLisp（`ulisp/`）および `tests/concurrency/` に限定する。
2. **IT Specialist (Programming Languages & Compilers / PLC)**:
   - x86-64 System V ABI のスタックアライメント規約（`call` 命令直前で `rsp % 16 == 0`、関数エントリ直後で `rsp % 16 == 8`）と、uLisp ネイティブバックエンドの大域ヒープポインタレジスタ（`%r12`）および GC スタック底境界（`stack_bottom`）の整合性を保証する。
   - 生の `swap_context(old_sp_ptr, new_sp)` は System V ABI 通りに `rbp`, `rbx`, `r12`, `r13`, `r14`, `r15` の全 6 個の Callee-saved レジスタを退避・復元する 15 命令ルーチンとし、Scheme タスク間切り替えラッパー（`ulisp_swap_context`）では呼び出し元の最新ヒープポインタ `%r12` をスクラッチレジスタ `%r11` 経由で引き継ぐことで、タスク切り替え後のヒープポインタ巻き戻りを完全に防止する。
3. **Software Development (SWD)**:
   - `ulisp/runtime/concurrency/context.s` にアセンブラ実装を配置するとともに、`ulisp/backend/142_backend_x86_freestanding.scm` にも `.weak` シンボルとして同一ルーチンを出力することで、`as` / `ld` で `context.o` を明示リンクする場合と、単一 `.s` ファイルから直接アセンブル・リンクする場合の双方でシームレスに動作させる。
4. **Systems Architect**:
   - [Issue #633](633-implement-synapse-first-class-p2p-channel.md) で定義した `<task-context>` の `stack-pointer` / `continuation-pc` スロットと連携可能な `<execution-context>`（または `<task-stack>`）データ構造を提供し、コルーチンの初期起動・途中 `context-yield!`・正常終了復帰（Exit Trampoline）を一貫して管理する。
5. **Embedded Systems Specialist**:
   - デフォルトスタックサイズを 8KB（`8192` bytes、最小 4KB = `4096` bytes〜最大 64KB = `65536` bytes）とし、スタック下限（低位アドレス端）に 64-bit スタックカナリア（`0xDEADCAFEBEEF1337`）を書き込んでスタックオーバーフローを検知可能にする。
6. **Information Security Specialist**:
   - スタックオーバーフローによる隣接メモリ破壊（CWE-787）、16 バイト境界違反による SSE/システムコール命令フォルト（CWE-665）、終了済みスタックへの再スイッチや解放済みスタックの二重解放（CWE-416 / CWE-415）、および不正オブジェクト渡しによる型混同（CWE-843）への緩和策を実装する。
7. **Software Quality Assurance Specialist**:
   - ① 2 つのタスク間での往復コンテキストスイッチによる全 Callee-saved レジスタ（`rbp`, `rbx`, `r12`, `r13`, `r14`, `r15`）の不変性検証、② System V ABI 16 バイトスタックアライメント検証、③ Scheme コルーチンタスク間の交互実行（ピンポン yield）とヒープアロケーション整合性検証、④ スタックカナリア健全性検証、⑤ **1,000 万回（10,000,000 回）の連続コンテキストスイッチ耐久テスト**を網羅する `tests/concurrency/test_context_switch.scm` を策定する。
8. **Network Specialist**:
   - [Issue #633](633-implement-synapse-first-class-p2p-channel.md) のチャネル送受信で `'waiting-channel` にサスペンドしたタスクが、即座に `context-switch!` でスケジューラ／次タスクへ CPU を明け渡せることを確認する。
9. **Database / Data Infrastructure Specialist**:
   - 非同期 I/O 待ちやロックフリーキュー待機時の軽量コンテキスト切り替えとして、OS スレッド切り替え（数マイクロ秒）の 100 分の 1 以下のオーバーヘッドで動作することを確認する。
10. **IT Specialist (NLP & Info Retrieval)**:
    - ストリーミング字句解析・トークナイザコルーチンとして、プロデューサ・コンシューマ間で状態を保持したまま `context-yield!` できることを確認する。
11. **IT Strategist**:
    - Go の `gobuf` / `gogo` や Boost.Context (`jump_fcontext`) に匹敵する極小コンテキストスイッチ基盤を Zero-libc Freestanding x86-64 環境で確立する。
12. **IT Service Manager**:
    - 累計コンテキストスイッチ回数やスタック使用量・カナリア状態を検査できる統計・診断 API（`context-stats`, `task-stack-check-canary`）を提供する。
13. **Systems Auditor**:
    - すべてのドキュメント内リンクが相対パスで記述されていること（絶対パス 0 件）および `ilisp/` 非変更制約を監査する。
14. **UI/UX & Documentation Designer**:
    - `(import (ulisp concurrency context))`、`(load "ulisp/runtime/concurrency/context.scm")`、`(include "ulisp/runtime/concurrency/context.scm")` の 3 層インターフェースを整える。
15. **Education Specialist**:
    - Callee-saved レジスタ退避による極小スタック切り替えのアーキテクチャ解説と ASCII 図解を仕様ドキュメントに記載する。
16. **Application Specialist (APS)**:
    - Web / API ゲートウェイやストリーミング処理におけるタスク切り替えの低遅延性を保証する。

---

## 3. 現状分析と課題 (Current State & Challenges)

1. **現状 (Status Quo)**:
   - DSN-37 Phase 1 では、プロセス局所アリーナ（Issue #630）、低レベルアトミック（Issue #631）、M&S ロックフリーキュー（Issue #632）、およびリニア所有権チャネル（Issue #633）が完成した。
   - しかし、タスクの実行コンテキスト自体は Scheme の継続（`call/cc`）または単一スタック上での関数呼び出しに依存しており、タスクの途中中断・再開時に OS スレッドを生成することなくスタック状態を完全保持したまま切り替えるネイティブ機構が存在しない。
2. **課題 (Challenges)**:
   - `call/cc` は現在の全スタックフレームをヒープに丸ごとディープコピーするため、マイクロタスクが数千〜数万個にスケールした際にヒープ消費と GC 圧力が爆発する。
   - x86-64 System V AMD64 ABI では関数呼び出し時に `rsp % 16 == 0`（エントリ直後で `rsp % 16 == 8`）という厳格なアライメントが要求され、これに違反すると SSE 命令（`movaps` 等）や glibc/musl/kernel 呼び出しで即座に一般保護例外（SIGSEGV / SIGBUS）が発生する。
   - uLisp のネイティブコード生成器（`140_backend_x86_64.scm`）は大域ヒープポインタとしてレジスタ `%r12` を使用している。純粋な `swap_context` は Callee-saved レジスタとして `%r12` を保存・復元するが、タスク A からタスク B へ切り替えた後、タスク B がヒープ確保を行い、再度タスク A へ戻った際に、タスク A の古い `%r12` が復元されるとヒープアロケーション境界が巻き戻ってしまう。そのため、コンテキストスイッチ境界で最新のヒープポインタを Caller-saved レジスタ経由で引き継ぐ必要がある。

---

## 4. アーキテクチャと設計 (Architecture & Design)

### 4.1 System V AMD64 15 命令 `swap_context`

```assembly
# swap_context(uint64_t *old_sp_ptr, uint64_t new_sp)
# rdi = old_sp_ptr
# rsi = new_sp
.globl swap_context
.type swap_context, @function
.p2align 4
swap_context:
    push rbp
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov [rdi], rsp
    mov rsp, rsi
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret
```

### 4.2 極小タスクスタック（4KB〜16KB）とフレームレイアウト

```
+-------------------------------------------------------------+ High Address (top)
| Guard / Canary / Context Metadata (TCB Header: 64 bytes)    |
| [top - 8]  : exit_trampoline (タスク終了時の復帰先)         |
| [top - 16] : entry_rip (ulisp_task_entry_trampoline)        |
| [top - 24] : initial rbp (0)                                |
| [top - 32] : initial rbx (タスク引数 / クロージャ)          |
| [top - 40] : initial r12 (最新 heap_ptr)                   |
| [top - 48] : initial r13 (0)                                |
| [top - 56] : initial r14 (0)                                |
| [top - 64] : initial r15 (0)  <-- initial_sp (16B aligned)  |
+-------------------------------------------------------------+
|                                                             |
|                   実行時スタック領域 (4KB〜16KB)            |
|                           |                                 |
|                           v (スタック成長方向: 低位アドレス)|
|                                                             |
+-------------------------------------------------------------+
| [base + 0] : 64-bit スタックカナリア (0xDEADCAFEBEEF1337)   | Low Address (base)
+-------------------------------------------------------------+
```

---

## 5. セキュリティ・品質保証分析 (Security & QA Analysis)

| 脅威 / リスク | CWE | 影響 | 対策 |
| :--- | :--- | :--- | :--- |
| **スタックオーバーフローによる隣接破壊** | CWE-787 | ヒープや隣接タスクのメモリ破壊 | スタック下限に 64-bit カナリア（`0xDEADCAFEBEEF1337`）を配置し、切り替え・復帰時に `task-stack-check-canary` で即座に検知・パニック中断 |
| **16 バイトスタックアライメント不整合** | CWE-665 | SSE 命令フォルト、未定義動作 | `setup-task-stack` で `top & ~15` から 64 バイト（8 スロット）を配置し、`swap_context` の `ret` 直後の `rsp % 16 == 8` を機械語レベルで数学的に保証 |
| **終了済み・解放済みスタックへの再突入** | CWE-416 | Use-After-Free、スタック破壊 | `<task-stack>` に `freed?` フラグを保持し、解放済みスタックへの切り替えを防御。終了タスクは Exit Trampoline で状態を `'terminated` に更新 |
| **不正オブジェクト渡しによる型混同** | CWE-843 | 不正メモリアクセス、SEGV | `task-stack?` および `coroutine-context?` 型ガードで非適合引数を事前拒絶 |

---

## 6. 実装ステップ (Implementation Steps)

### Step 1: x86-64 アセンブラ実装 (`ulisp/runtime/concurrency/context.s`)
- 15 命令の正規 `swap_context(old_sp_ptr, new_sp)` を実装。
- `ulisp_task_entry_trampoline` および `ulisp_task_exit_trampoline` を実装。
- `%r12` 大域ヒープバンプポインタを `%r11` 経由で退避・復帰し、GC の `stack_bottom` もタスクスタック範囲に同期。
- `swap_context` の全 Callee-saved レジスタ保存・復元検証ルーチンおよび 1,000 万回連続耐久ベンチマークルーチンを実装。

### Step 2: Scheme コンテキスト管理 API の実装 (`ulisp/runtime/concurrency/context.scm` & `context.sld`)
- `<task-stack>` レコード（`make-task-stack`, `free-task-stack!`, `task-stack-check-canary`, `setup-task-stack`）。
- `<coroutine-context>` レコードと高水準切り替え API（`make-coroutine-context`, `context-switch!`, `context-yield!`, `context-resume!`）。
- R7RS ライブラリ定義 `(ulisp concurrency context)`。

### Step 3: 単体・耐久テストスイート (`tests/concurrency/test_context_switch.scm`) の作成
- Group 1: `<task-stack>` の生成・解放・サイズ境界検証・16 バイトアライメント・スタックカナリア検査。
- Group 2: `setup-task-stack` による初期スタックフレーム構築・16 バイト境界検証。
- Group 3: `swap_context` における System V AMD64 全 Callee-saved レジスタ往復保存・復元検証および関数エントリ 16 バイトスタックアライメント検証。
- Group 4: Scheme コルーチンタスク（`make-coroutine-context`, `context-switch!`, `context-yield!`）による 2 タスク間の交互実行、タスク内ヒープアロケーションと `%r12` 整合性検証。
- Group 5: **10,000,000 回（1,000 万回）連続コンテキストスイッチ耐久テスト**（スタック破壊 0 件、SEGV 0 件、カナリア無傷）。
- Group 6: 型混同・不正スタックサイズ・解放済みスタック／終了済みコルーチン再突入・カナリア改ざん検知に対するセキュリティガード検証。

---

## 7. 完了条件 (Success Criteria / Definition of Done)

- [x] `ulisp/runtime/concurrency/context.s`, `ulisp/runtime/concurrency/context.scm`, `ulisp/lib/ulisp/concurrency/context.sld` が実装され、`include` / `load` / `import` の 3 方式すべてでオンデマンドロード可能であること（コアランタイムにはバンドルしないこと）。
- [x] `swap_context` が System V AMD64 ABI に準拠し、2 つのタスク間でコンテキストスイッチを往復させて全 Callee-saved レジスタ（`rbp`, `rbx`, `r12`, `r13`, `r14`, `r15`）の値が一切改変されないこと。
- [x] `setup-task-stack` および `swap_context` において System V ABI の 16 バイトスタックアライメント規約が厳密に維持されること。
- [x] Scheme コルーチンタスク間での `context-switch!` / `context-yield!` 往復実行およびタスク内アロケーションが正常に動作すること。
- [x] **1,000 万回（10,000,000 回）の連続コンテキストスイッチ耐久テスト**でスタック破壊やセグメンテーションフォールトが 0 件であること。
- [x] ILisp (`ilisp/` および `tests/ilisp/`) には一切の変更を加えていないこと。
- [x] `tests/concurrency/test_context_switch.scm` の全テストケースがネイティブコンパイル実行 (`make -C ulisp test_context_switch`) で 100% PASS すること（61/61 passed）。
- [x] S 式構文・括弧バランス検査 (`make -C ulisp lint_sexpr`) および品質ゲート (`make format`, `make static_analysis`) がエラー 0 件で PASS すること。
- [x] ドキュメント内のすべてのリンクが相対パスで記述されており、絶対パス指定が 0 件であること。

