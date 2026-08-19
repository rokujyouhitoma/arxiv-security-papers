/**
 * Markdown Parser Module
 * Builds Abstract Syntax Tree (DocumentNode AST) with node hierarchy from token streams.
 */

class MarkdownParser {
  /**
   * @param {!Array<!Object>} tokens
   * @return {!Object}
   */
  parse(tokens) {
    const root = { type: 'DOCUMENT', children: [] };
    for (const token of tokens) {
      root.children.push({
        type: token.type,
        payload: token,
        children: []
      });
    }
    return root;
  }
}

if (typeof module !== 'undefined' && module.exports) {
  module.exports = { MarkdownParser };
}
