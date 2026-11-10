---
ID: 798
種別: Bug
優先度: Medium
ステータス: Open (New)
---

# [BUG/CONCURRENCY] Supervisor の idle 状態復帰とスケジューラ後処理間のレースコンディション解消 (ID: 798)

## 1. 概要 / Summary
Issue #788 および #789 により Supervisor タスクの重複投入抑止（`idle`, `scheduled`, `running`, `running_notified` の4状態マシン）が導入されたが、状態遷移とスケジューラ内部処理の順序関係に起因する競合窓（Race Condition Window）が残存している。
Supervisor がメールボックス受信ループを終え、CAS により状態を `idle` に戻してから、スケジューラがコンテキストの後処理（状態の `waiting` への変更、実行中フラグのクリア、escape-k の復元）を完全に終えるまでのわずかな隙間に次の `DOWN` シグナルが到着した場合、同一 Supervisor タスクが別 worker によって即座に `scheduled` $\to$ `running` として投入され、2 つの worker スレッド上で並行動作を開始してしまうリスクが存在する。
本 Issue では、`idle` への復帰 CAS をスケジューラの後処理が完全に完了した後（タスク境界を脱出した直後のフック等）で安全に実行するようリファクタリングし、多重実行を完全に防止する。

### 再現手順 / Steps to Reproduce
1. マルチワーカー環境（ワーカー数 4）上で Supervisor タスクを常駐稼働させる。
2. 子タスク群を高速に連続クラッシュさせ、Supervisor が一度受信ループを抜ける瞬間と次の `DOWN` シグナル受信タイミングを意図的に衝突させる。
3. 2 つのワーカー上で同一 Supervisor の実行フラグまたはコンテキストが一時的に競合する現象を確認する。

### 再現環境 / Environment
- OS / Env: Linux x86-64 / macOS arm64
- File: [supervisor.scm](../../ulisp/runtime/concurrency/supervisor.scm), [scheduler.scm](../../ulisp/runtime/concurrency/scheduler.scm)

---

## 2. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [ulisp/runtime/concurrency/supervisor.scm](../../ulisp/runtime/concurrency/supervisor.scm) - Supervisor 状態遷移ロジック
- [ ] [ulisp/runtime/concurrency/scheduler.scm](../../ulisp/runtime/concurrency/scheduler.scm) - タスク終了・後処理フック
- [ ] [tests/concurrency/test_supervisor.scm](../../tests/concurrency/test_supervisor.scm) - 並行クラッシュ時の多重複入ストレステスト

---

## 3. 根本原因分析 (RCA) / Root Cause Analysis
- Supervisor 側が自身の実行終了とみなして状態を `idle` へ戻す CAS を発行するタイミングが、スケジューラが当該タスクのレジスタ/スタック/フラグの後片付けを完了するよりも前に行われているため、タイム・オブ・チェック〜タイム・オブ・ユース（TOCTOU）のギャップが発生している。

---

## 4. 暫定対処と恒久対策 / Workaround & Permanent Fix
* **暫定対処 (Workaround)**:
  - なし（並行タイミング問題のため設計修正が必要）。
* **恒久対策 (Permanent Fix)**:
  - 状態を `idle` へ遷移させる処理を Supervisor のタスク内コードから切り離し、スケジューラがタスク切り替え（コンテキスト保存・waiting 設定）を完了した境界脱出後コールバック（post-context-switch hook）において実行する。

---

## 5. 実装方針 / Implementation Plan
Target Branch: `fix/798-fix-supervisor-idle-state-transition-race`

1. スケジューラのタスク実行完了パスに境界脱出後フック機構を整備。
2. Supervisor の `idle` 復帰 CAS をこのフック内で実行するよう変更。
3. 4 ワーカー高頻度クラッシュテストを実施し、多重起動が発生しないことを検証。

---

## 6. 完了条件 / Success Criteria (DoD)
- [ ] 高速連続クラッシュ時でも Supervisor が同一時刻に単一のワーカーでのみ実行されることが保証されること。
- [ ] 並行性ストレステストにおいてコンテキスト競合や二重起動アサーションエラーが 0 件であること。

