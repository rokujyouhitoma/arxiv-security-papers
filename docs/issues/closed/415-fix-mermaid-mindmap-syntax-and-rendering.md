---
ID: 415
種別: Bug
優先度: High
ステータス: Closed
完了日: 2026-10-03
---

# [BUG] Mermaid mindmap 構文エラーの解消とトレンド分析マインドマップ描画の正常化 (ID: 415)

## 1. 概要 / Summary
「📊 階層別エグゼクティブサマリー & トレンド分析 (`http://localhost:8000/?tab=trends#/trends`)」画面において、「🗺️ 月次セキュリティ技術レーダー (Technology Radar)」の Mermaid マインドマップが図としてレンダリングされず、生テキストのまま崩れて表示される不具合が発生していた。

### 再現手順 / Steps to Reproduce
1. Web サーバーを起動 (`make run_web`)
2. ブラウザで `http://localhost:8000/?tab=trends#/trends` を開く
3. 「🗺️ 月次セキュリティ技術レーダー (Technology Radar)」の箇所を確認する
4. Mermaid 図ではなく、以下のような生の mindmap 構文テキストが改行崩れを起こして表示されている：
   `mindmap root((セキュリティ動向 月次 2026-10-01)) 量子暗号_ゼロ知識証明技術["量子暗号 & ゼロ知識証明技術 (18件)"] ["unknown（セキュリティ分析論文）"] ...`

### 再現環境 / Environment
- OS: Linux
- Components: `src/nlp/clustering/trend_analyzer.py`, `src/pipeline/reporter/diagram_generator.py`, `site/js/evaluator.js`, `site/js/renderer.js`, `site/js/markdown_compiler.js`

---

## 2. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [src/nlp/clustering/trend_analyzer.py](../../src/nlp/clustering/trend_analyzer.py): Mermaid mindmap のノード出力構文（`node_id` の除去と `["label"]` 形式への準拠）
- [x] [src/pipeline/reporter/diagram_generator.py](../../src/pipeline/reporter/diagram_generator.py): `generate_mermaid_mindmap` および `_build_trend_mindmap_lines` の mindmap 構文是正
- [x] [site/js/evaluator.js](../../site/js/evaluator.js): MERMAID ノード評価時の `elementId` プロパティ付与
- [x] [site/js/renderer.js](../../site/js/renderer.js): MERMAID ノードレンダリング時の ID 解決の堅牢化 (`ev.elementId || ev.id`)
- [x] [site/app-min.js](../../site/app-min.js): Closure Compiler 最適化 JS バンドルの再ビルド

---

## 3. 根本原因分析 (RCA) / Root Cause Analysis
1. **Mermaid Mindmap 構文違反**:
   - `src/nlp/clustering/trend_analyzer.py` の `_render_mindmap_node` において、`node_id["label"]` という Flowchart 用の構文を出力していた。Mermaid v10 の Mindmap 構文ではノード ID は不要であり、`node_id["label"]` を記述すると構文エラー（Syntax error）を引き起こす。
   - さらに、ラベルテキスト中に丸括弧 `(18件)` や特殊文字が含まれる場合、Mindmap のノード形状判定と衝突して構文エラーを引き起こしていた。
   - `AI_LLM_セキュリティ_敵対的攻撃` などの同一ノード ID が複数行で重複出力されていた。
2. **フロントエンドの ID 参照不整合 & エラーハンドリング**:
   - `site/js/evaluator.js` では `evaluated: { id: diagramId, code: ... }` と設定しているにもかかわらず、`site/js/renderer.js` では `<div class="mermaid" id="${ev.elementId}">` と `ev.elementId` を参照しており、DOM 上で `id="undefined"` となっていた。
   - `site/js/markdown_compiler.js` の `renderMermaid` において、`mermaid.run()` が構文エラーで例外を投げた際、単に `console.warn` で握りつぶされ、`<div class="mermaid">` 内の生テキストが CSS の通常ブロックとして崩れて表示されていた。

---

## 4. 暫定対処と恒久対策 / Workaround & Permanent Fix
* **暫定対処 (Workaround)**: なし
* **恒久対策 (Permanent Fix)**:
  - `src/nlp/clustering/trend_analyzer.py` の Mindmap 生成ロジックを Mermaid v10 公式仕様に完全準拠させる。ノードは `    ["カテゴリ名 (18件)"]` のように二重引用符付きの角括弧形状とし、ID を付与しない。
  - `src/pipeline/reporter/diagram_generator.py` の mindmap 生成ロジックも同様に `    ["ラベル (件数)"]` 形式に統一。
  - フロントエンド `site/js/evaluator.js` / `renderer.js` のプロパティ名不整合（`id` vs `elementId`）を是正。
  - `make build_js` でフロントエンドをコンパイル。

---

## 5. 実装方針 / Implementation Plan
Target Branch: `fix/415-mermaid-mindmap-syntax`

1. `src/nlp/clustering/trend_analyzer.py` を修正：
   - `_render_mindmap_node`: `node_id` を排し、`    ["{safe_label} ({count}件)"]` 形式に変更。
   - `_build_mermaid_mindmap_tree`: `root` ノードを `root["セキュリティ動向 ({safe_date})"]` 形式に変更。
2. `src/pipeline/reporter/diagram_generator.py` を修正：
   - `generate_mermaid_mindmap`: `lines.append(f'    ["{safe_cat} ({count} papers)"]')`
   - `_build_trend_mindmap_lines`: `lines.append(f'    ["{safe_kw} ({count} 件)"]')`
3. `site/js/evaluator.js` および `site/js/renderer.js` を修正し、`elementId` を整合させる。
4. `make build_js` でフロントエンドを再コンパイル。
5. 単体テストを追加し、生成された mindmap 構文が Mermaid 仕様を満たすことを検証。

---

## 6. 完了条件 / Success Criteria (DoD)
- [x] 生成される Mermaid mindmap コードに `node_id["..."]` が含まれず、Mermaid v10 でエラーなくパースできること
- [x] フロントエンドの DOM において `id="undefined"` が解消され、有効な要素 ID が付与されること
- [x] `make build_js`, `make test`, `make static_analysis` がすべて PASS すること
