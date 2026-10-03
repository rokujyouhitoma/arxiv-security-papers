---
ID: 432
種別: Feature
優先度: High
ステータス: Closed (Completed)
完了日: 2026-10-04
---

# [FEAT] manage.py okf-convert Google OKF構造化ストリームフィルタの実装 (ID: 432)

## 1. 概要 / Summary
`REQ-FR-09` および `DSN-01 Section 5.2` のパイプライン第3ステージとして、標準入力（stdin）からテキスト抽出済み論文レコード（JSON Lines）を受け取り、Google Open Knowledge Format (OKF) v0.2 仕様に準拠した YAML フロントマター付きナレッジデータを生成して標準出力（stdout）に流す `manage.py okf-convert` フィルタコマンドを `src/cli/commands/okf_convert.py` に実装した。

ストリーム出力モードとして、後続ツールへ渡す拡張 JSON Lines（`--format=jsonl`）と、OKF Markdown ドキュメント直接出力（`--format=markdown`）の双方をサポートし、オプションで指定ディレクトリへのファイル永続化も提供する。

---

## 2. トレーサビリティ / Traceability
- 要求仕様書: [docs/requirements/REQ-01-system_requirements.md](../../requirements/REQ-01-system_requirements.md) (`REQ-FR-02`, `REQ-FR-09`)
- 基本設計書: [docs/designs/DSN-01-high_level_design.md](../../designs/DSN-01-high_level_design.md) (`5.2 CLI Stream Pipeline Protocol`)
- 基底依存: Issue #429 (`src/cli/stream.py`), [src/pipeline/transformer](../../src/pipeline/transformer)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [x] `src/cli/commands/okf_convert.py` (新規作成: OkfConvertCommand)
- [x] `src/cli/registry.py` (okf-convert サブコマンドの登録)
- [x] `tests/cli/commands/test_okf_convert.py` (新規単体テスト)
- [x] `docs/issues/README.md` (Issue台帳の更新)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/432-implement-manage-py-okf-convert-stream`

1. **`OkfConvertCommand` の定義**:
   - `src/cli/commands/okf_convert.py` に `OkfConvertCommand(BaseCommand)` を作成。
   - 引数オプション:
     - `-f`, `--format` (`jsonl` または `markdown`, デフォルト: `jsonl`)
     - `--save-dir` (指定された場合、ディスク上に `.md` ファイルを永続化)
     - `--on-error` (`skip` または `abort`, デフォルト: `skip`)
2. **OKF 変換とプロバナンス付与**:
   - `generate_japanese_executive_summary` による日本語エグゼクティブサマリー生成。
   - `determine_security_tags` によるセキュリティタグ付与。
   - Google OKF v0.2 仕様に適合した YAML フロントマターの動的生成。
3. **ストリーム送出**:
   - `jsonl`: OKF フィールド（`okf_yaml`, `markdown_content`, `tags`, `title_ja` 等）を含むレコードを出力。
   - `markdown`: 完全な Markdown ドキュメントを出力。

---

## 5. 完了条件 / Success Criteria (DoD)
- [x] `cat extracted.jsonl | python manage.py okf-convert` で、Google OKF v0.2 フィールドを含む JSONL が stdout に流れること。
- [x] `python manage.py okf-convert --format=markdown` で有効な YAML フロントマター付き Markdown が stdout に出力されること。
- [x] 単体テストがパスし、品質ゲート（Xenon Rank A, Mypy Strict, Flake8）を満たすこと。
