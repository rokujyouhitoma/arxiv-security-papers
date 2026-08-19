/**
 * Markdown Renderer Module
 * Transforms AST nodes into CSS-styled HTML5 elements (.md-table, .md-h1~.md-h3, .md-blockquote)
 * and asynchronously calls mermaid.run() to render Mermaid code blocks graphically.
 */

class MarkdownRenderer {
  /**
   * @param {!Object} evaluatedAst
   * @return {{html: string, mermaidElements: !Array<?>}}
   */
  render(evaluatedAst) {
    if (!evaluatedAst || evaluatedAst.type !== 'DOCUMENT') {
      return { html: '', mermaidElements: [] };
    }
    const htmlParts = [];
    const mermaidElements = [];

    for (const node of evaluatedAst.children) {
      const ev = node['evaluated'] || {};

      switch (node.type) {
        case 'HEADING':
          htmlParts.push(`<h${ev.level} class="md-h${ev.level}">${ev.content}</h${ev.level}>`);
          break;

        case 'PARAGRAPH':
          htmlParts.push(`<p class="md-p">${ev.content}</p>`);
          break;

        case 'HR':
          htmlParts.push(`<hr class="md-hr" />`);
          break;

        case 'BLOCKQUOTE':
          htmlParts.push(`<blockquote class="md-blockquote">${ev.content}</blockquote>`);
          break;

        case 'LIST':
          const itemsHtml = ev.items.map(item => `<li>${item}</li>`).join('');
          htmlParts.push(`<ul class="md-list">${itemsHtml}</ul>`);
          break;

        case 'TABLE':
          const ths = ev.headers.map(h => `<th>${h}</th>`).join('');
          const trs = ev.rows.map(r => `<tr>${r.map(c => `<td>${c}</td>`).join('')}</tr>`).join('');
          htmlParts.push(`
            <div class="md-table-wrapper">
              <table class="md-table">
                <thead><tr>${ths}</tr></thead>
                <tbody>${trs}</tbody>
              </table>
            </div>
          `);
          break;

        case 'MERMAID':
          mermaidElements.push(ev);
          htmlParts.push(`
            <div class="md-mermaid-wrapper">
              <div class="mermaid" id="${ev.elementId}">
${ev.code}
              </div>
            </div>
          `);
          break;

        case 'CODE_BLOCK':
          htmlParts.push(`
            <pre class="md-code-block"><code class="language-${ev.lang}">${ev.code}</code></pre>
          `);
          break;

        default:
          break;
      }
    }

    return {
      html: htmlParts.join('\n'),
      mermaidElements
    };
  }
}

if (typeof module !== 'undefined' && module.exports) {
  module.exports = { MarkdownRenderer };
}
