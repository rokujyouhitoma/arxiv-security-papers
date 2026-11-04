---
ID: 728
種別: Bug
優先度: High
ステータス: Open (New)
---

# [BUG/SEC] Supervisor 再起動頻度制限の時刻源を sys-clock-gettime-monotonic 単調増加クロックへ置換 (ID: 728)

## 1. 概要 / Summary
現在、`supervisor.scm` の再起動回数上限（MaxRestarts / MaxTime）のスライディングウィンドウ判定で使われている時計 `*supervisor-clock*` は、呼ばれるたびに固定値（`+10`）を加算するだけの人工カウンタになっている（項目 C4）。時計を OS の単調増加クロック `sys-clock-gettime-monotonic` に置き換え、実時間に基づいた正確な再起動頻度制限を実現する。

### 再現手順 / Steps to Reproduce
1. `supervisor.scm` の `allocate-supervisor-timestamp!` を確認すると、実時間に関係なく `(atomic-fetch-add! *supervisor-clock* 10)` を返している。
2. どれだけ長い時間を空けて再起動が発生しても、人工クロックが `+10` しか進まないため、`max-time` が大きいと過去の再起動履歴がウィンドウから外れず誤って上限超過になる。

### 再現環境 / Environment
- OS / Env: Linux (x86-64 / AArch64 / Portable C99)
- File: `ulisp/runtime/concurrency/supervisor.scm`, `ulisp/lib/posix.scm`

---

## 2. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [supervisor.scm](../../ulisp/runtime/concurrency/supervisor.scm)
- [ ] [posix.scm](../../ulisp/lib/posix.scm)
- [ ] [test_supervisor.scm](../../tests/concurrency/test_supervisor.scm)

---

## 3. 根本原因分析 (RCA) / Root Cause Analysis
- 初期実装時に単体テスト容易性のために導入したダミーの論理カウンタ `*supervisor-clock*` がそのまま本番の時刻源として使われ続けていたため。

---

## 4. 暫定対処と恒久対策 / Workaround & Permanent Fix
* **暫定対処 (Workaround)**: `supervisor-clock-advance!` を手動で呼び出して時刻を進める。
* **恒久対策 (Permanent Fix)**: `supervisor-clock-now` のデフォルト時刻源を `sys-clock-gettime-monotonic` に置き換える（手動オフセット加算も併用可能にして既存テスト互換性も維持する）。

---

## 5. 実装方針 / Implementation Plan
Target Branch: `fix/728-supervisor-monotonic-clock`

1. `supervisor.scm` の時刻取得関数を `sys-clock-gettime-monotonic` を参照する実装に置き換える。
2. `%record-restart-and-check-limit!` が実時間の単調増加クロック（およびテスト用オフセット）に基づいてスライディングウィンドウを評価するようにする。

---

## 6. 完了条件 / Success Criteria (DoD)
- [ ] Supervisor の再起動スライディングウィンドウが `sys-clock-gettime-monotonic` の実時間に基づいて動作すること。
- [ ] `make format`, `make static_analysis`, `make test` がすべて PASS すること。

