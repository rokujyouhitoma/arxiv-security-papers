---
title: "[FEAT] Scheme 低レベルアトミック命令 (atomic-cas! / atomic-box) の提供 (ID: 631)"
ステータス: Closed
優先度: High (P1)
担当エージェント:
  -Project Manager (PM) (Chair / Governance)
  -IT Specialist (Programming Languages & Compilers / PLC)
  -Software Development (SWD)
  -Systems Architect
  -Information Security Specialist
  -Software Quality Assurance Specialist
作成日: 2026-10-31
更新日: 2026-10-31
---

# Issue #631: [FEAT] Scheme 低レベルアトミック命令 (`atomic-cas!` / `atomic-box`) の提供

## 1. 概要 (Summary)

[DSN-37: Synapse Dual-Plane Concurrent Runtime Architecture](../../designs/DSN-37-synapse_dual_plane_concurrent_runtime_architecture.md)（Phase 0 / Task 0.2）に基づき、uLisp ランタイムおよび AOT/JIT コンパイラ（x86-64 ネイティブバックエンドおよび C バックエンド）において、ミューテックス等の OS ロックを一切介さず CPU ハードウェアの Compare-And-Swap (`LOCK CMPXCHG`) およびメモリバリア (`MFENCE`) 命令へ直接展開される低レベルアトミックプリミティブおよび `<atomic-box>` 抽象データ型を実装する。

