---
ID: 746
種別: Feature / CI Integration
優先度: High
ステータス: Closed
関連PR: -
ブランチ: feat/746-integrate-multithread-and-coroutine-integration-tests-into-ci
---

# [FEAT/ENH] CI テストマトリクスへのマルチスレッド・コルーチン並行性結合テスト統合 (ID: 746)

## 1. 概要 / Summary
Synapse 並行性ランタイム向けに `test_supervisor`、`test_multithread_scheduler`、`test_let_it_crash`、`test_concurrency_harness` 等のマルチスレッドおよびコルーチン結合テストが作成されたが、現在の `.github/workflows/ci.yml` では単一スレッドの Python テスト（`make test (pytest)`）および DB 差分監査のみが実行されており、CI パイプライン上でネイティブ並行性ランタイムの実動作・耐障害性が自動検証されていない。

PR や main ブランチへのコミット時に、マルチスレッド OS ワーカー、コルーチンスケジューラ、およびカオスジッター耐性回帰テストが自動実行されるよう、CI ワークフロー (`ci.yml`) と `Makefile` / `ulisp/Makefile` ターゲットを整備する。

また、既存の `concurrency_harness.scm` (Scenario 4e) において、Issue #741 (タスク正常終了時のクリーンアップ・DOWN 通知実装) 以降に発生している `permanent` 再起動セマンティクスによる再起動カウント不一致（`expected: 2, got: 3`）を `'transient` 指定により解消し、CI テストが常時 100% 安定して PASS する環境を構築する。

---

## 2. トレーサビリティ / Traceability
- **関連 Issue**: #722 (Supervisor Fault Isolation), #741 (Normal Task Termination DOWN), #742 (Auto-Enqueue Restarted Child), #743 (Supervisor Actor Isolation), #745 (Arena Reset Stop Verification)
- **関連仕様・資料**:
  - DSN-37 Section 7.4 (Multithreaded Work-Stealing) & 8.4.3 (Supervision Tree)
  - GitHub Actions CI ワークフロー仕様 (`.github/workflows/ci.yml`)
  - ULisp 並行性テストハーネス (`tests/concurrency/concurrency_harness.scm`)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [`.github/workflows/ci.yml`](../../.github/workflows/ci.yml): CI パイプラインへの並行性ランタイム結合テストジョブ/ステップ追加
- [x] [`Makefile`](../../Makefile): `test_concurrency` / `test-concurrency` ターゲット新設
- [x] [`ulisp/Makefile`](../../ulisp/Makefile): `test_concurrency` ターゲット新設および `test_concurrency_ci` の対象拡充
- [x] [`tests/concurrency/concurrency_harness.scm`](../../tests/concurrency/concurrency_harness.scm): Scenario 4e の再起動指定適正化 (`'transient`)
- [x] [`tests/concurrency/test_multithread_scheduler.scm`](../../tests/concurrency/test_multithread_scheduler.scm): マルチスレッド検証対象の動作確認
- [x] [`tests/concurrency/test_supervisor.scm`](../../tests/concurrency/test_supervisor.scm): コルーチン/アクター検証対象の動作確認

---

## 4. 脅威モデルおよびセキュリティ要件 / Threat Modeling & Security
- **CWE-362 (Race Condition)**: CI 上のマルチコア仮想マシン (GitHub Actions `ubuntu-24.04`) において、スレッド間競合やチャネル送受信のレースコンディションを完全排除すること。
- **CWE-833 (Deadlock)**: ワークスティーリングや futex 同期待ちでのデッドロックによる CI タイムアウトを防止し、Chaos Jitter 注入下でも確実に終了すること。
- **CWE-416 (Use-After-Free)**: 並行タスク停止後の Ephemeral Arena 解放競合が CI マシン上で発生しないことを回帰テストで常時監視すること。
- **Flakiness 排除**: CI のビルド信頼性を損なわないよう、100 回のイテレーションとジッター注入下で偽陽性・偽陰性なく決定論的に PASS すること。

---

