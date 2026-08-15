---
name: git-workflow
description: arxiv-security-papers リポジトリにおけるブランチ命名規則、Conventional Commitメッセージ、Issueクローズ標準フローを規定するGit運用スキル。
---
# git-workflow

本スキルは、`arxiv-security-papers` リポジトリにおけるGitブランチの作成、コミットメッセージ、およびIssue完了・クローズ処理の標準化を規定します。

## Instructions

1. **Branch Naming (ブランチ命名規則)**:
   - 全ての実装・修正作業はタスク専用のフィーチャーブランチを作成して行ってください。
   - フォーマット: `<type>/<issue-id>-<lowercase-hyphenated-description>`
   - 利用可能な type:
     - `feat`: 新機能（新しい取得ロジック、OKF拡張、新サマリー機能等）
     - `fix`: パイプラインバグ修正・フォールバック通信修正
     - `docs`: アーキテクチャドキュメント・サマリーテンプレート・Issue更新のみ
     - `refactor`: パイプライン・OKF変換エンジンのリファクタリング
     - `pipeline`: 定期自動バッチ処理・定期フェッチ設定の最適化
     - `test`: 品質ゲート・テストスイートの追加・更新
   - 例: `feat/001-arxiv-rss-fallback`, `pipeline/002-annual-summary-generator`

2. **Commit Message Format (コミットメッセージ)**:
   - Conventional Commits フォーマットを使用してください。
   - フォーマット: `<type>(<optional-scope>): <summary> (ID: <issue-id>)`
   - 例:
     ```
     feat(fetcher): add arXiv RSS feed automatic fallback mechanism (ID: 001)

     - Support falling back to https://rss.arxiv.org/rss/cs.CR when arXiv API fails
     - Preserve raw metadata JSON and full-text extraction pipeline
     ```

3. **Issue Completion / Close Workflow (Issueクローズ標準フロー)**:
   1. **ドキュメント整合性検証**: `docs/` 配下のアーキテクチャドキュメント（要件書・HLD・LLD）と実装コードの整合性を確認。
   2. **Issue ステータス更新**: `docs/issues/` 配下の該当 Issue ファイルを開き、ヘッダーの `ステータス` を `In Progress` から `Closed` に更新。
   3. **アーカイブ移動**: `mv docs/issues/<issue-id>-<title>.md docs/issues/closed/` で closed ディレクトリへ移動。
   4. **Issue 台帳更新**: `docs/issues/README.md` の一覧テーブルでステータスを `Closed` に更新し、リンクを `closed/<issue-id>-<title>.md` に変更。
