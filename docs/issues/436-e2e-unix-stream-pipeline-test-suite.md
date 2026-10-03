---
ID: 436
種別: Feature
優先度: High
ステータス: Open (New)
---

# [FEAT] Unix ストリームパイプライン統合テストスイートおよびOSツール連携検証の実装 (ID: 436)

## 1. 概要 / Summary
Issue #429 〜 #434 で実装された各 CLI ストリームサブコマンド群（`fetch`, `pdf-extract`, `okf-convert`, `summarize`, `db-index`）が、シェルパイプ（`|`）および標準入出力ストリームを介して end-to-end で正確に連動し、データ欠損やデッドロックなく完走することを検証する統合 E2E テストスイート（`tests/cli/test_stream_pipeline.py`）を実装する。

さらに、`jq`, `grep`, `wc`, `xargs` などの代表的な Unix 標準ツールとの連携が正常に機能することを実証する。

---

## 2. トレーサビリティ / Traceability
- 要求仕様書: [docs/requirements/REQ-01-system_requirements.md](../requirements/REQ-01-system_requirements.md) (`REQ-FR-09`, `REQ-NFR-06`, `REQ-NFR-07`)
- 基本設計書: [docs/designs/DSN-01-high_level_design.md](../designs/DSN-01-high_level_design.md) (`5.2 CLI Stream Pipeline Protocol`)
- 依存 Issue: Issue #429, #430, #431, #432, #433, #434

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] `tests/cli/test_stream_pipeline.py` (新規作成: フルストリームパイプライン E2E テスト)
- [ ] `Makefile` (`test_stream` ターゲットの追加)
- [ ] `docs/user_manual.md` (CLI パイプライン連携ユースケース・使用例の追記)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/436-e2e-unix-stream-pipeline-test-suite`

1. **E2E フルパイプライン連動テスト**:
   - `subprocess.Popen` を用いて、以下のパイプラインが終了コード 0 で完走することをテスト：
     ```bash
     python manage.py fetch --limit 2 --stream \
       | python manage.py pdf-extract --stream \
       | python manage.py okf-convert --stream \
       | python manage.py summarize --stream \
       | python manage.py db-index --stream --passthrough
     ```
   - 最終出力レコードのフィールド完全性（`arxiv_id`, `full_text`, `okf_yaml`, `summary_ja` 等の存在）をアサート。
2. **中間フィルタリング・Unix ツール結合テスト**:
   - `python manage.py fetch --limit 5 | jq -c 'select(.arxiv_id != "")'` などのフィルタ連動をテスト。
3. **バックプレッシャー & 大規模ストリーム耐性テスト**:
   - 複数行（例: 50行以上）の JSONL を流した際にバッファ詰まりやデッドロックが発生しないことを確認。
4. **マニュアル記載**:
   - `docs/user_manual.md` にワンライナーでの実行例や Unix パイプライン活用のTipsを記載。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] フルストリームパイプライン E2E テストが `pytest tests/cli/test_stream_pipeline.py` で 100% PASS すること。
- [ ] `make test` および CI 品質ゲートを全通過すること。
- [ ] `docs/user_manual.md` に Unix パイプライン使用法が反映されていること。
