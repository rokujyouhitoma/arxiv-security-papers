/**
 * Markdown Lexer / Tokenizer Module
 * Tokenizes raw markdown text into structured token streams:
 * HEADING, TABLE, MERMAID, CODE_BLOCK, LIST, BLOCKQUOTE, HR, PARAGRAPH.
 */

class MarkdownLexer {
  /**
   * @param {string} rawMarkdown
   * @return {!Array<!Object>}
   */
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

if (typeof module !== 'undefined' && module.exports) {
  module.exports = { MarkdownLexer };
}
