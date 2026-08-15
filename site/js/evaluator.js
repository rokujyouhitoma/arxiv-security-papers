/**
 * Markdown Evaluator Module
 * Traverses AST nodes, transforms inline syntax (**bold**, `code`, [link](url)),
 * and assigns unique IDs for Mermaid diagrams.
 */

class MarkdownEvaluator {
  constructor() {
    this.mermaidCount = 0;
  }

  evaluate(ast) {
    this.mermaidCount = 0;
    return this._evaluateNode(ast);
  }

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
        evaluated: { items }
      };
    }

    if (node.type === 'MERMAID') {
      this.mermaidCount++;
      return {
        ...node,
        evaluated: {
          code: node.payload.code,
          elementId: `mermaid-diagram-${this.mermaidCount}-${Date.now()}`
        }
      };
    }

    return { ...node, evaluated: node.payload };
  }

  _evaluateInlineText(text) {
    if (!text) return '';
    let result = text;
    // 1. Escape HTML special chars
    result = result.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
    // 2. Bold: **text**
    result = result.replace(/\*\*(.*?)\*\*/g, '<strong class="md-bold">$1</strong>');
    // 3. Inline Code: `code`
    result = result.replace(/`(.*?)`/g, '<code class="md-inline-code">$1</code>');
    // 4. Links: [text](url)
    result = result.replace(/\[(.*?)\]\((.*?)\)/g, '<a href="$2" class="md-link" target="_blank" rel="noopener">$1</a>');
    return result;
  }
}

if (typeof module !== 'undefined' && module.exports) {
  module.exports = { MarkdownEvaluator };
}
