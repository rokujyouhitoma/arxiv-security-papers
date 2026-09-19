---
ID: 333
種別: Feature
優先度: Low
ステータス: Open (New)
---

# [FEAT/ENH] スケジューラー初回起動時におけるスパイダー即時実行挙動の制御と仕様明記 (ID: 333)

## 1. 概要 / Summary
`src/workflow/scheduler.py` の `ScheduledTask` 定義において、`last_run: float = 0.0` と初期化されているため、Arbiter プロセス起動直後の初回ポーリング時に全スパイダー（arXiv, CWE, CVE）が即時発火する挙動となっている。
この挙動が「定期実行（6時間後・24時間後）」を期待する運用者に対して違和感を与えないよう、仕様としての位置付けを明確化し、必要に応じて起動時実行スキップ（起動時刻を `last_run` 初期値とする設定等）の選択肢やドキュメント・UI 上の補足説明を導入する。

---

## 2. トレーサビリティ / Traceability
- 関連仕様: `src/workflow/scheduler.py`, `src/workflow/service.py`, `docs/USR-01_USER_MANUAL.md`
- 要求元: スケジューラー初回起動ライフサイクルの予測可能性向上

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [scheduler.py](../../src/workflow/scheduler.py)
- [ ] [service.py](../../src/workflow/service.py)
- [ ] [USR-01_USER_MANUAL.md](../USR-01_USER_MANUAL.md)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/333-clarify-or-adjust-scheduler-initial-execution-behavior`

1. スケジューラー起動オプション（例: `run_on_startup: bool = True`）の検討と、意図的な設計方針の策定。
2. 初回起動時に即時実行される仕様をユーザーマニュアルおよび UI のツールチップ/ヘルプに明記。
3. 必要に応じて `ScheduledTask` 登録時に `initial_delay` または起動時刻基準の `last_run` 設定を可能にする。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] 初回起動時の即時発火挙動について設計方針が定まり、仕様ドキュメントに明記されていること。
- [ ] 起動時オプションまたは挙動の制御がコードとして正しく実装されていること。
- [ ] 関連する単体テストが PASS すること。
