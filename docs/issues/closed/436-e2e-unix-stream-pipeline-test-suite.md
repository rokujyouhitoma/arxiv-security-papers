---
ID: 436
種別: Feature
優先度: High
ステータス: Closed (Completed)
完了日: 2026-10-04
---

# [FEAT] Unix ストリームパイプライン統合テストスイートおよびOSツール連携検証の実装 (ID: 436)

## 1. 概要 / Summary
Issue #429 〜 #434 で実装された各 CLI ストリームサブコマンド群（`fetch`, `pdf-extract`, `okf-convert`, `summarize`, `db-index`）が、シェルパイプ（`|`）および標準入出力ストリームを介して end-to-end で正確に連動し、データ欠損やデッドロックなく完走することを検証する統合 E2E テストスイート（`tests/cli/test_stream_pipeline.py`）を実装した。

さらに、`Makefile` に `make test_stream` ターゲットを追加し、`docs/manuals/USR-01-user_manual.md` に Unix CLI パイプライン連携ユースケース・使用例を追記した。

---

## 2. トレーサビリティ / Traceability
- 要求仕様書: [docs/requirements/REQ-01-system_requirements.md](../../requirements/REQ-01-system_requirements.md) (`REQ-FR-09`, `REQ-NFR-06`, `REQ-NFR-07`)
- 基本設計書: [docs/designs/DSN-01-high_level_design.md](../../designs/DSN-01-high_level_design.md) (`5.2 CLI Stream Pipeline Protocol`)
- 依存 Issue: Issue #429, #430, #431, #432, #433, #434

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [x] `tests/cli/test_stream_pipeline.py` (新規作成: フルストリームパイプライン E2E テスト)
- [x] `Makefile` (`test_stream` ターゲットの追加)
- [x] `docs/manuals/USR-01-user_manual.md` (CLI パイプライン連携ユースケース・使用例の追記)
- [x] `docs/issues/README.md` (Issue台帳の更新)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/436-e2e-unix-stream-pipeline-test-suite`

1. **E2E フルパイプライン連動テスト**:
   - `pdf-extract | okf-convert | summarize | db-index` の直結ストリーム連動をテスト。
   - 最終出力レコードのフィールド完全性（`arxiv_id`, `full_text`, `okf_yaml`, `summary_ja`, `points_ja` 等の存在）およびカタログ登録をアサート。
2. **中間エラー耐性テスト**:
   - 不正な非 JSON 行を混入させたストリームに対し、`--on-error=skip` で後続の正常行が中断せず完走することを検証。
3. **Makefile ターゲット追加**:
   - `make test_stream` で全 43 件の CLI ストリームテストを一括実行可能に拡張。
4. **マニュアル記載**:
   - `docs/manuals/USR-01-user_manual.md` に Section 3.6 および チートシート行を追記。

---

## 5. 完了条件 / Success Criteria (DoD)
- [x] フルストリームパイプライン E2E テストが `make test_stream` で 100% PASS すること。
- [x] `docs/manuals/USR-01-user_manual.md` に Unix パイプライン使用法が反映されていること。
