---
ID: 735
種別: Bug
優先度: Medium
ステータス: Open (New)
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
- File: `ulisp/runtime/concurrency/supervisor.scm`, `ulisp/runtime/concurrency/boundary.scm`

---

## 2. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [supervisor.scm](../../ulisp/runtime/concurrency/supervisor.scm)
- [ ] [boundary.scm](../../ulisp/runtime/concurrency/boundary.scm)
- [ ] [test_supervisor.scm](../../tests/concurrency/test_supervisor.scm)

---

## 3. 根本原因分析 (RCA) / Root Cause Analysis
- `<child-spec>` が `start-thunk` のみを保持する設計になっており、初期引数リストの保持と起動ごとの `sanitize-to-arena` / `channel-deep-copy` によるディープコピーが実装されていなかったため。

---

## 4. 暫定対処と恒久対策 / Workaround & Permanent Fix
* **暫定対処 (Workaround)**: `start-thunk` 内で毎回自分で `channel-deep-copy` を呼ぶ。
* **恒久対策 (Permanent Fix)**: `<child-spec>` に起動引数（`init-args`）を保持できるようにし、`%spawn-and-monitor-child!` で起動・再起動するたびに引数をディープコピーして渡す。

---

## 5. 実装方針 / Implementation Plan
Target Branch: `fix/735-supervisor-deep-copy-child-args`

1. `<child-spec>` に初期引数リスト `init-args` を保持するフィールドとコンストラクタ拡張を追加する。
2. `%spawn-and-monitor-child!` で子タスクを起動・再起動する際、保持している初期引数をディープコピー（子タスクの Arena または新規コピー）してから起動手続きに適用する。

---

## 6. 完了条件 / Success Criteria (DoD)
- [ ] 子タスクが起動引数の複合データを変更した後にクラッシュ・再起動しても、再起動後の子タスクにはクリーンなディープコピー済みの初期引数が渡されること。
- [ ] `make format`, `make static_analysis`, `make test` がすべて PASS すること。

