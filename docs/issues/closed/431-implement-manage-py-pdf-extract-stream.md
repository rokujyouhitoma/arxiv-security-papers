---
ID: 431
種別: Feature
優先度: High
ステータス: Closed (Completed)
完了日: 2026-10-04
---

# [FEAT] manage.py pdf-extract 全文テキスト抽出ストリームフィルタの実装 (ID: 431)

## 1. 概要 / Summary
`REQ-FR-09` および `DSN-01 Section 5.2` のパイプライン第2ステージとして、標準入力（stdin）から論文メタデータ（JSON Lines）を受け取り、PDF をダウンロード・抽出して全文テキスト（`full_text`）および図表メタデータを付加した拡張 JSON Lines を標準出力（stdout）に流す `manage.py pdf-extract` フィルタコマンドを `src/cli/commands/pdf_extract.py` に実装した。

PDF 解析処理には内製の Pure-Python PDF エンジン（`src/pdf_engine`）を活用し、外部依存ゼロのままストリーム変換を行う。

---

## 2. トレーサビリティ / Traceability
- 要求仕様書: [docs/requirements/REQ-01-system_requirements.md](../../requirements/REQ-01-system_requirements.md) (`REQ-FR-01`, `REQ-FR-09`)
- 基本設計書: [docs/designs/DSN-01-high_level_design.md](../../designs/DSN-01-high_level_design.md) (`5.2 CLI Stream Pipeline Protocol`)
- 基底依存: Issue #429 (`src/cli/stream.py`), [src/pdf_engine](../../src/pdf_engine)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [x] `src/cli/commands/pdf_extract.py` (新規作成: PdfExtractCommand)
- [x] `src/cli/registry.py` (pdf-extract サブコマンドの登録)
- [x] `tests/cli/commands/test_pdf_extract.py` (新規単体テスト)
- [x] `docs/issues/README.md` (Issue台帳の更新)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/431-implement-manage-py-pdf-extract-stream`

1. **`PdfExtractCommand` の定義**:
   - `src/cli/commands/pdf_extract.py` に `PdfExtractCommand(BaseCommand)` を作成。
   - 引数オプション:
     - `--pdf-cache-dir` (ローカルキャッシュ先ディレクトリ、デフォルト: `data/pdf_cache`)
     - `--on-error` (エラー処理ポリシー: `skip` または `abort`)
2. **ストリーム処理ループ**:
   - `StreamReader` で stdin から各論文メタデータを 1 行ずつ受信。
   - ローカルキャッシュに PDF が存在する場合は `PurePdfTextExtractor` で全文テキストとページ数を抽出。
   - 未キャッシュまたは失敗時は要約テキストへ安全にフォールバック。
   - 受信した JSON に `full_text`, `page_count`, `extracted_at` を付与して `StreamWriter` で stdout に出力。
3. **診断ログ**:
   - 進捗および抽出ステータスは stderr へ出力。

---

## 5. 完了条件 / Success Criteria (DoD)
- [x] `cat papers.jsonl | python manage.py pdf-extract` で、全文テキストが付与された JSONL が stdout に流れること。
- [x] 進捗ログが stdout に混入せず、すべて stderr に出力されること。
- [x] 不正な PDF やダウンロード失敗時に `--on-error=skip` で後続行が継続処理されること。
- [x] 単体テストがパスし、品質ゲート（Xenon Rank A, Mypy Strict, Flake8）を満たすこと。
