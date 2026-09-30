---
ID: 403
種別: Feature
優先度: Medium
ステータス: Open (New)
---

# [FEAT/ENH] ワーカー異常終了時の未完了チェックポイント自動検出と自己修復・自律再開ポリシーの実装 (ID: 403)

## 1. 概要 / Summary

Issue 396（孤立ジョブの検知・Janitor機構）および Issue 397（フロンティア永続化と手動再開）、Issue 401（Webでの再開制御）によって、スパイダーの中断状態を保存し、手動またはデーモン起動時に復元する土台が完成した。
しかし、プロセス不意のクラッシュや OOM、SIGKILL 等によって Supervisor / SpiderWorker が異常終了した場合、Supervisor や Watchdog（Janitor）は現在「ジョブを失敗・タイムアウトとしてマークする」のみにとどまっており、残された未完了チェックポイント（Frontier & Bloom filter）を自律的に検知して再開を試みる自動リカバリポリシー（Self-Healing Recovery Policy）が存在しない。

本 Issue では、Supervisor および Janitor / Watchdog 機構にチェックポイント連携のリカバリポリシーを導入し、異常終了したスパイダーの残存フロンティアを自動検証した上で、設定されたポリシー（即時自律再開 / 指数バックオフ再試行 / Web コンソールへの復旧アラート発出）に基づき自動修復・再開を行えるようにする。

---

## 2. トレーサビリティ / Traceability

- **関連 Issue**:
  - [Issue 396 (Closed): 停止・異常終了した孤立スパイダージョブの定期検知および状態修復（Reconciler / Janitor）の実装](closed/396-spider-stale-job-reconciliation-and-watchdog.md)
  - [Issue 397 (Closed): 中断スパイダーの巡回状態（Frontier）保存・デーモンによる自動再開（Resume）機能の実装](closed/397-spider-frontier-state-persistence-and-daemon-resume.md)
  - [Issue 401 (Closed): Web コンソールにおけるスパイダー巡回状態（チェックポイント）の可視化および再開・破棄制御UIの実装](closed/401-spider-checkpoint-status-visualization-and-web-resume-control.md)
  - [Issue 395 (Closed): スパイダー実行の排他制御（Mutex）および二重起動防止の実装](closed/395-spider-execution-concurrency-control-and-mutex.md)
- **アーキテクチャ規約**:
  - Supervisor / Arbiter 自律耐障害性規約
  - ゼロ外部依存・POSIX アトミック操作・Xenon CC <= 3 (Rank A)・Mypy Strict 適合
  - 冪等なリカバリ検証（破損チェックポイントの安全退避・無限再開ループ防止）

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files

- [ ] [src/spider/daemon/reconciler.py](../../src/spider/daemon/reconciler.py) (孤立ジョブ回収時にチェックポイント存在を検知しリカバリポリシーを判定)
- [ ] [src/spider/distributed/state_storage.py](../../src/spider/distributed/state_storage.py) (リカバリ試行回数カウンターの記録および破損チェックポイント隔離 `quarantine` メソッド)
- [ ] [src/spider/daemon/supervisor.py](../../src/spider/daemon/supervisor.py) (自律再開ジョブの安全ディスパッチおよび二重起動防止連携)
- [ ] [src/web/gateway/handlers.py](../../src/web/gateway/handlers.py) (自己修復・自律リカバリ発生時の監査ログおよびステータス連携)
- [ ] [site/app.js](../../site/app.js) (自動リカバリ発生時のトースト通知・バッジ表示)
- [ ] [tests/spider/test_reconciler_recovery.py](../../tests/spider/test_reconciler_recovery.py) (異常終了・クラッシュ時の自己修復シミュレーション結合テスト)
- [ ] [docs/issues/README.md](README.md) (Issue 台帳の進捗更新)

---

## 4. 実装方針 / Implementation Plan

Target Branch: `feat/403-spider-crash-recovery-and-autonomous-resume-policy`

1. **自己修復ポリシー（Self-Healing Policy）の定義**:
   - リカバリ設定（最大再試行回数: デフォルト 3回、バックオフ待機秒数）。
   - チェックポイント整合性検証（JSON 不正やゼロバイト破損時は `quarantine` ディレクトリへ安全退避し、無限ループを回避）。
2. **Reconciler / Janitor 拡張**:
   - 孤立ジョブ（stale running job）を検出した際、有効なチェックポイントが存在すればステータスを `RECOVERABLE` に設定。
   - 自律再開が有効な場合、Mutex ロックを取得して `resume=True` で SpiderWorker に安全に再ディスパッチする。
3. **Web コンソール通知 & 監査ログ**:
   - 自動リカバリがトリガーされた履歴を `outputs/log.md` および Web API 経由でオペレーターに明示。
4. **品質テスト**:
   - プロセス強制終了シミュレーションテストを追加し、CC <= 3 を厳格維持。

---

## 5. 完了条件 / Success Criteria (DoD)

- [ ] スパイダーワーカーがクラッシュ・異常終了した際、Reconciler が未完了チェックポイントを検知して安全に自動リカバリ（自律再開）できる。
- [ ] 破損したチェックポイントがある場合、安全に隔離（quarantine）され、二重クラッシュループに陥らないこと。
- [ ] 最大再試行回数を超過した場合は安全に停止し、Web コンソールおよびログに明示的な警告が記録される。
- [ ] `make static_analysis` (mypy --strict, xenon CC <= 3) および全テストが 100% PASS すること。
