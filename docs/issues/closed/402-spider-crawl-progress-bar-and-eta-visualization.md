---
ID: 402
種別: Feature
優先度: Medium
ステータス: Closed (Completed)
---

# [FEAT/ENH] スパイダー巡回中のリアルタイム進捗率・ETA可視化およびプログレスバー表示の実装 (ID: 402)

## 1. 概要 / Summary

Issue 397 および Issue 401 により、スパイダーの中断時巡回状態（Frontier）永続化と Web コンソールにおけるチェックポイントの再開・破棄制御が導入された。
しかし現状、スパイダーが実行中（Running）の際、Web コンソール上の表示はスピナーと「実行中...」のステータス表示のみにとどまり、全体の進捗率（例: 処理済みURL数 / 総発見URL数）、巡回速度（pages/sec）、完了見込み時間（ETA）をオペレーターがリアルタイムに把握できない。

本 Issue では、スパイダー巡回エンジンから処理済み件数、フロンティアキュー内保留件数、巡回開始時刻などのテレメトリをリアルタイムに Web Gateway `/api/spiders/status` および SSE（Server-Sent Events）ストリーム経由で提供し、Web コンソールのスパイダー管理カードにプログレスバー（%）、巡回レート、および推定残り時間（ETA）を可視化する。

---

## 2. トレーサビリティ / Traceability

- **関連 Issue**:
  - [Issue 401 (Closed): Web コンソールにおけるスパイダー巡回状態（チェックポイント）の可視化および再開・破棄制御UIの実装](closed/401-spider-checkpoint-status-visualization-and-web-resume-control.md)
  - [Issue 397 (Closed): 中断スパイダーの巡回状態（Frontier）保存・デーモンによる自動再開（Resume）機能の実装](closed/397-spider-frontier-state-persistence-and-daemon-resume.md)
  - [Issue 320 (Closed): スパイダー自律定期実行・実行状態DB永続化およびWebコンソール監視UIの実装](closed/320-implement-scheduled-spider-execution-with-db-persistence-and-web-ui.md)
- **アーキテクチャ規約**:
  - Antigravity IDE & 2.0 Web Gateway ガバナンス規約
  - Pure Vanilla JS (フレームワーク非依存・JSDoc 型契約・Closure Compiler 適合)
  - ゼロ外部依存・アトミック状態更新・Xenon CC <= 3 (Rank A)・Mypy Strict 適合

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files

- [x] [src/spider/core/engine.py](../../src/spider/core/engine.py) (巡回カウンタ、処理速度、リアルタイム進捗テレメトリ集計・更新)
- [x] [src/spider/distributed/state_storage.py](../../src/spider/distributed/state_storage.py) (実行中スパイダーのリアルタイム進捗メトリクス取得・永続化・ETA計算API)
- [x] [src/web/gateway/handlers.py](../../src/web/gateway/handlers.py) (`handle_spider_status` レスポンスへの進捗率・ETA・処理レート情報の追加)
- [x] [site/index.html](../../site/index.html) (スパイダーカード内プログレスバー要素および ETA 表示コンテナの追加)
- [x] [site/app.js](../../site/app.js) (`loadSpiderStatus` におけるプログレスバー更新・ETA レンダリング処理の統合)
- [x] [tests/web/test_web_server.py](../../tests/web/test_web_server.py) (進捗率・ETA レスポンス構造の回帰テスト)
- [x] [tests/web/test_js_syntax_and_contracts.py](../../tests/web/test_js_syntax_and_contracts.py) (UI 要素バインディングの整合性検証)
- [x] [tests/spider/test_spider_progress.py](../../tests/spider/test_spider_progress.py) (進捗計算およびテレメトリ永続化テスト)
- [x] [docs/issues/README.md](README.md) (Issue 台帳の進捗更新)

---

## 4. 実装方針 / Implementation Plan

Target Branch: `feat/402-spider-crawl-progress-bar-and-eta-visualization`

1. **バックエンド**:
   - `StateStorage` において、`processed_count`, `pending_count`, `start_time` から進捗率（`ratio_pct`）、巡回レート（`pages_per_second`）、ETA（秒）を計算・アトミック保存する API を実装。
   - `handlers.py` の `/api/spiders/status` レスポンスに `progress` オブジェクトを含める。
2. **フロントエンド**:
   - `site/index.html` の各スパイダーカード内にアニメーション付きプログレスバー（`<div class="progress-bar">`）と ETA / レートラベルを追加。
   - `site/app.js` で `status === 'RUNNING'` 時のプログレスバー動的更新およびアクセシブルな `aria-valuenow` 属性の同期を行う。
3. **品質テスト**:
   - Web サーバー結合テストおよびフロントエンド静的構文テストを追加し、CC <= 3 を厳格維持。

---

## 5. 完了条件 / Success Criteria (DoD)

- [x] スパイダー実行中に `/api/spiders/status` から進捗メトリクス（処理済み数、保留数、進捗率%、ETA）が正しく返却される。
- [x] Web コンソールのスパイダー管理カードで実行中にプログレスバーおよび ETA 表示が滑らかに更新される。
- [x] チェックポイント再開時にも、再開時点の保留件数に基づき正確な進捗率が計算・表示される。
- [x] `make static_analysis` (mypy --strict, xenon CC <= 3) および全テストが 100% PASS すること。

