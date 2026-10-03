---
ID: 428
種別: Feature
優先度: High
ステータス: Closed (Completed)
完了日: 2026-10-04
---

# [FEAT] Unix哲学的ツール間連携（標準入出力・JSON Linesストリーム）の要求仕様・高位設計への統合 (ID: 428)

## 1. 概要 / Summary
「Pure Python 3.14+ / 外部依存ゼロ」という本プロジェクトのコアアイデンティティを堅牢に維持しつつ、Unix哲学（The Unix Philosophy）の中核原則である「ツール間連携（Composition / Pipe & Filter）」と「普遍的テキストストリーム（Universal Text Streams: JSON Lines）」を要求仕様書 (`REQ-01`) および全体高位アーキテクチャ設計書 (`DSN-01`) に正式なシステム要件・設計原則として統合した。

具体的には以下を規定・明文化した：
1. **ストリーム入出力要求の追加 (`REQ-FR-09`)**: 各サブシステム（データ取得、PDFテキスト抽出、OKF変換、要約生成、インデックス登録）が、従来のモノリシックな閉ループ実行だけでなく、標準入出力（stdin/stdout）を介した行指向ストリーム（JSON Lines: `.jsonl`）による疎結合パイプライン処理に対応する機能要求。
2. **合成可能性・疎結合要求の追加 (`REQ-NFR-07`)**: 単機能CLIフィルタとしての合成可能性（Composability）と、診断ログ（stderr）とデータストリーム（stdout）の厳格分離（Rule of Separation / Rule of Silence）を非機能要求として規定。
3. **高位アーキテクチャ設計書 (`DSN-01`) の設計原則拡張**: 第5原則として「Unix Composition & Stream Interoperability（Unix的ツール間連携とストリーム相互運用性）」を策定し、公開インターフェース（Section 5.2）に CLI ストリームパイプラインプロトコルを定義。
4. **全15大専門エージェントによる合意形成の明文化**: PM, Systems Architect (SA), Software Development (SWD), Application Specialist (APS) らによる多角的レビューと合意事項の反映。

---

## 2. トレーサビリティ / Traceability
- 要求仕様書: [docs/requirements/REQ-01-system_requirements.md](../../requirements/REQ-01-system_requirements.md)
- 基本設計書: [docs/designs/DSN-01-high_level_design.md](../../designs/DSN-01-high_level_design.md)
- 関連規定: `.agents/AGENTS.md` (ガバナンス・品質基準)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [docs/requirements/REQ-01-system_requirements.md](../../requirements/REQ-01-system_requirements.md) (REQ-FR-09, REQ-NFR-07 の追記)
- [x] [docs/designs/DSN-01-high_level_design.md](../../designs/DSN-01-high_level_design.md) (1.3 設計原則の拡張、3.2 責務マトリクス、5.2 CLIストリームパイプラインプロトコル、2 協議議事録の更新)
- [x] [docs/issues/README.md](../README.md) (Issue台帳の管理)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/428-incorporate-unix-composition-into-requirements-and-design`

1. **`docs/requirements/REQ-01-system_requirements.md` の更新**:
   - `REQ-FR-09: ツール間連携・標準ストリーム (stdin/stdout) インターフェース要求` を追加。
   - `REQ-NFR-07: 疎結合性・合成可能性 (Composability) 要求` を追加。
2. **`docs/designs/DSN-01-high_level_design.md` の更新**:
   - Section 1.3 を「5大設計原則」に改定し、第5原則「Unix Composition & Stream Interoperability（Unix的ツール間連携とストリーム相互運用性）」を新設。
   - Section 2 の専門エージェント協議に、自前主義とUnixパイプライン思想を統合する多角的合意を反映。
   - Section 5 に「5.2 CLI ストリームパイプラインプロトコル（JSON Lines Filter Protocol）」を新設し、`manage.py` を介した stdin/stdout フィルタ連携データフローを定義。
3. **品質検証**:
   - 全体リンク整合性（相対パス遵守）、マークダウン構文確認。

---

## 5. 完了条件 / Success Criteria (DoD)
- [x] `REQ-01` に `REQ-FR-09`（機能要求）および `REQ-NFR-07`（非機能要求）が明文化されていること。
- [x] `DSN-01` に第5の設計原則として「Unix Composition & Stream Interoperability」が定義されていること。
- [x] `DSN-01` の公開インターフェース仕様に、JSON Lines ストリームパイプラインプロトコルが定義されていること。
- [x] すべての内部リンクが相対パス（`.md`）で統一され、デッドリンクが存在しないこと。
- [x] Issue台帳（`docs/issues/README.md`）が正しく同期されていること。
