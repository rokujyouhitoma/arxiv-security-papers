---
ID: 332
種別: Feature
優先度: Medium
ステータス: Open (New)
---

# [FEAT/DOC] スケジューラー本体 (Arbiter) 常駐プロセスの明示化と Web コンソール稼働状態警告の実装 (ID: 332)

## 1. 概要 / Summary
「定期実行」が自律的に機能するためには、Supervisor のスケジューラー本体である Arbiter プロセス（`python -m supervisor.cli start -D`）が常駐していることが前提条件となる。現状は Web サーバープロセスとは独立しているため、Arbiter が起動していない環境では定期実行が行われない。
本 Issue では、運用ドキュメント（README / ユーザーマニュアル）に Arbiter の常駐要件およびサービス定義（systemd / launchd）を明記するとともに、Web コンソール上で Supervisor / Arbiter の稼働状況を監視し、非稼働時には警告表示（「⚠ Supervisor が起動していません」等）を行う表示分岐を実装する。

---

## 2. トレーサビリティ / Traceability
- 関連仕様: `README.md`, `docs/USR-01_USER_MANUAL.md`, `src/web/gateway/handlers.py`, `site/app.js`
- 要求元: スケジューラー常駐運用の可視化および運用上の誤認防止

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [README.md](../../README.md)
- [ ] [USR-01_USER_MANUAL.md](../USR-01_USER_MANUAL.md)
- [ ] [handlers.py](../../src/web/gateway/handlers.py)
- [ ] [app.js](../../site/app.js)
- [ ] [index.html](../../site/index.html)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/332-clarify-arbiter-daemon-requirement-and-ui-status`

1. ドキュメント整備:
   - README およびユーザーマニュアルに `python -m supervisor.cli start -D` による常駐手順と systemd サービス設定例を追記。
2. API 拡張:
   - `handlers.py` の `_introspect_supervisor_state()` または状態 API を通じて、Arbiter プロセスの死活状態をフロントエンドへ返却。
3. UI 表示分岐:
   - `site/app.js` にて、Arbiter がオフラインの場合にスパイダー監視セクションへ警告バナー（例: 「⚠ Supervisor が起動していません。定期実行は停止しています」）を表示。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] ドキュメントに Arbiter 常駐運用の要件と手順が明確に記述されていること。
- [ ] Web コンソールが Supervisor / Arbiter の稼働状況を検知し、オフライン時に適切な警告を表示すること。
- [ ] 既存の正常稼働時には運用中のメッセージが正しく表示されること。
