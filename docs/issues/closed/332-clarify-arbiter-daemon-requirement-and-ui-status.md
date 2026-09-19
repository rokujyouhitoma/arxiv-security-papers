---
ID: 332
種別: Feature / Documentation
優先度: Medium
ステータス: Closed (Completed)
---

# [FEAT/DOC] スケジューラー本体 (Arbiter) 常駐プロセスの明示化と Web コンソール稼働状態警告の実装 (ID: 332)

## 1. 概要 / Summary
「定期実行」が自律的に機能するためには、Supervisor のスケジューラー本体である Arbiter プロセス（`python -m supervisor.cli start -D` または `make start_supervisor`）が常駐していることが前提条件となる。現状は Web サーバープロセスとは独立しているため、Arbiter が起動していない環境では定期実行が行われない。
本 Issue では、運用ドキュメント（`README.md` / `docs/manuals/USR-01-user_manual.md`）に Arbiter の常駐要件および本番運用向け systemd サービス定義を明記するとともに、Web コンソール上で Supervisor / Arbiter の稼働状況を監視し、非稼働時には警告バナー（「⚠ Supervisor (Arbiter) がオフラインです」等）を表示する動的分岐を実装した。

---

## 2. トレーサビリティ / Traceability
- 関連仕様: [README.md](../../README.md), [USR-01-user_manual.md](../manuals/USR-01-user_manual.md), [handlers.py](../../src/web/gateway/handlers.py), [index.html](../../site/index.html), [app.js](../../site/app.js)
- 要求元: スケジューラー常駐運用の可視化および運用上の誤認防止

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [README.md](../../README.md): バックグラウンド常駐起動手順およびスケジューラー要件明記
- [x] [USR-01-user_manual.md](../manuals/USR-01-user_manual.md): Supervisor 常駐要件・systemd ユニットファイル設定例の追記
- [x] [handlers.py](../../src/web/gateway/handlers.py): `handle_spider_status` レスポンスに `supervisor` 死活状態を含める
- [x] [index.html](../../site/index.html): スパイダータブ上部に Supervisor オフライン警告バナーを追加
- [x] [app.js](../../site/app.js): `loadSpiderStatus()` にて `data.supervisor` を判定し警告バナーを表示・非表示制御
- [x] [test_enterprise_console_ui.py](../../tests/web/test_enterprise_console_ui.py): Supervisor オフライン警告バナー要素および制御ロジックの存在検証テスト追加
- [x] [test_spider_db_persistence.py](../../tests/spider/test_spider_db_persistence.py): `test_spider_status_endpoint` における `supervisor` ステータス検証追加

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/332-clarify-arbiter-daemon-requirement-and-ui-status`

1. **ドキュメント整備**:
   - `README.md` にスパイダー自律実行のための `make start_supervisor`（`python -m supervisor.cli start -D`）常駐要件を明記。
   - `docs/manuals/USR-01-user_manual.md` に systemd サービス定義例（`arxiv-supervisor.service`）を記載。
2. **バックエンド API 拡張 (`src/web/gateway/handlers.py`)**:
   - `handle_spider_status()` にて `_introspect_supervisor_state(self.workspace_dir)` を呼び出し、レスポンス JSON に `"supervisor": {"status": ..., "is_supervised": ...}` を付与。
3. **フロントエンド HTML/JS 改修 (`site/index.html`, `site/app.js`)**:
   - `site/index.html` のスパイダータブ上部に警告バナー `#spiderSupervisorOfflineBanner` を配置。
   - `site/app.js` の `loadSpiderStatus()` で `data.supervisor` をチェックし、オフライン時に警告バナーを `display: flex` で表示、稼働時は `display: none` で非表示化。
4. **テスト追加 (`tests/web/test_enterprise_console_ui.py`, `tests/spider/test_spider_db_persistence.py`)**:
   - HTML 上のバナー要素および JS 内の判定ロジック、API レスポンスをテスト。

---

## 5. 完了条件 / Success Criteria (DoD)
- [x] ドキュメント（README / ユーザーマニュアル）に Arbiter 常駐運用の要件と手順、systemd 設定例が明確に記述されていること。
- [x] `/api/spiders/status` が `supervisor` オブジェクトを返却すること。
- [x] Web コンソールが Supervisor / Arbiter の稼働状況を検知し、オフライン時に警告バナーが表示されること。
- [x] 単体テストおよび全品質ゲート（`make check_format`、`make static_analysis`、`pytest`）が 100% PASS すること。
