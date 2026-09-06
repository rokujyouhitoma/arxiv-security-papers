---
ID: 177
種別: Bug
優先度: High
ステータス: Closed
---

# [BUG] IACR ePrint 論文に対する「arXiv:」プレフィックス誤表記の解消およびマルチソース（arXiv/IACR）動的リンク解決の実装 (ID: 177)

## 1. 概要 / Summary

CTI ナレッジグラフ（`dashboard.html`）の Context Mesh（コンテキストグラフ）において、`Target Subsystem` などのエンティティノードを選択した際、接続されている論文（Sources クラスタ）の Relations 表示に以下のような不自然な表記が発生していることが報告された。

```text
Target Subsystem
Core subsystem protected in AI & Neural Subsystems
Relations (8):
targets ← arXiv: iacr-2026-386
protects ← Model Guardrails & Boundary Verification
targets ← arXiv: iacr-2026-1846
targets ← arXiv: iacr-2026-1845
targets ← arXiv: iacr-2026-1844
targets ← arXiv: iacr-2026-1693
targets ← arXiv: iacr-2026-1587
targets ← arXiv: iacr-2026-1533
```

`iacr-2026-386` などの ID は、arXiv ではなく **IACR ePrint (International Association for Cryptologic Research - eprint.iacr.org)** 由来の暗号学プレプリント論文である。本リポジトリは IACR ePrint 収集機能（`IacrEprintSourceAdapter`）を備え、現在 60 件以上の IACR 論文を正規データとして保持しているが、グラフ生成部や Web コンソール UI、OKF シリアライザー等の各所で論文プレフィックスが「`arXiv:`」と固定でハードコードされているため、誤った表記およびリンク切れ（存在しない arXiv URL への遷移）が発生している。

### 再現手順 / Steps to Reproduce
1. Web ゲートウェイを起動し、`/dashboard?tab=graph&mode=context` にアクセスする。
2. グラフ上のエンティティノード（例: `Target Subsystem`）をクリックしてノード詳細インスペクター（`#nodeCallout`）を表示する。
3. `Relations` リストを確認すると、IACR 論文であるにもかかわらず `targets ← arXiv: iacr-2026-386` と表示される。
4. また、`/`（ポータル）で `iacr-2026-386` のカードを開き、詳細モーダルの「arXiv 原本 ↗」をクリックすると `https://arxiv.org/abs/iacr-2026-386`（404 Not Found）へ遷移してしまう。

### 再現環境 / Environment
- OS / Env: Linux / Pure-Python Web Gateway & Presentation Engine
- Target Files: `src/web/gateway/handlers.py`, `site/app.js`, `src/web/presentation/template.py`, `src/pipeline/transformer/okf_serializer.py`

---

## 2. 影響範囲と関連ファイル / Scope and Affected Files

- [x] [src/domain/source_resolver.py](../../src/domain/source_resolver.py) (新規ソース解決ヘルパー)
- [x] [src/web/gateway/handlers.py](../../src/web/gateway/handlers.py) (Context Mesh 構築時のノードタイトルプレフィックス動的解決)
- [x] [site/app.js](../../site/app.js) (論文カード ID バッジ表示およびモーダル原本リンク URL 動的解決)
- [x] [site/dashboard.html](../../site/dashboard.html) (Context Mesh ノード詳細インスペクターにおける原本リンク表示)
- [x] [site/index.html](../../site/index.html) (モーダル ID バッジ初期プレースホルダー)
- [x] [src/web/presentation/template.py](../../src/web/presentation/template.py) (HTML プレビューテンプレートのバッジ表示および原本リンク)
- [x] [src/pipeline/transformer/okf_serializer.py](../../src/pipeline/transformer/okf_serializer.py) (OKF Markdown 本文中の原題/ID表記)
- [x] [tests/web/test_dashboard_html.py](../../tests/web/test_dashboard_html.py) (マルチソース解決・IACR/arXiv リンク自動回帰テスト)

---

## 3. 根本原因分析 (RCA) / Root Cause Analysis

1. **Context Mesh ノード生成時のハードコード (`src/web/gateway/handlers.py:312`)**:
   `_build_dynamic_paper_mesh()` において、Sources ノードの `title` が一律 `f"arXiv: {clean_id}"` とハードコードされていた。
2. **Web UI におけるソース種別判定の欠如 (`site/app.js:516, 567-569, 636`)**:
   カードおよびモーダルで `arxiv-id-tag` に対し `arXiv: ${paper.id}` を強制設定し、リンク先も `https://arxiv.org/abs/${arxivId}` を固定生成していた（正規の IACR URL である `https://eprint.iacr.org/2026/386` になっていない）。
