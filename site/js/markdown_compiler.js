/**
 * Unified Markdown Compiler Engine Orchestrator
 * Integrates Lexer, Parser, Evaluator, and Renderer modules into a cohesive API.
 */

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
        await mermaid.run({
          nodes: containerElement.querySelectorAll('.mermaid')
        });
      } catch (err) {
        console.warn("Mermaid rendering warning:", err);
      }
    }
  }
}

window.MarkdownCompiler = new MarkdownCompilerEngine();
