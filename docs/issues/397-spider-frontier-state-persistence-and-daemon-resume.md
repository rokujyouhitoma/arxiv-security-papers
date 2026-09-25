---
ID: 397
種別: Feature
優先度: Medium
ステータス: Open (New)
---

# [FEAT/ENH] 中断スパイダーの巡回状態（Frontier）保存・デーモンによる自動再開（Resume）機能の実装 (ID: 397)

## 1. 概要 / Summary
NVD/CVE などの長時間に及ぶクローラー実行がプロセス再起動や一時エラー等で中断された際、低レイヤーのクローラーエンジン（`src/spider/runner.py`）に備わっているフロンティア状態永続化・再開機能（`--state-file`, `--resume`）を常駐デーモン（`SpiderDaemonWorker`）および `SpiderDaemonClient`、スケジューラから透過的に活用し、デーモン起動時や中断ジョブ検知時に未巡回キューから自動再開（Resume）可能にするパイプライン連携を確立する。

---

## 2. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [src/spider/daemon/worker.py](../../src/spider/daemon/worker.py) (`_execute_crawl` での `state_file` および `resume_from_state` パラメータ連携)
- [ ] [src/spider/daemon/client.py](../../src/spider/daemon/client.py) (`_execute_local_async` での `state_file` 透過連携)
- [ ] [src/workflow/operators/spider_operator.py](../../src/workflow/operators/spider_operator.py) (`SpiderTaskOperator` でのチェックポイントファイル指定と再開サポート)
- [ ] [src/spider/runner.py](../../src/spider/runner.py) (`run_spider` の状態ファイル保存先ディレクトリ自動生成と整合性向上)
- [ ] [tests/spider/test_spider_daemon.py](../../tests/spider/test_spider_daemon.py) (中断・再開ライフサイクルのテスト追加)

---

## 3. 根本原因分析 (RCA) / Root Cause Analysis
1. **上位オーケストレーション層と低レイヤー再開機能の未接続**:
   - `src/spider/runner.py` には `state_file` と `resume_from_state` による Frontier（Bloom フィルタ・未取得URLキュー）の再開ロジックが実装されている。
   - しかし、`SpiderDaemonWorker._execute_crawl()` や `SpiderDaemonClient._execute_local_async()` ではこれらの引数が渡されておらず、毎回ゼロから新規実行されていた。
2. **中断状態の引き継ぎフローの未確立**:
   - スパイダーの中断時（SIGTERM 等）にフロンティア状態を `outputs/spider/states/<spider_name>_state.json` に安全にフラッシュし、次回起動時に「未完了状態ファイルが存在すれば `--resume` で継続実行する」というライフサイクルポリシーが存在しなかった。

---

## 4. 暫定対処と恒久対策 / Workaround & Permanent Fix
* **暫定対処 (Workaround)**: CLI から手動で `python3 -m spider.runner --spider nvd_cve --state-file outputs/spider/states/nvd_cve.state --resume` を直接叩いて再開。
* **恒久対策 (Permanent Fix)**:
  1. `SpiderDaemonWorker` および `SpiderDaemonClient` の実行パラメータに `state_file` と `resume` オプションを透過的に追加。
  2. デフォルトのチェックポイント保存パス（`outputs/spider/state/<spider_name>.state`）を定義し、正常完了時は状態ファイルをクリーンアップ、中断時は保持して次回実行時に自動再開するポリシーを導入。
  3. デーモン起動時に前回の未完了チェックポイントが存在する場合、自動で再開ジョブ（`resume_{spider_name}_{timestamp}`）を発行して継続処理を実施。

---

## 5. 実装方針 / Implementation Plan
Target Branch: `feat/397-spider-frontier-state-persistence-and-daemon-resume`

1. **Daemon Worker / Client への State File 統合**:
   - `src/spider/daemon/worker.py` の `_execute_crawl` において、`state_file` および `resume` パラメータを `run_spider` へ伝搬。
   - `src/spider/daemon/client.py` の `_execute_local_async` にも同様に伝搬。
2. **自動チェックポイント管理**:
   - スパイダー開始時に `outputs/spider/checkpoints/<spider_name>.state` が存在するか判定し、存在する場合は `resume_from_state=True` で実行。
   - クロール完了（`SUCCESS`）時にチェックポイントを正常破棄。
3. **Workflow Task Operator 連携**:
   - `src/workflow/operators/spider_operator.py` でチェックポイント再開フラグをサポート。
4. **統合テストと品質ゲート通過**:
   - 疑似中断後の再開テストを作成し、取得件数が正しく合算・継続されることを確認。

---

## 6. 完了条件 / Success Criteria (DoD)
- [ ] 中断されたスパイダーの巡回状態がチェックポイントファイルとして保持されること。
- [ ] 次回デーモン起動時または次回実行時に、前回の未巡回URLから再開（Resume）できること。
- [ ] クロールが正常終了した際にはチェックポイントが安全に削除されること。
- [ ] `make test` および `make static_analysis` が全て PASS すること。
