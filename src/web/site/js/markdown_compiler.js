/**
 * Unified Markdown Compiler Engine Orchestrator
 * Integrates Lexer, Parser, Evaluator, and Renderer modules into a cohesive API.
 */
'use strict';

class MarkdownCompilerEngine {
  constructor() {
    this.lexer = new MarkdownLexer();
    this.parser = new MarkdownParser();
    this.evaluator = new MarkdownEvaluator();
    this.renderer = new MarkdownRenderer();
  }

  /**
   * @param {string} rawMarkdown
   * @return {{html: string, mermaidElements: !Array<?>}}
   */
  compile(rawMarkdown) {
    const tokens = this.lexer.tokenize(rawMarkdown);
    const ast = this.parser.parse(tokens);
    const evaluatedAst = this.evaluator.evaluate(ast);
    const result = this.renderer.render(evaluatedAst);
    return result;
  }

  /**
   * Render Mermaid blocks individually with isolated error boundaries.
   * @param {!Element} containerElement
   * @return {!Promise<void>}
   */
  async renderMermaid(containerElement) {
    if (typeof mermaid !== 'undefined' && containerElement) {
      try {
        mermaid.initialize({
          startOnLoad: false,
          theme: 'dark',
          securityLevel: 'loose'
        });
      } catch (initErr) {
        console.warn("Mermaid initialize warning:", initErr);
      }

      const nodes = containerElement.querySelectorAll('.mermaid');
      for (let i = 0; i < nodes.length; i++) {
        const node = nodes[i];
        try {
          await mermaid.run({
            nodes: [node]
          });
        } catch (elemErr) {
          console.warn("Individual Mermaid rendering failed on node:", node, elemErr);
          // Fallback UI to prevent broken raw text or red screen
          const rawCode = node.textContent || '';
          node.className = 'md-mermaid-fallback-container';
          node.innerHTML = `
            <div class="md-mermaid-fallback">
              <div class="md-mermaid-fallback-header">
                <span class="md-mermaid-fallback-badge">⚠️ 描画フォールバック</span>
              </div>
              <pre class="md-code-block"><code class="language-mermaid">${rawCode}</code></pre>
            </div>
          `;
        }
      }
    }
  }
}

window.MarkdownCompiler = new MarkdownCompilerEngine();
