---
ID: 735
種別: Bug
優先度: Medium
ステータス: Closed
---

# [BUG/SEC] Supervisor 子タスク起動引数の保持と再起動時のディープコピー機構の実装 (ID: 735)

## 1. 概要 / Summary
現在、`<child-spec>` は無引数の `start-thunk` しか保持しておらず、子タスクを再起動する際に起動引数をディープコピーして渡す仕組みがない（項目 C2）。そのため、起動クロージャが可変オブジェクト（リスト・ベクタ等）を共有していると、クラッシュ前の破壊された状態が再起動後の子タスクに引き継がれてしまう。`<child-spec>` で起動引数を保持し、子を再起動するたびに引数をディープコピーして渡すように改修する。

### 再現手順 / Steps to Reproduce
1. 可変ベクタやペアを捕捉した `start-thunk` で `<child-spec>` を作成する。
2. 子タスクがその可変データを書き換えた後にクラッシュし、Supervisor によって再起動される。
3. 再起動された子タスクが初期状態ではなく書き換え後の汚染されたデータを参照してしまう。

### 再現環境 / Environment
- OS / Env: Linux (x86-64 / AArch64 / Portable C99)
- File: `ulisp/runtime/concurrency/supervisor.scm`, `ulisp/lib/ulisp/concurrency/supervisor.sld`

---

## 2. セキュリティ脅威・脆弱性分析 / Security Threat Analysis
- **CWE-416 / CWE-843**: 残存可変状態の再利用 (Re-use of Mutated State after Failure / Type Confusion)
  - クラッシュした子プロセスがメモリ上の可変データ構造（ベクタやハッシュテーブル、境界バッファ）を一部破壊した状態で Supervisor が同じオブジェクト参照を用いて子タスクを再起動した場合、再起動されたタスクは汚染された状態から実行を再開し、不整合や二次クラッシュ、状態ポイズニング攻撃を招く。
- **CWE-400**: 制御不能なリソース消費 (Cascading Supervisor Crash Due to Poisoned State)
  - 不正データが再起動のたびに引き継がれることで、再起動上限回数（`max-restarts`）に瞬時に達し、Supervisor ツリー全体が連鎖停止するサービス拒否（DoS）につながる。

---

## 3. トレーサビリティ / Traceability
- 設計書: [DSN-37 Synapse Dual-Plane Concurrent Runtime Architecture](../designs/DSN-37-synapse_dual_plane_concurrent_runtime_architecture.md) (Supervisor & Failure Isolation)
- 関連モジュール: `ulisp/runtime/concurrency/supervisor.scm`, `ulisp/lib/ulisp/concurrency/supervisor.sld`
- テスト: `tests/concurrency/test_supervisor.scm` (Group 11: Deep copy of child init-args)

---

## 4. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [supervisor.scm](../../ulisp/runtime/concurrency/supervisor.scm)
- [x] [supervisor.sld](../../ulisp/lib/ulisp/concurrency/supervisor.sld)
- [x] [eval_adapter.scm](../../ulisp/runtime/concurrency/eval_adapter.scm)
- [x] [test_supervisor.scm](../../tests/concurrency/test_supervisor.scm)

---

## 5. 根本原因分析 (RCA) / Root Cause Analysis
`<child-spec>` が無引数の `start-thunk` のみを保持する簡易設計になっており、初期引数リストの保持フィールドおよび、起動・再起動ごとの `channel-deep-copy` によるイミュータブルな独立コピー生成処理が実装されていなかった。そのため、子タスクが自身の引数を破壊的に変更した後に異常終了した場合、Supervisor による再起動時にも同じ汚染オブジェクトが渡されていた。

---

## 6. 暫定対処と恒久対策 / Workaround & Permanent Fix
* **暫定対処 (Workaround)**: ユーザーコード側で `start-thunk` の内部で毎回明示的にコピーを作成する。
* **恒久対策 (Permanent Fix)**: `<child-spec>` に初期引数（`init-args`）を保持できるようにし、`make-child-spec` でオプショナル引数として受け付ける。`%spawn-and-monitor-child!` で子タスクを起動・再起動するたびに引数を `channel-deep-copy` でディープコピーして呼び出す。

---

## 7. 実装方針 / Implementation Plan
Target Branch: `fix/735-supervisor-deep-copy-child-args`

1. `<child-spec>` に初期引数リスト `init-args` を保持するフィールドとアクセサ `child-spec-init-args`、および `make-child-spec` への arity / 引数拡張を追加する。
2. `%spawn-and-monitor-child!` で子タスクを起動・再起動する際、保持している初期引数を `(channel-deep-copy args)` でクローンしてから起動手続きに適用する。
3. `test_supervisor.scm` に Group 11 を追加し、可変ベクタを引数に受け取る子タスクがクラッシュした際、再起動後の子タスクに初期状態のベクタが確実に渡されることを検証する。

---

## 8. 完了条件 / Success Criteria (DoD)
- [x] 子タスクが起動引数の複合データを変更した後にクラッシュ・再起動しても、再起動後の子タスクにはクリーンなディープコピー済みの初期引数が渡されること。
- [x] `make -C ulisp test_supervisor` が 100% PASS (68 assertions) すること。
- [x] `make format`, `make static_analysis`, `make test` がすべて PASS すること。

