---
ID: 728
種別: Bug
優先度: High
ステータス: Closed
---

# [BUG/SEC] Supervisor 再起動頻度制限の時刻源を sys-clock-gettime-monotonic 単調増加クロックへ置換 (ID: 728)

## 1. 概要 / Summary
現在、`supervisor.scm` の再起動回数上限（MaxRestarts / MaxTime）のスライディングウィンドウ判定で使われている時計 `*supervisor-clock*` は、呼ばれるたびに固定値（`+10`）を加算するだけの人工カウンタになっている（項目 C4）。時計を OS の単調増加クロック `sys-clock-gettime-monotonic`（ミリ秒換算）に置き換え、実時間に基づいた正確な再起動頻度制限を実現する。

### 再現手順 / Steps to Reproduce
1. `supervisor.scm` の `allocate-supervisor-timestamp!` を確認すると、実時間に関係なく `(atomic-fetch-add! *supervisor-clock* 10)` を返している。
2. どれだけ長い時間を空けて再起動が発生しても、人工クロックが `+10` しか進まないため、`max-time` が大きいと過去の再起動履歴がウィンドウから外れず誤って上限超過になる。

### 再現環境 / Environment
- OS / Env: Linux (x86-64 / AArch64 / Portable C99)
- File: `ulisp/runtime/concurrency/supervisor.scm`, `ulisp/lib/posix.scm`

---

## 2. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [supervisor.scm](../../../ulisp/runtime/concurrency/supervisor.scm)
- [x] [posix.scm](../../../ulisp/lib/posix.scm)
- [x] [test_supervisor.scm](../../../tests/concurrency/test_supervisor.scm)

---

## 3. 根本原因分析 (RCA) / Root Cause Analysis
- 初期実装時に単体テスト容易性のために導入したダミーの論理カウンタ `*supervisor-clock*`（呼び出しごとに `+10` 加算）がそのまま本番の時刻源として使われ続けていたため。
- また、`posix.scm` の `sys-clock-gettime-monotonic` がグローバル共有ペア `*posix-timespec-cell*` をそのままバッファとして使っており、マルチスレッド環境での競合や GC 追跡時の安全性に課題があったため。

---

## 4. 暫定対処と恒久対策 / Workaround & Permanent Fix
* **暫定対処 (Workaround)**: `supervisor-clock-advance!` を手動で呼び出して時刻を進める。
* **恒久対策 (Permanent Fix)**:
  1. `posix.scm` の `sys-clock-gettime-monotonic` / `sys-clock-gettime-realtime` を呼び出しごとに局所ペアを使用し読み取り後にタグ付き `0` へ戻すスレッドセーフ・GCセーフな実装にする。
  2. `supervisor.scm` の `supervisor-clock-now` および `allocate-supervisor-timestamp!` を `sys-clock-gettime-monotonic` から算出した単調増加ミリ秒 `(+ (* sec 1000) (quotient nsec 1000000))` と手動テストオフセット `*supervisor-clock-offset-ms*` の和を返すように置換する。

---

## 5. 実装方針 / Implementation Plan
Target Branch: `fix/728-supervisor-monotonic-clock`

1. `ulisp/lib/posix.scm` の `sys-clock-gettime-monotonic` / `sys-clock-gettime-realtime` をスレッドセーフ化する。
2. `ulisp/runtime/concurrency/supervisor.scm` の `supervisor-clock-now` と `allocate-supervisor-timestamp!` を `sys-clock-gettime-monotonic`（ミリ秒単位）＋ `*supervisor-clock-offset-ms*` に置き換え、人工的な `+10` カウンタ加算を廃止する。
3. `%record-restart-and-check-limit!` が実時間の単調増加クロック（および `supervisor-clock-advance!` によるオフセット）に基づいてスライディングウィンドウを評価することを確認する。
4. `tests/concurrency/test_supervisor.scm` に単調増加クロックおよび時間窓経過後の再起動許容を検証するテストを追加する。

---

## 6. 完了条件 / Success Criteria (DoD)
- [x] Supervisor の再起動スライディングウィンドウが `sys-clock-gettime-monotonic` の実時間に基づいて動作すること。
- [x] `make -C ulisp test_supervisor lint_sexpr` がすべて PASS すること。

