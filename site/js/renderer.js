/**
 * Markdown Renderer Module
 * Transforms AST nodes into CSS-styled HTML5 elements (.md-table, .md-h1~.md-h3, .md-blockquote)
 * and asynchronously calls mermaid.run() to render Mermaid code blocks graphically.
 * Includes MermaidValidator pre-validation, auto-sanitization, and safe fallback rendering.
 */
'use strict';

class MarkdownRenderer {
  constructor() {
    /** @type {?Object} */
    this.mermaidValidator_ = null;
  }

  /**
   * Retrieves or initializes the MermaidValidator instance.
   * @private
   * @return {?Object}
   */
  getMermaidValidator_() {
    if (this.mermaidValidator_) {
      return this.mermaidValidator_;
    }
    if (typeof window !== 'undefined' && window.MermaidValidator) {
      this.mermaidValidator_ = new window.MermaidValidator();
      return this.mermaidValidator_;
    }
    if (typeof window !== 'undefined' && window.Application && window.Application.frameworks && window.Application.frameworks.MermaidValidator) {
      this.mermaidValidator_ = new window.Application.frameworks.MermaidValidator();
      return this.mermaidValidator_;
    }
    if (typeof module !== 'undefined' && typeof require === 'function') {
      try {
        const { MermaidValidator } = require('./frameworks/mermaid-validator.js');
        this.mermaidValidator_ = new MermaidValidator();
        return this.mermaidValidator_;
      } catch (e) {
        // Fallback if not loadable in environment
      }
    }
    return null;
  }

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
    const validator = this.getMermaidValidator_();

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
          const listTag = ev.ordered ? 'ol' : 'ul';
          const itemsHtml = ev.items.map(item => `<li>${item}</li>`).join('');
          htmlParts.push(`<${listTag} class="md-list">${itemsHtml}</${listTag}>`);
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
          let codeToRender = ev.code || '';
          let isValid = true;
          let errorHint = '';

          if (validator) {
            const valRes = validator.validate(codeToRender);
            if (!valRes.valid) {
              const sanitized = validator.sanitize(codeToRender);
              if (sanitized) {
                codeToRender = sanitized;
              } else {
                isValid = false;
                errorHint = valRes.error || 'Syntax error';
              }
            }
          }

          if (isValid) {
            const safeEv = Object.assign({}, ev, { code: codeToRender });
            mermaidElements.push(safeEv);
            const elemId = safeEv.elementId || safeEv.id || `mermaid-${Math.random().toString(36).substring(2, 7)}`;
            htmlParts.push(`
              <div class="md-mermaid-wrapper">
                <div class="mermaid" id="${elemId}">
${codeToRender}
                </div>
              </div>
            `);
          } else if (validator && typeof validator.createFallbackHtml === 'function') {
            htmlParts.push(validator.createFallbackHtml(codeToRender, errorHint));
          } else {
            // Default safe code fallback
            htmlParts.push(`
              <div class="md-mermaid-fallback">
                <pre class="md-code-block"><code class="language-mermaid">${codeToRender}</code></pre>
              </div>
            `);
          }
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
