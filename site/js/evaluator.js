/**
 * Markdown Evaluator Module
 * Traverses AST nodes, transforms inline syntax (**bold**, `code`, [link](url)),
 * and assigns unique IDs for Mermaid diagrams.
 */

class MarkdownEvaluator {
  constructor() {
    this.mermaidCount = 0;
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
          code: node.payload.code
        }
      };
    }

    return { ...node, evaluated: node.payload };
  }

  /**
   * @param {string} text
   * @return {string}
   * @private
   */
  _evaluateInlineText(text) {
    if (!text) return '';

    let result = text;
    // Bold: **text**
    result = result.replace(/\*\*(.*?)\*\*/g, '<strong>$1</strong>');
    // Inline code: `code`
    result = result.replace(/`([^`]+)`/g, '<code class="inline-code">$1</code>');
    // Links: [text](url)
    result = result.replace(/\[([^\]]+)\]\(([^)]+)\)/g, '<a href="$2" target="_blank" rel="noopener noreferrer">$1</a>');

    return result;
  }
}

if (typeof module !== 'undefined' && module.exports) {
  module.exports = { MarkdownEvaluator };
}
