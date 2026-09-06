#!/usr/bin/env python3
"""
HTML Template and Preview Renderer for arXiv Security Papers.
Generates glassmorphic preview documents for Google OKF v0.2 markdown files.
"""

import html
import json
import re
from typing import Any, Dict

from domain.source_resolver import resolve_paper_source_info


def extract_paper_preview_metadata(content: str) -> Dict[str, Any]:
    """
    Extracts title, authors, date, and tags from OKF markdown frontmatter.
    """
    title_m = re.search(r"^title:\s*[\"']?(.*?)[\"']?$", content, re.MULTILINE)
    title = title_m.group(1).strip() if title_m else "OKF Paper Preview"

    authors_m = re.search(r"^authors:\s*\[(.*?)\]", content, re.MULTILINE)
    authors_str = authors_m.group(1).strip() if authors_m else ""

    tags_m = re.search(r"^tags:\s*\[(.*?)\]", content, re.MULTILINE)
    tags_str = tags_m.group(1).strip() if tags_m else ""

    date_m = re.search(
        r"^timestamp:\s*[\"']?([0-9]{4}-[0-9]{2}-[0-9]{2})", content, re.MULTILINE
    )
    date_str = date_m.group(1) if date_m else ""

    return {
        "title": title,
        "authors": authors_str,
        "tags": tags_str,
        "date": date_str,
    }


def render_okf_preview_html(
    arxiv_id: str,
    content: str,
    raw_md_path: str = "",
) -> str:
    """
    Renders standalone preview HTML embedding MarkdownCompiler JS scripts.
    """
    meta = extract_paper_preview_metadata(content)
    title = meta["title"]
    authors_str = meta["authors"]
    tags_str = meta["tags"]
    date_str = meta["date"]

    source_info = resolve_paper_source_info(arxiv_id)
    paper_badge = source_info["label"]
    source_abs_url = source_info["abs_url"]
    source_pdf_url = source_info["pdf_url"]
    source_name = source_info["source_name"]

    escaped_content = json.dumps(content, ensure_ascii=False)

    return f"""<!DOCTYPE html>
<html lang="ja">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>{html.escape(title)} - Google OKF Preview</title>
  <link rel="stylesheet" href="/style.css">
  <script src="https://cdn.jsdelivr.net/npm/mermaid/dist/mermaid.min.js"></script>
  <script src="/js/lexer.js"></script>
  <script src="/js/parser.js"></script>
  <script src="/js/evaluator.js"></script>
  <script src="/js/renderer.js"></script>
  <script src="/js/markdown_compiler.js"></script>
</head>
<body style="background: var(--bg-dark); color: var(--text-primary); margin: 0; padding: 2rem 1rem;">
  <div style="max-width: 1080px; margin: 0 auto;">
    <div class="glass-panel" style="padding: 1.5rem; margin-bottom: 2rem;">
      <div style="display: flex; justify-content: space-between; align-items: center; flex-wrap: wrap; gap: 1rem;">
        <div style="display: flex; gap: 0.5rem; align-items: center;">
          <span class="modal-badge">Google OKF v0.2</span>
          <span class="arxiv-id-tag">{html.escape(paper_badge)}</span>
        </div>
        <div style="display: flex; gap: 0.5rem; flex-wrap: wrap;">
          <a href="{html.escape(raw_md_path)}" class="btn-link-action" target="_blank"
             rel="noopener">📝 生の Markdown (.md)</a>
          <a href="{html.escape(source_abs_url)}" class="btn-link-action" target="_blank"
             rel="noopener">{html.escape(source_name)} 原本 ↗</a>
          <a href="{html.escape(source_pdf_url)}" class="btn-link-action" target="_blank"
             rel="noopener">PDF 📄</a>
          <a href="/" class="btn-link-action">🏠 ポータル</a>
        </div>
      </div>
      <h1 style="font-size: 1.6rem; color: #fff; margin: 0.5rem 0;">{html.escape(title)}</h1>
      <div style="font-size: 0.85rem; color: #94a3b8; display: flex; gap: 1.5rem; flex-wrap: wrap; margin-top: 0.8rem;">
        <div>👥 <strong>著者:</strong> {html.escape(authors_str)}</div>
        <div>📅 <strong>公開日:</strong> {html.escape(date_str)}</div>
        <div>🏷️ <strong>タグ:</strong> {html.escape(tags_str)}</div>
      </div>
    </div>
    <div id="previewBody" class="glass-panel" style="padding: 2.5rem; line-height: 1.75;">
      <p style="color: #94a3b8;">ドキュメントをレンダリング中...</p>
    </div>
  </div>
  <script>
    document.addEventListener('DOMContentLoaded', () => {{
      const rawContent = {escaped_content};
      const container = document.getElementById('previewBody');
      if (window.MarkdownCompiler) {{
        const compiled = window.MarkdownCompiler.compile(rawContent);
        container.innerHTML = compiled.html;
        window.MarkdownCompiler.renderMermaid(container);
      }} else {{
        container.innerText = rawContent;
      }}
    }});
  </script>
</body>
</html>"""
