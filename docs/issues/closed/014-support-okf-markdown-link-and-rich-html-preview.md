---
ID: 014
種別: Feature / UI/UX / Architecture
優先度: High
ステータス: Closed (Completed)
完了日: 2026-08-16
---

# [FEAT/UIUX] OKF .md プレーンテキスト配信 ＆ 独立 HTML プレビュー画面の実装と検索結果リンク配置 (ID: 014)

## 1. 概要 / Summary
ユーザー指示および UI/UX 設計に基づき、以下の 3 点を明確に分離・実装しました：

1. **`.md` ファイルのプレーンテキスト直接配信**:
   - `/outputs/okf_papers/YYYY-MM-DD/<id>.md` は **純粋な生の Google OKF v0.2 Markdown（`Content-Type: text/plain; charset=utf-8`）** として直接配信。
2. **独立 HTML プレビュー画面（`/preview/<arxiv_id>`）**:
   - 指定された論文の YAML フロントマター、構造化メタデータ、Markdown 本文、および Mermaid 構成図をスタンドアロンの美しい HTML ページ（`Content-Type: text/html; charset=utf-8`）として動的レンダリングして配信。
3. **検索結果カードおよび全画面モーダルへの両リンク配置**:
   - 検索結果カードのフッターに **`[👁️ プレビュー ↗]`** と **`[📝 .md]`** の 2 つの独立リンクを常設。
   - 全画面モーダルトップバーにも `[arXiv 原本 ↗]`, `[PDF 📄]`, `[OKF .md 📝]` を配置。

---

## 2. 完了条件 (DoD) 検証結果
- [x] `/outputs/okf_papers/YYYY-MM-DD/<id>.md` が `text/plain; charset=utf-8` として生マークダウンを返却すること。
- [x] `/preview/<arxiv_id>` が `text/html; charset=utf-8` として美しいスタンドアロンプレビューを返却すること。
- [x] 検索結果カード内に `[👁️ プレビュー ↗]` と `[📝 .md]` の両方のリンクが配置され機能すること。
- [x] `make build_js`（Google Closure Compiler）、`mypy`、`flake8` が 100% オールグリーンで通過すること。
