---
ID: 365
種別: Refactor
優先度: Medium
ステータス: Open (In Progress)
---

# [REFACTOR] Supervisor 実行時ソケットの `src/outputs/` 漏洩防止およびログ・PID/ロックファイルの適正配置への一本化 (ID: 365)

## 1. 概要 / Summary

現在、Supervisor デーモンの起動および実行時に、相対パスの解決差異に起因して `src/outputs/supervisor/` 配下に `db_*.sock`（UNIX ドメインソケット）が生成され、本来コードのみであるべき `src/` 配下が汚染されている。

加えて、Supervisor 関連のファイル配置が以下のように分裂している：
- `outputs/supervisor/`: `arbiter.lock`, `arbiter.pid`, `control.sock`, `search.sock`, `heartbeat_*.json`, および 28MB の `supervisor.log`
- `outputs/logs/`: `supervisor.log` (1.1KB, 過去世代), `web_access.jsonl` (30MB), `query_log.jsonl` 等
- `src/outputs/supervisor/`: `db_*.sock`

本 Issue では、Supervisor のパス解決ロジックを修正して `src/outputs/` へのファイル漏洩を根絶し、ソケット・PID・ロックなどの実行時ランタイムファイルとログ出力の配置を整流化・一本化する。

---

## 2. トレーサビリティ / Traceability

- 関連 Issue: [Issue 332: Clarify Arbiter Daemon Requirement](closed/332-clarify-arbiter-daemon-requirement-and-ui-status.md)
- 関連設定: `config/supervisor.json`
- 関連規定: `.gitignore`（`outputs/supervisor/`, `src/outputs/`, `outputs/logs/`）

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files

### ソースコード・設定
- [ ] `src/supervisor/` 配下のパス解決ロジック（ベースディレクトリ解決）
- [ ] `config/supervisor.json`（ソケットおよびログパス定義）
- [ ] `src/outputs/` (完全削除)

### 出力・ランタイムストレージ
- [ ] `outputs/supervisor/`（ランタイムファイル管理）
- [ ] `outputs/logs/`（ログ集約先）

### テストスイート
- [ ] `tests/supervisor/` 配下のユニットテスト

---

## 4. 実装方針 / Implementation Plan

Target Branch: `refactor/365-isolate-runtime-sockets-logging`

1. **ベースディレクトリ解決の厳格化**:
   - `src/supervisor/` 内で実行時パス（ソケット、PID、ロック）を生成する際、カレントワーキングディレクトリ依存の相対パスを排し、`BASE_DIR`（プロジェクトルート）基準の絶対パスまたは統一プレフィックスへ修正。
   - `src/outputs/` が生成される根本原因（`src` 内からの相対解決）を修正。
2. **`src/outputs/` の完全除去**:
   - リポジトリから `src/outputs/` ディレクトリおよび残存ソケットファイルを完全削除。
3. **ログ出力先の一本化とローテーション**:
   - `supervisor.log` の出力先を `outputs/logs/supervisor.log` に集約。
   - 肥大化（28MB）を防ぐため、`RotatingFileHandler`（例: 最大10MB、バックアップ3世代）を適用。
4. **品質ゲートの検証**:
   - Supervisor の起動・停止・ソケット通信テストを実行し、`src/outputs/` が一切再生成されないことを確認。
   - `make static_analysis`
   - `make test`

---

## 5. 完了条件 / Success Criteria (DoD)

- [ ] Supervisor 起動・停止・テスト実行時に `src/outputs/` が一切作成されないこと。
- [ ] ログ出力が `outputs/logs/supervisor.log` に統一され、ローテーションが機能していること。
- [ ] UNIX ドメインソケットおよび PID/Lock が指定の一時ディレクトリ配下にのみ配置されること。
- [ ] 全テストスイートが 100% PASS すること。