3. **HTML プレビューテンプレートの固定表記 (`src/web/presentation/template.py:75, 80-82`)**:
   プレビューヘッダーで `arXiv: {html.escape(arxiv_id)}` および `https://arxiv.org/abs/...` が固定されていた。
4. **OKF シリアライザーの固定記述 (`src/pipeline/transformer/okf_serializer.py:43, 303`)**:
   `f"本論文「{title_ja}」（原題: {title} / arXiv: {arxiv_id}）は、"` と出力されていた。

---

## 4. 暫定対処と恒久対策 / Workaround & Permanent Fix

* **暫定対処 (Workaround)**:
  `dashboard.html` の Relations 一覧およびポータルのモーダル表示時に、クライアントサイド JS で `clean_id` の接頭辞（`iacr-`）を判定して表記を置換する。
* **恒久対策 (Permanent Fix)**:
  1. Python 側および JavaScript 側の双方に、論文 ID またはソース種別に応じた共通ヘルパー関数（`resolve_paper_source_info(paper_id)`）を導入。
     - `iacr-YYYY-NNN` の場合:
       - 表示ラベル: `IACR: YYYY/NNN` (例: `IACR: 2026/386`)
       - ソース名称: `IACR ePrint`
       - 原本 URL: `https://eprint.iacr.org/YYYY/NNN`
       - PDF URL: `https://eprint.iacr.org/YYYY/NNN.pdf`
     - 通常 arXiv ID（`YYMM.NNNNN` 等）の場合:
       - 表示ラベル: `arXiv: {paper_id}`
       - ソース名称: `arXiv`
       - 原本 URL: `https://arxiv.org/abs/{paper_id}`
       - PDF URL: `https://arxiv.org/pdf/{paper_id}.pdf`
  2. `handlers.py`, `app.js`, `template.py`, `okf_serializer.py` で共通ヘルパーを利用し、動的解決を行う。

---

## 5. 実装方針 / Implementation Plan

Target Branch: `fix/177-multi-source-paper-prefix-and-links-arxiv-iacr`

1. **Python 側ヘルパー実装 (`src/web/gateway/handlers.py`, `src/web/presentation/template.py`)**:
   - `resolve_paper_source_info(clean_id: str)` 関数を実装:
     - 入力 ID のプレフィックス（`iacr-`）を解析し、正規化された表示ラベル（`IACR: YYYY/NNN`）、原本リンク、PDF リンク、ソース名を返却。
   - `_build_dynamic_paper_mesh()`:
     - `node_dict[s_id]["title"]` を `f"arXiv: {clean_id}"` から `resolve_paper_source_info(clean_id)["label"]` に変更。
   - `src/web/presentation/template.py`:
     - `render_okf_preview_html()` 内で `resolve_paper_source_info()` を呼び出し、バッジおよびリンク先（原本・PDF）を動的生成。
   - `src/pipeline/transformer/okf_serializer.py`:
     - `iacr-` 論文の場合に `IACR: ...` 表記および `IACR ID` を出力するよう補正。

2. **Frontend 側ヘルパー実装 (`site/app.js`, `site/index.html`)**:
   - `site/app.js` に `resolvePaperSourceInfo(paperId)` を実装。
   - カード描画（通常カードおよび関連論文トポロジーカード）で `arxiv-id-tag` に動的ラベルを適用。
   - モーダル表示処理（`openPaperModal`）で、モーダルタイトルバッジ、原本リンク（テキストと href）、PDF リンク（href）を動的設定。

3. **自動回帰テストの拡充**:
   - `tests/web/test_dashboard_graph_tab.py`:
     - Context Mesh に IACR 論文が含まれる場合に `IACR: 2026/386` としてノードタイトルが生成され、`arXiv:` が付与されないことを検証。
   - `tests/web/test_dashboard_html.py`:
     - 単体プレビュー（`/preview/iacr-2026-386`）が正しい IACR リンクおよびバッジをレンダリングすることを検証。

---

## 6. 完了条件 / Success Criteria (DoD)

- [x] `dashboard.html` の Context Mesh において、IACR 論文ノードおよび Relations 表示が `arXiv: iacr-...` ではなく `IACR: 2026/386` と表示されること。
- [x] `site/app.js` およびポータル画面において、IACR 論文カードのバッジが `IACR: 2026/386` と表示され、原本リンクをクリックすると正しく `https://eprint.iacr.org/...` へ遷移すること。
- [x] 単体 HTML プレビュー（`/preview/<clean_id>`）で、IACR 論文の原本・PDF リンクが正常に IACR ePrint を参照すること。
- [x] 相対リンク規約（`AGENTS.md`）に違反しないこと（絶対パス `file:///` ゼロ件）。
- [x] `make check_format`, `make static_analysis`, `make test` が 100% PASS すること。