## 5. 実装方針 / Implementation Plan

Target Branch: `feat/746-integrate-multithread-and-coroutine-integration-tests-into-ci`

### Step 1: ブランチ作成
```bash
git checkout -b feat/746-integrate-multithread-and-coroutine-integration-tests-into-ci
```

### Step 2: `concurrency_harness.scm` Scenario 4e の適正化 (`tests/concurrency/concurrency_harness.scm`)
- Scenario 4e (`run-scenario-supervisor-fault-isolation!`) において、`crashy-spec` の生成時に再起動タイプ `'transient'` を明示指定する：
  ```scheme
  (crashy-spec
   (make-child-spec
    'ci_crashy_worker
    (lambda () ...)
    'transient))
  ```
- Issue #741 によりタスク正常終了時にも DOWN シグナルが送信されるようになったため、`transient` を指定することで、クラッシュ時は再起動し、再起動後の正常終了時は再起動を抑止して期待値（boot count = 2）と合致させる。

### Step 3: `ulisp/Makefile` への並行性総合テストターゲット整備 (`ulisp/Makefile`)
- `test_concurrency` ターゲットを新設し、主要な並行性テストスイートを順次実行：
  - `test_multithread_scheduler` (複数 OS スレッドワーカー、コアピニング、並列実行)
  - `test_supervisor` (スーパーバイザーツリー、アクタータスク、自動再起動)
  - `test_let_it_crash` (パニック境界、Ephemeral Arena 解放、チャネル汚染)
  - `test_scheduler` (シングルワーカー・ワークスティーリング・コルーチン)
  - `test_links_monitors` (双方向リンク、単方向モニタ)
  - `test_preemption` (Safepoint プリエンプション)
  - `test_concurrency_harness` (100 回イテレーション Chaos Jitter ハーネス)
- `test_concurrency_ci` ターゲットから `test_concurrency` を呼び出すようリファクタリング。

### Step 4: ルート `Makefile` への `test_concurrency` 統合 (`Makefile`)
- `test_concurrency` およびエイリアス `test-concurrency` を追加：
  ```makefile
  .PHONY: test_concurrency test-concurrency
  test_concurrency: ## Run complete Synapse multithreaded and coroutine concurrency test suite
  	$(MAKE) -C ulisp test_concurrency

  test-concurrency: test_concurrency
  ```

### Step 5: `.github/workflows/ci.yml` への Quality Gate 統合 (`.github/workflows/ci.yml`)
- `quality-and-differential-gates` ジョブ内の Quality Gate ステップに以下を追加：
  ```yaml
  - name: Quality Gate 6 - Multicore Concurrency & Coroutine Integration Tests
    run: make test_concurrency
  ```
- 既存の Linux x86-64 ランナー (`ubuntu-24.04`) 上で `gcc` とアセンブラ・リンカを利用してネイティブバイナリをビルド・実行可能にする。

### Step 6: 総合検証 & CI 構文検証
- `make test_concurrency` をローカルで実行し、全テストケースが 100% PASS することを確認。
- `git diff` および pre-commit フック検証。

---

## 6. 完了条件 / Definition of Done (DoD)
- [x] `tests/concurrency/concurrency_harness.scm` の Scenario 4e が修正され、100 回のイテレーションが 0 failure で完走すること
- [x] `ulisp/Makefile` に `test_concurrency` ターゲットが定義され、マルチスレッドおよびコルーチン関連テストが一括実行できること
- [x] ルート `Makefile` に `test_concurrency` および `test-concurrency` ターゲットが定義されていること
- [x] `.github/workflows/ci.yml` に `Quality Gate 6 - Multicore Concurrency & Coroutine Integration Tests` が追加されていること
- [x] ローカル環境で `make test_concurrency` を実行し、全テストスイートが 100% PASS すること
- [x] GitHub Actions CI 定義ファイルが YAML 構文エラーなく正当であること
- [x] pre-commit 品質ゲート（フォーマット、静的解析、型チェック）がすべて PASS すること
