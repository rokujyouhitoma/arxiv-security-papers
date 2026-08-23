# [FEAT] Supervisor CLI top モニタリング機能の実装 (ID: 070)

## メタデータ
- **ID**: 070
- **種別**: Feature
- **優先度**: Medium
- **ステータス**: Closed (Completed)
- **作成日**: 2026-08-23
- **完了日**: 2026-08-23
- **担当**: IT Service Manager / Systems Architect

---

## 1. 概要 / Summary
`supervisor.cli` に `top` サブコマンド（`PYTHONPATH=src .venv/bin/python -m supervisor.cli top`）を追加し、Arbiter および Web/Database ワーカープロセスの PID、CPU使用率、メモリ使用量 (RSS)、処理リクエスト数、稼働時間 (Uptime)、ヘルス状態などをリアルタイムまたはワンショットで ANSI ターミナルテーブル表示するプロセスモニタリング機能を提供する。

---

## 2. 影響範囲と関連ファイル / Scope and Affected Files
- `src/supervisor/top.py` (プロセスメトリクス収集および ANSI ターミナル描画エンジン)
- `src/supervisor/cli.py` (CLI引数パーサーに `top` サブコマンド追加、ディスパッチ処理)
- `src/supervisor/arbiter.py` / `src/supervisor/workers/async_worker.py` (型定義の整合性強化)
- `tests/supervisor/test_top.py` (top コマンドおよびレンダラーの単体テスト)
- `tests/supervisor/test_cli.py` (CLI パーサーのテスト拡張)
- `Makefile` (`top_supervisor` ターゲット追加)
- `docs/designs/DSN-12-process_supervisor_and_arbiter.md` (Top仕様およびCLI運用コマンドリファレンス追加)

---

## 3. 要件と仕様 / Requirements & Specifications
1. **サブコマンド構文**:
   - `python -m supervisor.cli top [--interval SECONDS] [--once] [--no-color]`
   - `make top_supervisor` (ワンショット: `make top_supervisor ARGS="--once"`)
2. **収集メトリクス**:
   - Arbiter: PID, Uptime, Target/Active Workers, Memory (RSS), Binding, Worker Class
   - 各 Worker: PID, Worker Type (web/database), Status (ALIVE/DEAD), Health (HEALTHY/DEGRADED), Requests Handled, Idle Seconds, Memory (RSS)
3. **描画スタイル**:
   - ANSI カラー対応（緑: HEALTHY, 赤: UNHEALTHY, 青: Arbiter, マゼンタ: DB）
   - テーブルヘッダーと境界線
   - `--once` で1回表示して終了、デフォルトは定期リフレッシュ (Ctrl+C で安全終了)
4. **ポータビリティ**:
   - 外部ライブラリ依存ゼロ（標準ライブラリ `os`, `sys`, `time`, `json`, Linux `/proc` を活用）

---

## 4. Definition of Done (DoD)
- [x] `supervisor.cli top --once` が正常終了し、構造化テーブルを出力すること
- [x] `supervisor.cli top` がリフレッシュループで動作し、Ctrl+C でクリーンに終了すること
- [x] Arbiter が停止している場合のエラーハンドリングが適切に行われること
- [x] `make check_format` および `make static_analysis` (flake8, py_compile, mypy) が 100% PASS すること
- [x] 単体テストが作成され `pytest tests/supervisor/` が 36件全件 PASS すること
