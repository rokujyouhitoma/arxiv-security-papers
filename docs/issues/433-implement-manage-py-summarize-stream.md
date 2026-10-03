---
ID: 433
種別: Feature
優先度: High
ステータス: Open (New)
---

# [FEAT] manage.py summarize 日本語エグゼクティブ要約ストリームフィルタの実装 (ID: 433)

## 1. 概要 / Summary
`REQ-FR-09` および `DSN-01 Section 5.2` のパイプライン第4ステージとして、標準入力（stdin）から OKF 変換済み論文レコード（JSON Lines）を受け取り、自然言語処理基盤（`src/nlp`）を用いて 100% 日本語の構造化要約（背景、脅威/攻撃手法、対策/防御、評価）を生成・付加した JSON Lines を標準出力（stdout）に流す `manage.py summarize` フィルタコマンドを実装する。

単体実行により、外部スクリプトや AI エージェントが論文メタデータをパイプで渡すだけで、即座に高品質な日本語要約結果を取り出せるようにする。

---

## 2. トレーサビリティ / Traceability
- 要求仕様書: [docs/requirements/REQ-01-system_requirements.md](../requirements/REQ-01-system_requirements.md) (`REQ-FR-03`, `REQ-FR-09`)
- 基本設計書: [docs/designs/DSN-01-high_level_design.md](../designs/DSN-01-high_level_design.md) (`5.2 CLI Stream Pipeline Protocol`)
- 基底依存: Issue #429 (`src/cli/stream.py`), [src/nlp](file:///workspace/arxiv-security-papers/src/nlp)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] `src/cli/commands/summarize.py` (新規作成: SummarizeCommand)
- [ ] `src/cli/registry.py` (summarize サブコマンドの登録)
- [ ] `tests/cli/commands/test_summarize.py` (新規単体テスト)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/433-implement-manage-py-summarize-stream`

1. **`SummarizeCommand` の定義**:
   - `src/cli/commands/summarize.py` に `SummarizeCommand(BaseCommand)` を作成。
   - 引数オプション:
     - `--style` (`executive` または `structured`, デフォルト: `executive`)
     - `--on-error=skip|abort`
2. **要約パイプラインの結合**:
   - `src/nlp` 配下の学術文境界解析器 (`academic_segmenter`)、談話構造解析器 (`structured_summarizer`) を使用。
   - 英文 Abstract および 本文テキストから、日本語 1 文エグゼクティブサマリー（`summary_ja`）および 3点構造化要約（`points_ja`）を生成。
3. **ストリーム送出**:
   - 受信した JSON レコードに `summary_ja`, `points_ja` を付加し、`StreamWriter` で stdout に出力。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] `cat okf.jsonl | python manage.py summarize` で、日本語要約が付加された JSONL が stdout に出力されること。
- [ ] `python manage.py fetch --limit 1 | python manage.py pdf-extract | python manage.py okf-convert | python manage.py summarize | jq .summary_ja` が正常な日本語文字列を返すこと。
- [ ] 単体テストがパスし、品質ゲートを満たすこと。
