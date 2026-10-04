/**
 * Markdown Evaluator Module
 * Traverses AST nodes, transforms inline syntax (**bold**, `code`, [link](url), escapes),
 * and assigns unique IDs for Mermaid diagrams.
 * Powered by PEG (Parsing Expression Grammar) runtime engine (DSN-25 / Issue 417).
 */
'use strict';

class MarkdownEvaluator {
  constructor() {
    this.mermaidCount = 0;
    this._pegParser = null;
    this._initPegParser();
  }

  /**
   * Initializes or caches the PEG inline syntax parser.
   * @private
   */
  _initPegParser() {
    let peg = null;
    if (typeof window !== 'undefined' && window.Application && window.Application.frameworks && window.Application.frameworks.peg) {
      peg = window.Application.frameworks.peg;
    } else if (typeof require !== 'undefined') {
      try {
        const qv = require('./frameworks/query-validator.js');
        peg = qv.peg;
      } catch (e) {
        // PEG runtime not directly accessible via require
      }
    }

    if (peg && typeof peg.choice === 'function' && typeof peg.reg === 'function') {
      try {
        const reg = peg.reg;
        const choice = peg.choice;
        const star = peg.star;

        // 1. Escaped characters: \* \` \[ \] \( \) \\
        const escaped = reg(/\\([*`[\]()\\])/).map(m => this._escapeHtml(m[1]));

        // 2. Inline Code Span: `...` (Highest precedence, protects inner formatting)
        const codeSpan = reg(/`([^`]+)`/).map(m => {
          const inner = m.slice(1, -1);
          return `<code class="inline-code">${this._escapeHtml(inner)}</code>`;
        });

        // 3. Bold: **...** (inner evaluated for nested formatting)
        const bold = reg(/\*\*([^*]+)\*\*/).map(m => {
          const inner = m.slice(2, -2);
          return `<strong>${this._evaluateInlineText(inner)}</strong>`;
        });

        // 4. Link: [label](url) (label can contain nested inline markup)
        const link = reg(/\[([^\]]+)\]\(([^)\s]+)\)/).map(m => {
          const match = m.match(/\[([^\]]+)\]\(([^)\s]+)\)/);
          const label = this._evaluateInlineText(match[1]);
          const url = this._escapeHtml(match[2]);
          return `<a href="${url}" target="_blank" rel="noopener noreferrer">${label}</a>`;
        });

        // 5. Plain text segment (characters up to the next special delimiter)
        const plainText = reg(/[^\\*`[]+/);

        // 6. Single fallback character (unmatched delimiter or symbol)
        const fallback = reg(/[\s\S]/);

        const inlineItem = choice([codeSpan, escaped, bold, link, plainText, fallback]);
        this._pegParser = star(inlineItem).map(items => items.join(''));
      } catch (err) {
        this._pegParser = null;
      }
    }
  }

  /**
   * @param {string} str
   * @return {string}
   * @private
   */
  _escapeHtml(str) {
    if (!str) return '';
    return String(str)
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;')
      .replace(/'/g, '&#39;');
  }

  /**
   * @param {!Object} ast
   * @return {!Object}
   */
  evaluate(ast) {
    this.mermaidCount = 0;
    return this._evaluateNode(ast);
  }

  /**
   * @param {!Object} node
   * @return {!Object}
   * @private
   */
  _evaluateNode(node) {
    if (node.type === 'DOCUMENT') {
      return {
        ...node,
        children: node.children.map(child => this._evaluateNode(child))
      };
    }

    if (node.type === 'HEADING' || node.type === 'PARAGRAPH' || node.type === 'BLOCKQUOTE') {
      const content = node.payload.content || '';
      const evaluatedContent = this._evaluateInlineText(content);
      return {
        ...node,
        evaluated: { ...node.payload, content: evaluatedContent }
      };
    }

    if (node.type === 'TABLE') {
      const headers = node.payload.headers.map(h => this._evaluateInlineText(h));
      const rows = node.payload.rows.map(row => row.map(cell => this._evaluateInlineText(cell)));
      return {
        ...node,
        evaluated: { headers, rows }
      };
    }

    if (node.type === 'LIST') {
      const items = node.payload.items.map(item => this._evaluateInlineText(item));
      return {
        ...node,
        evaluated: { ...node.payload, items }
      };
    }

    if (node.type === 'MERMAID') {
      this.mermaidCount++;
      const diagramId = `mermaid-diagram-${this.mermaidCount}-${Math.random().toString(36).substring(2, 7)}`;
      return {
        ...node,
        evaluated: {
          id: diagramId,
          elementId: diagramId,
          code: node.payload.code
        }
      };
    }

    return { ...node, evaluated: node.payload };
  }

  /**
   * Evaluates inline markdown text using PEG parser with robust fallback.
   * @param {string} text
   * @return {string}
   * @private
   */
  _evaluateInlineText(text) {
    if (!text) return '';

    // If PEG parser is not initialized, attempt re-initialization
    if (!this._pegParser) {
      this._initPegParser();
    }

    if (this._pegParser) {
      try {
        const result = this._pegParser.parse(text);
        if (typeof result === 'string') {
          return result;
        }
      } catch (err) {
        // Fall through to fallback on syntax edge cases
      }
    }

    // Fallback parser if PEG runtime is unavailable
    let result = text;
    // Escapes: \* \`
    result = result.replace(/\\([*`[\]()\\])/g, '$1');
    // Inline code: `code`
    result = result.replace(/`([^`]+)`/g, '<code class="inline-code">$1</code>');
    // Bold: **text**
    result = result.replace(/\*\*(.*?)\*\*/g, '<strong>$1</strong>');
    // Links: [text](url)
    result = result.replace(/\[([^\]]+)\]\(([^)\s]+)\)/g, '<a href="$2" target="_blank" rel="noopener noreferrer">$1</a>');

    return result;
  }
}

if (typeof module !== 'undefined' && module.exports) {
  module.exports = { MarkdownEvaluator };
}
