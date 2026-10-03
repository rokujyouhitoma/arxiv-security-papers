---
ID: 435
種別: Feature
優先度: Medium
ステータス: Closed (Completed)
完了日: 2026-10-04
---

# [FEAT] src/intelligence/cli.py オーケストレータにおける診断ログ(stderr)とデータ(stdout)の完全分離 (ID: 435)

## 1. 概要 / Summary
Unix 哲学の「静けさのルール（Rule of Silence）」および「分離のルール（Rule of Separation）」を遵守するため、既存の統合インテリジェンス・オーケストレータ CLI（`src/intelligence/cli.py`）において、標準出力（stdout）に出力されていたアスキーアートバナー、フェーズ実行マトリクス、進捗ログをすべて標準エラー出力（`stderr`）に分離・移送した。

これにより、オーケストレータ実行時でも `stdout` には純粋な実行結果サマリー（JSON Lines または JSON）のみを出力させることが可能となり、`python -m src.intelligence.cli | jq .` や CI スクリプトとのシームレスなパイプライン連携を実現した。

---

## 2. トレーサビリティ / Traceability
- 要求仕様書: [docs/requirements/REQ-01-system_requirements.md](../../requirements/REQ-01-system_requirements.md) (`REQ-FR-09`, `REQ-NFR-07`)
- 基本設計書: [docs/designs/DSN-01-high_level_design.md](../../designs/DSN-01-high_level_design.md) (`1.3 第5原則`, `5.2 CLI Stream Pipeline Protocol`)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [x] `src/intelligence/cli.py` (`_print_banner`、各フェーズ進捗出力先を stderr へリダイレクト)
- [x] `tests/intelligence/test_cli.py` (CLI 実行時の stdout/stderr 分離テスト)
- [x] `docs/issues/README.md` (Issue台帳の更新)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/435-separate-orchestrator-stdout-and-stderr-streams`

1. **バナーおよびプログレス出力の stderr 化**:
   - `_print_banner()` 内の出力を `sys.stderr.write(banner + "\n")` に変更。
   - `_print_phase_matrix()` および `_print_cycle_details()` の診断出力を `sys.stderr` に統一。
   - 各サイクル開始進捗メッセージを `sys.stderr` に統一。
2. **stdout 出力の純粋化**:
   - `--json` 指定時、パイプライン完走時の実行結果 JSON のみが `sys.stdout` に送出され、バナー等のノイズが混入しないことを担保。
3. **回帰テスト**:
   - `tests/intelligence/test_cli.py` にて stdout/stderr 分離と JSON 純粋性を自動検証。

---

## 5. 完了条件 / Success Criteria (DoD)
- [x] `python src/intelligence/cli.py --json | jq .` が JSON パースエラーを起こさずに実行できること。
- [x] 視覚的なバナーや進捗インジケータは端末画面（stderr）に正常に表示されること。
- [x] 単体テストおよび品質ゲート（Xenon Rank A、mypy strict）に全合格すること。
