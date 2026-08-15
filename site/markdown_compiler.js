/**
 * Markdown Compiler Engine (Lexer, Parser, AST, Evaluator, Renderer)
 * High-performance, zero-dependency Markdown & Mermaid transpiler for arXiv Security Papers Web UI.
 */

class MarkdownLexer {
  tokenize(rawMarkdown) {
    if (!rawMarkdown) return [];
    const lines = rawMarkdown.replace(/\r\n/g, '\n').split('\n');
    const tokens = [];
    let i = 0;

    while (i < lines.length) {
      const line = lines[i];
      const trimmed = line.trim();

      // Skip empty lines
      if (!trimmed) {
        i++;
        continue;
      }

      // 1. Fenced Code Block or Mermaid Block
      if (trimmed.startsWith('```')) {
        const lang = trimmed.replace(/^```/, '').trim();
        const codeLines = [];
        i++;
        while (i < lines.length && !lines[i].trim().startsWith('```')) {
          codeLines.push(lines[i]);
          i++;
        }
        i++; // skip closing ```
        
        if (lang.toLowerCase() === 'mermaid') {
          tokens.push({ type: 'MERMAID', code: codeLines.join('\n') });
        } else {
          tokens.push({ type: 'CODE_BLOCK', lang: lang || 'text', code: codeLines.join('\n') });
        }
        continue;
      }

      // 2. Headings (# H1, ## H2, ### H3, #### H4)
      const headingMatch = line.match(/^(#{1,6})\s+(.*)$/);
      if (headingMatch) {
        tokens.push({
          type: 'HEADING',
          level: headingMatch[1].length,
          content: headingMatch[2].trim()
        });
        i++;
        continue;
      }

      // 3. Horizontal Rule (--- or ***)
      if (/^(\-{3,}|\*{3,})$/.test(trimmed)) {
        tokens.push({ type: 'HR' });
        i++;
        continue;
      }

      // 4. Tables (| Col1 | Col2 |)
      if (trimmed.startsWith('|') && trimmed.endsWith('|')) {
        const tableLines = [];
        while (i < lines.length && lines[i].trim().startsWith('|') && lines[i].trim().endsWith('|')) {
          tableLines.push(lines[i].trim());
          i++;
        }
        if (tableLines.length >= 2) {
          const parseRow = row => row.split('|').slice(1, -1).map(c => c.trim());
          const headers = parseRow(tableLines[0]);
          // Check if second line is separator | --- | --- |
          let startRowIdx = 1;
          if (tableLines[1].includes('---')) {
            startRowIdx = 2;
          }
          const rows = tableLines.slice(startRowIdx).map(parseRow);
          tokens.push({ type: 'TABLE', headers, rows });
        }
        continue;
      }

      // 5. Unordered List Items (- item or * item)
      if (/^[\-\*]\s+/.test(trimmed)) {
        const listItems = [];
        while (i < lines.length && /^[\-\*]\s+/.test(lines[i].trim())) {
          listItems.push(lines[i].trim().replace(/^[\-\*]\s+/, ''));
          i++;
        }
        tokens.push({ type: 'LIST', items: listItems });
        continue;
      }

      // 6. Blockquote (> text)
      if (trimmed.startsWith('>')) {
        const quoteLines = [];
        while (i < lines.length && lines[i].trim().startsWith('>')) {
          quoteLines.push(lines[i].trim().replace(/^>\s?/, ''));
          i++;
        }
        tokens.push({ type: 'BLOCKQUOTE', content: quoteLines.join(' ') });
        continue;
      }

      // 7. Standard Paragraph
      tokens.push({ type: 'PARAGRAPH', content: trimmed });
      i++;
    }

    return tokens;
  }
}

class MarkdownParser {
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

class MarkdownRenderer {
  render(evaluatedAst) {
    if (!evaluatedAst || evaluatedAst.type !== 'DOCUMENT') return '';
    const htmlParts = [];
    const mermaidElements = [];

    for (const node of evaluatedAst.children) {
      const ev = node.evaluated;

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

// Unified Markdown Compiler Interface
class MarkdownCompilerEngine {
  constructor() {
    this.lexer = new MarkdownLexer();
    this.parser = new MarkdownParser();
    this.evaluator = new MarkdownEvaluator();
    this.renderer = new MarkdownRenderer();
  }

  compile(rawMarkdown) {
    const tokens = this.lexer.tokenize(rawMarkdown);
    const ast = this.parser.parse(tokens);
    const evaluatedAst = this.evaluator.evaluate(ast);
    const result = this.renderer.render(evaluatedAst);
    return result;
  }

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