本機能は、後続の Phase 0 Task 0.3（[Issue #632: Michael-Scott ノンブロッキング・ロックフリーキュー](../632-implement-synapse-michael-scott-lockfree-queue.md)）、Phase 1（[Issue #633: 線形所有権移譲チャネルおよび有界バックプレッシャー機構](../633-implement-synapse-first-class-p2p-channel.md)）、Phase 2（[Issue #635: 分散 M:N ワークスティーリングスケジューラおよび Chase-Lev Deque](../635-implement-synapse-work-stealing-scheduler.md)）、Phase 6（[Issue #642: 世代管理型投機タスク破棄および待機タスク世代ゲート検証](../642-implement-synapse-epoch-fencing-distributed-rollback.md)）など、Synapse Dual-Plane 並行ランタイムのすべてのロックフリーデータ構造を支える最下層ハードウェア同期基盤となる。

また、[DSN-37 セクション 13.4](../../designs/DSN-37-synapse_dual_plane_concurrent_runtime_architecture.md) および先行完了した [Issue #630](630-implement-synapse-task-independent-bump-arena.md) と同様、**uLisp 専用スコープ**（ILisp への組み込み・テストは行わない）および**オンデマンド・モジュールロード設計**（コアランタイムを肥大化させず、`include` / `load` / `import` の 3 方式で利用可能）を厳格に遵守する。

---

## 2. ガバナンス・専門エージェント多角レビュー (Governance & Multi-Agent Reviews)

1. **Project Manager (PM) [Chair]**:
   - DSN-37 Phase 0 の 2 番目のマイルストーン（Task 0.2）。先行する [Issue #630](630-implement-synapse-task-independent-bump-arena.md)（Task 0.1）の完了を受け、後続の全ロックフリー構造（#632, #633, #635, #642）のブロッカーを解消するクリティカルパスとして位置付ける。スコープは uLisp コンパイラ・ランタイムおよび `tests/concurrency/` に限定する。
2. **IT Specialist (Programming Languages & Compilers / PLC)**:
   - uLisp の `define-record-type` は Pass 025 (`ulisp/frontend/025_top_level.scm`) によりベクタ（タグ `5` = `0b101`）へ展開され、スロット 0（オフセット `[ptr + 3]`）にレコード型タグシンボル、スロット 1（オフセット `[ptr + 11]`）に第 1 フィールド `val` が配置される。
   - LIR 3 引数プリミティブ `(%atomic-cas! box expected new)` を導入し、`140_backend_x86_64.scm` において `%rdx` (`box`), `%rax` (`expected`), `%rcx` (`new`) にレジスタ割り付けした上で、単一の `lock cmpxchgq %rcx, 11(%rdx)` 命令とゼロフラグ判定 `(%set-boolean %rax "sete")` にインライン展開する。さらに直列化バリア用の 0 引数プリミティブ `(%memory-fence)` (`mfence`) を提供する。
3. **Software Development (SWD)**:
   - 基本操作 (`make-atomic-box`, `atomic-box?`, `atomic-ref` / `atomic-box-ref`, `atomic-set!` / `atomic-box-set!`, `atomic-cas!`) に加え、実用的なロックフリーアルゴリズム構築に不可欠な派生アトミック操作 (`atomic-swap!`, `atomic-fetch-add!`, `atomic-update!`, `memory-fence`)、および ABA 問題を防止するバージョンスタンプ付きアトミックボックス (`<atomic-stamped-box>`: `make-atomic-stamped-box`, `atomic-stamped-box?`, `atomic-stamped-ref`, `atomic-stamped-cas!`) を `ulisp/runtime/concurrency/atomic.scm` に実装する。
4. **Systems Architect**:
   - DSN-37 セクション 6.1・6.2 では `atomic-box-ref` / `atomic-box-set!`、セクション 14.2 では `atomic-ref` / `atomic-set!` の双方が記述されているため、両方の命名を公式 API としてエクスポートし、設計書全章および後続 Issue との 100% 互換性を保証する。
5. **Information Security Specialist**:
   - 非アトミックボックスオブジェクト（整数、ペア、空ベクタ等）に対する `%atomic-cas!` 呼び出しによる任意メモリ破壊（CWE-843: Type Confusion / CWE-119: Out-of-Bounds Write）を防ぐため、パブリック関数 `atomic-cas!`, `atomic-ref`, `atomic-set!` 等で `atomic-box?` 型検査を強制する。
6. **Software Quality Assurance Specialist**:
   - CAS 成功（期待値一致時の値更新と `#t` 返却）、CAS 失敗（期待値不一致時の値不変と `#f` 返却）、ポインタ同一性 (`eq?`) 比較、Fixnum 加算 (`atomic-fetch-add!`)、関数リトライループ (`atomic-update!`)、ABA スタンプ付き CAS (`atomic-stamped-cas!`)、および不正型エラーハンドリングを網羅する自動テスト `tests/concurrency/test_atomic.scm` と Makefile ターゲット `test_atomic` を整備する。
7. **Database / Data Infrastructure Specialist**:
   - Phase 2 の ETS 共有メモリテーブル（Issue #635）におけるバケットヘッダのロックフリー更新およびシーケンスロック管理にそのまま適用可能な 64-bit ワード CAS セマンティクスを保証する。
8. **Network Specialist**:
   - 高頻度イベントループ（epoll / io_uring 完了通知リング）での状態フラグ遷移において、システムコールを伴わないユーザ空間数サイクルの `lock cmpxchgq` で完了することを確認する。
9. **IT Specialist (NLP & Info Retrieval)**:
   - 並列ドキュメントインデクサにおける共有ドキュメント ID カウンタとして `atomic-fetch-add!` がロックなしで安全に採番できる構造とする。
10. **IT Strategist**:
    - ハードウェア直結の `LOCK CMPXCHG` プリミティブを uLisp ネイティブコンパイラに備えることで、高級言語でありながら C/Rust と同等のロックフリー同期性能を実現する。
11. **IT Service Manager**:
    - 既存の `make -C ulisp check` / `make -C ulisp lint_sexpr` パイプラインに `test_atomic` を統合し、CI/CD 品質ゲートでの継続的検証を保証する。
12. **Embedded Systems Specialist**:
    - x86-64 バックエンド（`140_backend_x86_64.scm`）だけでなく C バックエンド（`160_backend_c.scm`）でも `__sync_bool_compare_and_swap` / `__sync_synchronize` を用いた等価なアトミック命令出力をサポートし、移植性を維持する。
13. **Systems Auditor**:
    - DSN-37、先行 Issue #630、後続 Issue #632〜#645 との双方向トレーサビリティと、ドキュメント内の相対パスリンク規約（絶対パスゼロ）を監査する。
14. **UI/UX & Documentation Designer**:
    - オンデマンドロードの 3 方式（`include` / `load` / `import`）および CAS ループのイディオムを明快なコード例付きでドキュメント化する。
15. **Education Specialist**:
    - ハードウェア CAS 命令のセマンティクス、メモリバリアの役割、および ABA 問題への対処法（Stamped Reference）が学習者にも直感的に理解できるようコメントと API を整備する。
16. **Application Specialist (APS)**:
    - アプリケーション層から `atomic-update!` や `atomic-fetch-add!` を使って、明示的な CAS ループを書かずに宣言的かつ安全に共有状態を更新できる高水準ユーティリティを提供する。

---

## 3. 脅威分析とセキュリティ要件 (Threat Modeling & Security Requirements)

| 脅威 ID | STRIDE 分類 | 対象 CWE | 脅威シナリオ | 緩和策・セキュリティ設計 |
| :--- | :--- | :--- | :--- | :--- |
| **TM-631-01** | Tampering / Elevation of Privilege | CWE-843 (Type Confusion)<br>CWE-787 (Out-of-Bounds Write) | `atomic-cas!` や `atomic-set!` に `<atomic-box>` 以外の値（Fixnum や長さ 1 以下のベクタ等）を渡すことで、オフセット `[ptr + 11]` の無関係なヒープ領域や不正アドレスをアトミックに書き換える。 | パブリック API (`atomic-ref`, `atomic-box-ref`, `atomic-set!`, `atomic-box-set!`, `atomic-cas!`, `atomic-swap!`, `atomic-fetch-add!`, `atomic-update!`) の入口で必ず `(atomic-box? box)` による実行時型検証を行い、違反時は安全に `error` を送出する。 |
| **TM-631-02** | Tampering | CWE-362 (Concurrent Execution using Shared Resource with Improper Synchronization) | ロード→比較→ストアを非アトミックな複数命令で実装した場合、マルチコア Worker スレッド間で TOCTOU レースが発生し、キューノードの消失や二重取得が起きる。 | コンパイラ LIR プリミティブ `%atomic-cas!` を x86-64 の単一ハードウェア命令 `lock cmpxchgq %rcx, 11(%rdx)`（C バックエンドでは `__sync_bool_compare_and_swap`）に直接コンパイルし、バスロック／キャッシュコヒーレンシプロトコルによる不可分性を保証する。 |
| **TM-631-03** | Tampering | CWE-416 (Use After Free / ABA Problem in Lock-Free Structures) | ロックフリースタックやキューにおいて、ポインタが `A -> B -> A` と再利用された際、単純なポインタ比較の CAS が誤って成功し、壊れたフリーリストや循環リストを生む。 | 基本の `<atomic-box>` に加え、単調増加する 64-bit バージョンスタンプ（世代番号）をペアで保持・検証する `<atomic-stamped-box>` (`atomic-stamped-cas!`) を標準提供し、ABA 問題を構造的に排除可能とする。 |
| **TM-631-04** | Information Disclosure / Denial of Service | CWE-820 (Missing Synchronization / Memory Ordering Violation) | ストアバッファリングにより、データ初期化の書き込みがポインタ公開より後に他コアへ可視化され、未初期化メモリを読み取る。 | `lock cmpxchgq` 自体が x86-64 TSO メモリモデル上でフルメモリバリアとして機能することに加え、明示的な直列化命令 `(%memory-fence)` (`mfence`) および高水準ラッパー `(memory-fence)` を提供し、ストア後のロード順序付け（Chase-Lev Deque 等で必須）を保証する。 |

---

## 4. トレーサビリティ (Traceability)

- **親設計ドキュメント**:
  - [DSN-37: Synapse Dual-Plane Concurrent Runtime Architecture](../../designs/DSN-37-synapse_dual_plane_concurrent_runtime_architecture.md)（セクション 6「Lock-Free Algorithms in Scheme」、セクション 13.4「並行ランタイムモジュールのロード設計」、セクション 14.2「Task 0.2: 低レベルアトミック命令の提供」）
- **関連アーキテクチャ設計書**:
  - [DSN-33: Self-Hosting Native Compiler Architecture](../../designs/DSN-33-self_hosting_native_compiler_architecture.md)
  - [DSN-36: Write-Barrier & Generational GC Architecture](../../designs/DSN-36-generational_gc_and_write_barrier_architecture.md)
- **先行 Issue (完了済)**:
  - [Issue #630: プロセスローカル・バンプアリーナ (Process-Local Ephemeral Bump Arena) と O(1) 一括リセットの実装](630-implement-synapse-task-independent-bump-arena.md)
- **後続・依存先 Issue**:
  - [Issue #632: Michael-Scott ノンブロッキング・ロックフリーキューの実装](../632-implement-synapse-michael-scott-lockfree-queue.md)
  - [Issue #633: 線形所有権移譲チャネルおよび有界バックプレッシャー機構の実装](../633-implement-synapse-first-class-p2p-channel.md)
  - [Issue #635: 分散 M:N ワークスティーリングスケジューラおよび Chase-Lev Deque の実装](../635-implement-synapse-work-stealing-scheduler.md)
  - [Issue #642: 世代管理型投機タスク破棄および待機タスク世代ゲート検証の実装](../642-implement-synapse-epoch-fencing-distributed-rollback.md)
  - [Issue #645: CI 向けマルチコア並行競合テストハーネス (concurrency_harness.scm) の実装](../645-implement-synapse-multicore-concurrency-ci-harness.md)

---

## 5. 影響範囲と関連ファイル (Scope and Affected Files)

> [!IMPORTANT]
> ユーザー指示および DSN-37 の方針に基づき、実装およびテストの対象は **uLisp のみ**（`ulisp/` および `tests/concurrency/`）とする。`ilisp/` への組み込みや `tests/ilisp/` でのテスト追加は一切行わない。また、`ulisp/stdlib_entry.scm` や `ULISP_RUNTIME_LIBS` にはバンドルせず、オンデマンドロード方式とする。

### 新規作成ファイル
- [`ulisp/runtime/concurrency/atomic.scm`](../../../ulisp/runtime/concurrency/atomic.scm):
  - `<atomic-box>` レコード定義およびアトミック操作 API 一式（`make-atomic-box`, `atomic-box?`, `atomic-ref`, `atomic-box-ref`, `atomic-set!`, `atomic-box-set!`, `atomic-cas!`, `atomic-swap!`, `atomic-fetch-add!`, `atomic-update!`, `memory-fence`）、および ABA 対策 `<atomic-stamped-box>` API 一式。
- [`ulisp/lib/ulisp/concurrency/atomic.sld`](../../../ulisp/lib/ulisp/concurrency/atomic.sld):
  - R7RS `(import (ulisp concurrency atomic))` 用のライブラリ定義ファイル。
- [`tests/concurrency/test_atomic.scm`](../../../tests/concurrency/test_atomic.scm):
  - `include` / `load` / `import` の各方式および全アトミックプリミティブ・CAS 境界条件・ABA スタンプ検証の単体テストスイート。

### 変更対象ファイル
- [`ulisp/compiler/primitives.scm`](../../../ulisp/compiler/primitives.scm):
  - `*primitives*` テーブルに `(%memory-fence 0)` および `(%atomic-cas! 3)` を登録。
- [`ulisp/frontend/020_macro_expander.scm`](../../../ulisp/frontend/020_macro_expander.scm):
  - マクロ展開器の既知プリミティブリストに `%memory-fence` および `%atomic-cas!` を登録。
- [`ulisp/lir/129_lir_primitives.scm`](../../../ulisp/lir/129_lir_primitives.scm):
  - 0 引数プリミティブ `%memory-fence`（`(%memory-fence)` LIR 命令の発行）および 3 引数プリミティブ `%atomic-cas!`（`box` を `%rdx`、`expected` を `%rax`、`new` を `%rcx` にロードし、`(%atomic-cas! %rax %rdx %rcx)` LIR 命令と世代別 GC ライトバリアを発行）のローワーリング処理を追加。
- [`ulisp/lir/lir_lang.scm`](../../../ulisp/lir/lir_lang.scm):
  - LIR 構文検証器（`valid-lir-inst?`）に `(%memory-fence)` および `(%atomic-cas! dst box new)` を追加。
- [`ulisp/backend/140_backend_x86_64.scm`](../../../ulisp/backend/140_backend_x86_64.scm):
  - x86-64 コード生成器に `(%memory-fence)` → `mfence`、および `(%atomic-cas! %rax %rdx %rcx)` → `lock cmpxchg qword ptr [rdx + 11], rcx` + `(%set-boolean %rax "sete")` のアセンブリ出力を追加。
- [`ulisp/backend/160_backend_c.scm`](../../../ulisp/backend/160_backend_c.scm):
  - C バックエンドコード生成器に `(%memory-fence)`（`__sync_synchronize()`）および `(%atomic-cas! ...)`（`__sync_bool_compare_and_swap`）の出力サポートを追加。
- [`ulisp/Makefile`](../../../ulisp/Makefile):
  - `test_atomic` ターゲットを追加し、`check` ターゲットから自動実行されるよう統合。

---

## 6. 実装方針 (Implementation Plan)

- **ターゲットブランチ**: `feat/631-atomic-primitives`

### Step 1: uLisp コンパイラ低レベルプリミティブ (`%atomic-cas!` / `%memory-fence`) の追加
1. **メモリレイアウトの確定**:
   - uLisp の `define-record-type` (`025_top_level.scm`) はレコードをベクタ `(vector '%%record-type-<atomic-box> val)` として生成する。
   - ベクタタグは `5` (`0b101`) であり、アロケーションベース `r12` に対してタグ付きポインタは `ptr = r12 + 13` となる。
   - `[r12 + 0]` (`[ptr - 13]`) が GC ヘッダ、`[r12 + 8]` (`[ptr - 5]`) がベクタ長、`[r12 + 16]` (`[ptr + 3]`) がスロット 0（レコード型タグ）、`[r12 + 24]` (`[ptr + 11]`) がスロット 1（`<atomic-box>` の `val` フィールド）である。
2. **フロントエンド & LIR ローワーリング (`primitives.scm`, `020_macro_expander.scm`, `129_lir_primitives.scm`, `lir_lang.scm`)**:
   - `(%memory-fence)` (0 引数): LIR 命令 `(%memory-fence)` を発行し、`%rax` に `#t` (`111`) を設定する。
   - `(%atomic-cas! box expected new)` (3 引数):
     - 第 1 引数 `box` を `%rdx`、第 2 引数 `expected` を `%rax`、第 3 引数 `new` を `%rcx` に配置する。
     - LIR 命令 `(%atomic-cas! %rax %rdx %rcx)` を発行する。
     - 世代別 GC モード時（`(not (eq? *backend-gc-mode* 'none))`）には、`vector-set!` と同様に `%rdx`（`box`）に対するライトバリア記録を行い、Old 世代の `<atomic-box>` が Young 世代オブジェクトを参照した場合のルート追跡漏れを防ぐ。
3. **x86-64 バックエンド & C バックエンド (`140_backend_x86_64.scm`, `160_backend_c.scm`)**:
   - `140_backend_x86_64.scm`:
     - `(%memory-fence)` → `(emit "    mfence")`
     - `(%atomic-cas! dst box new)` →
       - `(emit "    lock cmpxchgq ~a, 11(~a)" (reg->asm new) (reg->asm box))`
       - `(emit-inst (list '%set-boolean dst "sete"))`（CAS 成功時 `ZF=1` で `#t` = `111`、失敗時 `ZF=0` で `#f` = `47` を `%rax` にセット）
   - `160_backend_c.scm`:
     - `(%memory-fence)` → `__sync_synchronize();`
     - `(%atomic-cas! dst box new)` → `((uintptr_t)(__sync_bool_compare_and_swap((uintptr_t*)((char*)(uintptr_t)(box) + 11), (uintptr_t)( dst ), (uintptr_t)(new)) ? 111 : 47))`

### Step 2: `ulisp/runtime/concurrency/atomic.scm` および `.sld` の実装
1. **オンデマンドロード対応モジュール構造**:
   - [DSN-37 セクション 13.4](../../designs/DSN-37-synapse_dual_plane_concurrent_runtime_architecture.md) に従い、`ulisp/runtime/concurrency/atomic.scm` と `ulisp/lib/ulisp/concurrency/atomic.sld` を分離作成する。
2. **コア `<atomic-box>` プリミティブ**:
   - `(define-record-type <atomic-box> (%make-atomic-box val) atomic-box? (val %atomic-box-val %atomic-box-val-set!))`
   - `(make-atomic-box val)`: 初期値 `val` を持つ `<atomic-box>` を生成。
   - `(atomic-box? x)`: `<atomic-box>` 型の述語。
   - `(atomic-ref box)` / `(atomic-box-ref box)`: 型検査の上で現在の値をアトミックに読み取る。
   - `(atomic-set! box new-val)` / `(atomic-box-set! box new-val)`: 型検査の上で値を更新し、`(%memory-fence)` により可視性を保証する。
   - `(atomic-cas! box expected new-val)`: 型検査の上で `(%atomic-cas! box expected new-val)` を実行し、成功時は `#t`、失敗時は `#f` を返す。
3. **高水準ロックフリー派生操作**:
   - `(memory-fence)`: `(%memory-fence)` を実行するハードウェアメモリバリア関数。
   - `(atomic-swap! box new-val)`: CAS ループにより `box` の値を `new-val` にアトミックに置換し、**置換前の旧値**を返す。
   - `(atomic-fetch-add! box delta)`: CAS ループにより整数値を保持する `box` に `delta` をアトミックに加算し、**加算前の旧値**を返す。
   - `(atomic-update! box proc)`: CAS ループにより `(proc old-val)` の結果で `box` をアトミックに更新し、**更新後の新値**を返す。
4. **ABA 問題対策 `<atomic-stamped-box>`**:
   - 値 `val` と単調増加スタンプ `stamp` のペア `(cons val stamp)` を内部 `<atomic-box>` に保持（または専用レコードで管理）し、`(make-atomic-stamped-box val initial-stamp)`, `(atomic-stamped-box? x)`, `(atomic-stamped-ref sbox)`（`(cons val stamp)` または値の取得）, `(atomic-stamped-cas! sbox expected-val next-val expected-stamp next-stamp)` を提供する。

### Step 3: 単体テスト・品質ゲートの構築 (`tests/concurrency/test_atomic.scm`)
1. `tests/concurrency/test_atomic.scm` を作成し、以下のテストケースを網羅する：
   - `make-atomic-box`, `atomic-box?`, `atomic-ref` / `atomic-box-ref`, `atomic-set!` / `atomic-box-set!` の基本動作検証。
   - `atomic-cas!` の成功パス（期待値一致時の値更新と `#t` 返却）および失敗パス（期待値不一致時の値不変と `#f` 返却）。
   - シンボル・ペア・ベクタ等のヒープオブジェクトに対するポインタ同一性 (`eq?`) CAS と世代別 GC 共存時の安全性検証。
   - `atomic-swap!`, `atomic-fetch-add!`, `atomic-update!`, `memory-fence` の動作検証。
   - `<atomic-stamped-box>` による ABA シナリオ（値が `A -> B -> A` に戻ってもスタンプが異なれば `atomic-stamped-cas!` が `#f` で拒絶すること）の検証。
   - `include`, `load`, `import` の 3 方式でのロード互換性検証。
2. `ulisp/Makefile` に `test_atomic` を追加し、`make -C ulisp lint_sexpr` および `make -C ulisp test_atomic` がパスすることを確認する。

---

## 7. 完了条件 (Success Criteria / Definition of Done)

- [x] `ulisp/compiler/primitives.scm`, `020_macro_expander.scm`, `129_lir_primitives.scm`, `lir_lang.scm`, `140_backend_x86_64.scm`, `160_backend_c.scm` に `%atomic-cas!` および `%memory-fence` が実装され、x86-64 バックエンドで `lock cmpxchg qword ptr [rdx + 11], rcx` および `mfence` に直接インライン展開されること。
- [x] `ulisp/runtime/concurrency/atomic.scm` および `ulisp/lib/ulisp/concurrency/atomic.sld` が作成され、`include` / `load` / `import` の 3 方式すべてでオンデマンドロード可能であること（コアランタイムにはバンドルしないこと）。
- [x] `make-atomic-box`, `atomic-box?`, `atomic-ref`, `atomic-box-ref`, `atomic-set!`, `atomic-box-set!`, `atomic-cas!`, `atomic-swap!`, `atomic-fetch-add!`, `atomic-update!`, `memory-fence`, および `<atomic-stamped-box>` API 一式が実装されていること。
- [x] ILisp (`ilisp/` および `tests/ilisp/`) には一切の変更を加えていないこと。
- [x] `tests/concurrency/test_atomic.scm` の全テストケースがネイティブコンパイル実行 (`make -C ulisp test_atomic`) で 100% PASS すること。
- [x] S 式構文・括弧バランス検査 (`make -C ulisp lint_sexpr`) および品質ゲート (`make format`, `make static_analysis`) がエラー 0 件で PASS すること。
- [x] ドキュメント内のすべてのリンクが相対パスで記述されており、絶対パス指定が 0 件であること。
