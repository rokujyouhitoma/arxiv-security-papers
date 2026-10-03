---
ID: 430
種別: Feature
優先度: High
ステータス: Open (New)
---

# [FEAT] manage.py fetch 論文メタデータ取得ストリームサブコマンドの実装 (ID: 430)

## 1. 概要 / Summary
`REQ-FR-09` および `DSN-01 Section 5.2` のパイプライン第1ステージとして、arXiv API および RSS フィードから論文メタデータを取得し、行指向ストリーム（JSON Lines）として標準出力（stdout）にリアルタイム送出する `manage.py fetch` コマンドを実装する。

進捗表示やネットワーク再試行メッセージはすべて `stderr` に出力し、stdout には純粋なメタデータレコードのみを流すことで、後続の Unix コマンドや抽出フィルタとパイプで直結可能にする。

---

## 2. トレーサビリティ / Traceability
- 要求仕様書: [docs/requirements/REQ-01-system_requirements.md](../requirements/REQ-01-system_requirements.md) (`REQ-FR-01`, `REQ-FR-09`)
- 基本設計書: [docs/designs/DSN-01-high_level_design.md](../designs/DSN-01-high_level_design.md) (`5.2 CLI Stream Pipeline Protocol`)
- 基底依存: Issue #429 (`src/cli/stream.py`)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] `src/cli/commands/fetch.py` (新規作成: FetchCommand)
- [ ] `src/cli/registry.py` (fetch サブコマンドの登録)
- [ ] `tests/cli/commands/test_fetch.py` (新規単体テスト)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/430-implement-manage-py-fetch-stream`

1. **`FetchCommand` の定義**:
   - `src/cli/commands/fetch.py` に `FetchCommand(BaseCommand)` を作成。
   - 引数オプション:
     - `--category` (デフォルト: `cs.CR`)
     - `--limit` (取得件数上限、デフォルト: 20)
     - `--since` (取得開始日時 YYYY-MM-DD)
     - `--source` (`arxiv` または `rss`, デフォルト: `arxiv`)
     - `--stream` (ストリームモード有効フラグ)
2. **データフェッチとストリーム送出**:
   - 既存の `src/pipeline/ingestion/` アダプターを呼び出し。
   - 1件フェッチされるごとに、`StreamWriter` を介して stdout に JSONL 行を出力。
   - レコード内容: `arxiv_id`, `title`, `authors`, `abstract`, `published`, `categories`, `pdf_url`。
3. **診断ログの分離**:
   - HTTP 通信状況、取得件数カウンターは `DiagnosticLogger` を通じて stderr に出力。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] `python manage.py fetch --limit 5` を実行した際、stdout に 5 行の JSONL が出力されること。
- [ ] `python manage.py fetch --limit 5 | jq -r '.title'` がエラーなく実行でき、タイトル一覧が取得できること。
- [ ] 進捗ログが stdout に混入せず、すべて stderr に出力されること。
- [ ] 単体テストがパスし、品質ゲートを満たすこと。
