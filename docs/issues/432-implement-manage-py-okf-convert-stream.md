---
ID: 432
種別: Feature
優先度: High
ステータス: Open (New)
---

# [FEAT] manage.py okf-convert Google OKF構造化ストリームフィルタの実装 (ID: 432)

## 1. 概要 / Summary
`REQ-FR-09` および `DSN-01 Section 5.2` のパイプライン第3ステージとして、標準入力（stdin）からテキスト抽出済み論文レコード（JSON Lines）を受け取り、Google Open Knowledge Format (OKF) v0.2 仕様に準拠した YAML フロントマター付きナレッジデータを生成して標準出力（stdout）に流す `manage.py okf-convert` フィルタコマンドを実装する。

ストリーム出力モードとして、後続ツールへ渡す拡張 JSON Lines（`--format=jsonl`）と、OKF Markdown ドキュメント直接出力（`--format=markdown`）の双方をサポートする。

---

## 2. トレーサビリティ / Traceability
- 要求仕様書: [docs/requirements/REQ-01-system_requirements.md](../requirements/REQ-01-system_requirements.md) (`REQ-FR-02`, `REQ-FR-09`)
- 基本設計書: [docs/designs/DSN-01-high_level_design.md](../designs/DSN-01-high_level_design.md) (`5.2 CLI Stream Pipeline Protocol`)
- 基底依存: Issue #429 (`src/cli/stream.py`), [src/pipeline/transformer](file:///workspace/arxiv-security-papers/src/pipeline/transformer)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] `src/cli/commands/okf_convert.py` (新規作成: OkfConvertCommand)
- [ ] `src/cli/registry.py` (okf-convert サブコマンドの登録)
- [ ] `tests/cli/commands/test_okf_convert.py` (新規単体テスト)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/432-implement-manage-py-okf-convert-stream`

1. **`OkfConvertCommand` の定義**:
   - `src/cli/commands/okf_convert.py` に `OkfConvertCommand(BaseCommand)` を作成。
   - 引数オプション:
     - `--format` (`jsonl` または `markdown`, デフォルト: `jsonl`)
     - `--save-dir` (指定された場合、ディスク上の `outputs/okf/papers/YYYY-MM-DD/` にも保存)
     - `--on-error=skip|abort`
2. **OKF 変換とプロバナンス付与**:
   - `src/pipeline/transformer/okf_serializer.py` を活用。
   - Google OKF v0.2 必須キー（`type: "security-paper"`, `title`, `description`, `resource`, `tags`, `timestamp`, `provenance`, `trust`）を生成。
   - セキュリティタグ付与（`tagger.py`）を実行。
3. **ストリーム送出**:
   - `format=jsonl`: OKF オブジェクト（`okf_yaml`, `markdown_body`, `tags` 等）を含むレコードを stdout に 1行1JSON で出力。
   - `format=markdown`: 完全な Markdown ドキュメントを出力。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] `cat extracted.jsonl | python manage.py okf-convert` で、Google OKF v0.2 フィールドを含む JSONL が stdout に流れること。
- [ ] `python manage.py okf-convert --format=markdown` で有効な YAML フロントマター付き Markdown が stdout に出力されること。
- [ ] 単体テストがパスし、品質ゲートを満たすこと。
