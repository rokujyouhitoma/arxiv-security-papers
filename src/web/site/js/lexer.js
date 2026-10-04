/**
 * Markdown Lexer / Tokenizer Module
 * Tokenizes raw markdown text into structured token streams:
 * HEADING, TABLE, MERMAID, CODE_BLOCK, LIST, BLOCKQUOTE, HR, PARAGRAPH.
 *
 * Powered by PEG (Parsing Expression Grammar) row tokenizer for tables (DSN-25 / Issue 418),
 * protecting escaped pipes \| and inline code spans `|`.
 */
'use strict';

class MarkdownLexer {
  constructor() {
    /** @type {?Object} */
    this._pegRowParser = null;
    this._initPegParser();
  }

  /**
   * Initializes or caches the PEG table row parser if PEG runtime is available.
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
        const seq = peg.seq;
        const opt = peg.opt;

        // 1. Escaped pipe \| or other escape \.
        const escaped = reg(/\\./);

        // 2. Code span `...` (protects pipes inside)
        const codeSpan = reg(/`[^`\r\n]*`/);

        // 3. Regular cell text (any character except |, `, \)
        const normalText = reg(/[^|`\\\r\n]+/);

        // 4. Fallback character
        const fallbackChar = reg(/[^|\r\n]/);

        const cellChar = choice([escaped, codeSpan, normalText, fallbackChar]);
        const cell = star(cellChar).map(items => items.join('').trim());

        const pipe = reg(/\s*\|\s*/);
        const nextCell = seq([pipe, cell]).map(parts => parts[1]);

        // Complete row: opt(|) + cell + star(| + cell) + opt(|)
        this._pegRowParser = seq([
          opt(pipe),
          cell,
          star(nextCell),
          opt(pipe)
        ]).map(parts => {
          const first = parts[1];
          const rest = parts[2] || [];
          return [first].concat(rest);
        });
      } catch (err) {
        this._pegRowParser = null;
      }
    }
  }

  /**
   * Parses a single table row line into trimmed cell strings.
   * Correctly preserves escaped pipes (\|) and pipes within inline code (`|`).
   *
   * @param {string} rowLine
   * @return {!Array<string>}
   */
  parseTableRow(rowLine) {
    if (!rowLine) return [];
    const trimmed = rowLine.trim();

    // Try PEG combinator parser first
    if (this._pegRowParser) {
      try {
        const parsed = this._pegRowParser.parse(trimmed);
        if (parsed && Array.isArray(parsed) && parsed.length > 0) {
          return this._normalizeParsedCells(trimmed, parsed);
        }
      } catch (e) {
        // Fallback to deterministic linear scanner
      }
    }

    return this._scanTableRowCells(trimmed);
  }

  /**
   * Deterministic linear Packrat/PEG scanner for table cells.
   * Guarantees O(N) execution with zero ReDoS risk.
   *
   * @param {string} text
   * @return {!Array<string>}
   * @private
   */
  _scanTableRowCells(text) {
    let s = text.trim();
    // Strip leading border pipe if present
    if (s.startsWith('|')) {
      s = s.slice(1);
    }
    // Strip trailing border pipe if present (and not escaped)
    if (s.endsWith('|') && !s.endsWith('\\|')) {
      s = s.slice(0, -1);
    }

    const cells = [];
    let current = '';
    let i = 0;

    while (i < s.length) {
      const ch = s[i];

      // 1. Escaped character
      if (ch === '\\' && i + 1 < s.length) {
        current += ch + s[i + 1];
        i += 2;
        continue;
      }

      // 2. Inline code span: protect all inner pipes
      if (ch === '`') {
        const closeIdx = s.indexOf('`', i + 1);
        if (closeIdx !== -1) {
          current += s.slice(i, closeIdx + 1);
          i = closeIdx + 1;
          continue;
        }
      }

      // 3. Cell delimiter
      if (ch === '|') {
        cells.push(current.trim());
        current = '';
        i++;
        continue;
      }

      current += ch;
      i++;
    }

    cells.push(current.trim());
    return cells;
  }

  /**
   * @param {string} originalLine
   * @param {!Array<string>} cells
   * @return {!Array<string>}
   * @private
   */
  _normalizeParsedCells(originalLine, cells) {
    const result = cells.slice();
    if (originalLine.startsWith('|') && result.length > 0 && result[0] === '') {
      result.shift();
    }
    if (originalLine.endsWith('|') && !originalLine.endsWith('\\|') && result.length > 0 && result[result.length - 1] === '') {
      result.pop();
    }
    return result;
  }

  /**
   * Tests whether a row line is a markdown table separator (e.g. |:---|:---:|---:|).
   *
   * @param {string} line
   * @return {boolean}
   */
  isTableSeparator(line) {
    const cells = this.parseTableRow(line);
    if (cells.length === 0) return false;
    return cells.every(c => /^:?-+:?$/.test(c));
  }

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

      // 2. Headings (# H1, ## H2, ### H3, #### H4, ##### H5, ###### H6)
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

      // 3. Horizontal Rule (---, ***, ___)
      if (/^(\-{3,}|\*{3,}|_{3,})$/.test(trimmed)) {
        tokens.push({ type: 'HR' });
        i++;
        continue;
      }

      // 4. Tables (| Col1 | Col2 | or Col1 | Col2)
      if (trimmed.includes('|')) {
        const hasNextLine = i + 1 < lines.length;
        const nextIsSeparator = hasNextLine && this.isTableSeparator(lines[i + 1].trim());

        if (nextIsSeparator || (trimmed.startsWith('|') && trimmed.endsWith('|') && hasNextLine)) {
          const tableLines = [];
          while (i < lines.length && lines[i].trim().includes('|') && lines[i].trim().length > 0) {
            tableLines.push(lines[i].trim());
            i++;
          }
          if (tableLines.length >= 2) {
            const headers = this.parseTableRow(tableLines[0]);
            let startRowIdx = 1;
            let alignments = [];

            if (this.isTableSeparator(tableLines[1])) {
              const sepCells = this.parseTableRow(tableLines[1]);
              alignments = sepCells.map(c => {
                const left = c.startsWith(':');
                const right = c.endsWith(':');
                if (left && right) return 'center';
                if (right) return 'right';
                if (left) return 'left';
                return 'default';
              });
              startRowIdx = 2;
            }

            const rows = tableLines.slice(startRowIdx).map(r => this.parseTableRow(r));
            tokens.push({ type: 'TABLE', headers, rows, alignments });
            continue;
          }
        }
      }

      // 5. Ordered and Unordered List Items
      const unorderedMatch = line.match(/^\s*[\-\*+]\s+(.*)$/);
      const orderedMatch = line.match(/^\s*(\d+)\.\s+(.*)$/);

      if (unorderedMatch || orderedMatch) {
        const isOrdered = !!orderedMatch;
        const listItems = [];
        const pattern = isOrdered ? /^\s*\d+\.\s+(.*)$/ : /^\s*[\-\*+]\s+(.*)$/;

        while (i < lines.length) {
          const match = lines[i].match(pattern);
          if (!match) break;
          listItems.push(match[1].trim());
          i++;
        }
        tokens.push({ type: 'LIST', items: listItems, ordered: isOrdered });
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

if (typeof window !== 'undefined') {
  window.MarkdownLexer = MarkdownLexer;
  const App = window.Application = window.Application || {};
  const frameworks = App.frameworks = App.frameworks || {};
  frameworks.MarkdownLexer = MarkdownLexer;
}

if (typeof module !== 'undefined' && module.exports) {
  module.exports = { MarkdownLexer };
}
