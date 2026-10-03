(function() {
  'use strict';

/**
 * Supported Mermaid diagram types
 * @const {!Array<string>}
 */
const SUPPORTED_DIAGRAM_TYPES = [
  'mindmap',
  'graph',
  'flowchart',
  'sequenceDiagram',
  'classDiagram',
  'stateDiagram',
  'stateDiagram-v2',
  'erDiagram',
  'gantt',
  'pie',
  'gitGraph',
  'journey',
  'c4Context'
];

/**
 * Escape HTML special characters for safe fallback display.
 * @param {string} str
 * @return {string}
 */
function escapeHtml(str) {
  if (!str) return '';
  return str
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
}

/**
 * Validation Result Type
 * @typedef {{
 *   valid: boolean,
 *   diagramType: string,
 *   error: ?string,
 *   line: number
 * }}
 */
let MermaidValidationResult;

/**
 * Lightweight client-side PEG-based Mermaid Pre-validator and Sanitizer.
 * Inspects diagram syntax before handing it to mermaid.run(), preventing
 * catastrophic rendering exceptions, UI freeze, and ugly red syntax error blocks.
 */
class MermaidValidator {
  constructor() {}

  /**
   * Detects diagram type from source code.
   * @param {string} code
   * @return {string}
   */
  detectType(code) {
    if (!code || typeof code !== 'string') return '';
    const lines = code.split('\n');
    for (let i = 0; i < lines.length; i++) {
      const trimmed = lines[i].trim();
      if (!trimmed || trimmed.startsWith('%%')) continue; // Skip comments and empty lines
      const firstWord = trimmed.split(/[\s(;]/)[0];
      for (let j = 0; j < SUPPORTED_DIAGRAM_TYPES.length; j++) {
        const type = SUPPORTED_DIAGRAM_TYPES[j];
        if (firstWord.toLowerCase() === type.toLowerCase()) {
          return type;
        }
      }
      return '';
    }
    return '';
  }

  /**
   * Validates Mermaid code syntax.
   * @param {string} code
   * @return {{valid: boolean, diagramType: string, error: ?string, line: number}}
   */
  validate(code) {
    if (!code || typeof code !== 'string' || !code.trim()) {
      return {
        valid: false,
        diagramType: '',
        error: 'Empty diagram code',
        line: 0
      };
    }

    const diagramType = this.detectType(code);
    if (!diagramType) {
      return {
        valid: false,
        diagramType: '',
        error: 'Unknown or missing Mermaid diagram header',
        line: 1
      };
    }

    const lines = code.split('\n');

    if (diagramType.toLowerCase() === 'mindmap') {
      return this.validateMindmap_(lines);
    } else if (diagramType.toLowerCase() === 'graph' || diagramType.toLowerCase() === 'flowchart') {
      return this.validateFlowchart_(lines);
    }

    // Generic structural validation for other diagram types
    return this.validateGeneric_(lines, diagramType);
  }

  /**
   * Validates mindmap syntax with indent and label checking.
   * @private
   * @param {!Array<string>} lines
   * @return {{valid: boolean, diagramType: string, error: ?string, line: number}}
   */
  validateMindmap_(lines) {
    let hasRoot = false;
    let inCommentBlock = false;

    for (let i = 0; i < lines.length; i++) {
      const rawLine = lines[i];
      const trimmed = rawLine.trim();
      if (!trimmed) continue;
      if (trimmed.startsWith('%%')) continue;
      if (trimmed.toLowerCase() === 'mindmap') continue;

      // First non-comment line after header must be root
      if (!hasRoot) {
        hasRoot = true;
        // Check for root declaration
        if (trimmed.includes('((') && !trimmed.endsWith('))')) {
          return {
            valid: false,
            diagramType: 'mindmap',
            error: 'Unbalanced root circular brackets ((...))',
            line: i + 1
          };
        }
        continue;
      }

      // Check unbalanced brackets in mindmap nodes
      const roundOpen = (trimmed.match(/\(/g) || []).length;
      const roundClose = (trimmed.match(/\)/g) || []).length;
      const squareOpen = (trimmed.match(/\[/g) || []).length;
      const squareClose = (trimmed.match(/\]/g) || []).length;

      // Inside quotes brackets can be unbalanced, but outside quotes they must be balanced
      const quoteCount = (trimmed.match(/"/g) || []).length;
      if (quoteCount % 2 === 0 && quoteCount === 0) {
        if (roundOpen !== roundClose) {
          return {
            valid: false,
            diagramType: 'mindmap',
            error: 'Unbalanced parentheses in unquoted node label',
            line: i + 1
          };
        }
        if (squareOpen !== squareClose) {
          return {
            valid: false,
            diagramType: 'mindmap',
            error: 'Unbalanced square brackets in unquoted node label',
            line: i + 1
          };
        }
        // Nested unquoted brackets (e.g. Node1(A (B)) or Node2[A [B]] or Node(A [B]))
        const isDoubleCircle = trimmed.includes('((') && trimmed.includes('))');
        const effectiveRound = isDoubleCircle ? (roundOpen - 2) : roundOpen;
        if (effectiveRound > 1 || squareOpen > 1 || (effectiveRound > 0 && squareOpen > 0)) {
          return {
            valid: false,
            diagramType: 'mindmap',
            error: 'Nested brackets without quotes in mindmap node label',
            line: i + 1
          };
        }
      }
    }

    if (!hasRoot) {
      return {
        valid: false,
        diagramType: 'mindmap',
        error: 'Mindmap is missing a root node',
        line: 1
      };
    }

    return {
      valid: true,
      diagramType: 'mindmap',
      error: null,
      line: 0
    };
  }

  /**
   * Validates graph/flowchart syntax.
   * @private
   * @param {!Array<string>} lines
   * @return {{valid: boolean, diagramType: string, error: ?string, line: number}}
   */
  validateFlowchart_(lines) {
    let headerFound = false;

    for (let i = 0; i < lines.length; i++) {
      const trimmed = lines[i].trim();
      if (!trimmed || trimmed.startsWith('%%')) continue;

      if (!headerFound) {
        // e.g. graph TD, flowchart LR
        const match = trimmed.match(/^(?:graph|flowchart)\s+(?:TD|TB|BT|RL|LR)/i);
        if (!match) {
          return {
            valid: false,
            diagramType: 'flowchart',
            error: 'Missing orientation directive (e.g., TD, LR) in flowchart header',
            line: i + 1
          };
        }
        headerFound = true;
        continue;
      }

      // Check for security-sensitive click handlers
      if (/^click\s+/i.test(trimmed)) {
        return {
          valid: false,
          diagramType: 'flowchart',
          error: 'Security violation: click handlers are prohibited',
          line: i + 1
        };
      }

      // Check unbalanced brackets outside quotes
      const quotes = (trimmed.match(/"/g) || []).length;
      if (quotes % 2 === 0 && quotes === 0) {
        const roundOpen = (trimmed.match(/\(/g) || []).length;
        const roundClose = (trimmed.match(/\)/g) || []).length;
        const squareOpen = (trimmed.match(/\[/g) || []).length;
        const squareClose = (trimmed.match(/\]/g) || []).length;

        if (roundOpen !== roundClose || squareOpen !== squareClose) {
          return {
            valid: false,
            diagramType: 'flowchart',
            error: 'Unbalanced brackets in statement',
            line: i + 1
          };
        }
      }
    }

    return {
      valid: true,
      diagramType: 'flowchart',
      error: null,
      line: 0
    };
  }

  /**
   * Generic structural validation for other diagram types.
   * @private
   * @param {!Array<string>} lines
   * @param {string} diagramType
   * @return {{valid: boolean, diagramType: string, error: ?string, line: number}}
   */
  validateGeneric_(lines, diagramType) {
    for (let i = 0; i < lines.length; i++) {
      const trimmed = lines[i].trim();
      if (!trimmed || trimmed.startsWith('%%')) continue;

      // Strip dangerous HTML script tags
      if (/<script/i.test(trimmed)) {
        return {
          valid: false,
          diagramType: diagramType,
          error: 'Security violation: script tag detected',
          line: i + 1
        };
      }
    }

    return {
      valid: true,
      diagramType: diagramType,
      error: null,
      line: 0
    };
  }

  /**
   * Sanitizes broken Mermaid code to fix common syntax issues (e.g. unquoted nested brackets in mindmaps).
   * Returns sanitized code string, or null if cannot be safely recovered.
   * @param {string} code
   * @return {?string}
   */
  sanitize(code) {
    if (!code || typeof code !== 'string') return null;

    const validation = this.validate(code);
    if (validation.valid) {
      return code;
    }

    const lines = code.split('\n');
    const sanitizedLines = [];
    const diagramType = this.detectType(code).toLowerCase();

    // Remove dangerous directives first (XSS / click handlers)
    const filteredLines = lines.filter(l => {
      const t = l.trim();
      return !/^click\s+/i.test(t) && !/<script/i.test(t);
    });

    if (diagramType === 'mindmap') {
      // Mindmap sanitization: quote labels containing unquoted nested parens or brackets
      let hasRoot = false;

      for (let i = 0; i < filteredLines.length; i++) {
        const rawLine = filteredLines[i];
        const trimmed = rawLine.trim();

        if (!trimmed || trimmed.startsWith('%%')) {
          sanitizedLines.push(rawLine);
          continue;
        }

        if (trimmed.toLowerCase() === 'mindmap') {
          sanitizedLines.push(rawLine);
          continue;
        }

        const indentMatch = rawLine.match(/^(\s*)/);
        const indent = indentMatch ? indentMatch[1] : '';

        // If line contains unbalanced parentheses or brackets, wrap label in quotes
        let lineContent = trimmed;

        // Pattern 1: root node fix
        if (!hasRoot) {
          hasRoot = true;
          if (lineContent.startsWith('root(') && !lineContent.endsWith(')')) {
            const inner = lineContent.slice(5).replace(/\)+$/, '');
            lineContent = `root("${inner}")`;
          } else if (lineContent.startsWith('root[') && !lineContent.endsWith(']')) {
            const inner = lineContent.slice(5).replace(/\]+$/, '');
            lineContent = `root["${inner}"]`;
          }
          sanitizedLines.push(indent + lineContent);
          continue;
        }

        // Pattern 2: node with label syntax like Node1(Label (Extra)) or Node2[Label [Extra]]
        const nodeMatch = lineContent.match(/^([a-zA-Z0-9_-]+)?(\(\(|\(|\[|\{)(.*)(\)\)|\)|\]|\})$/);
        if (nodeMatch) {
          const id = nodeMatch[1] || '';
          const openB = nodeMatch[2];
          let inner = nodeMatch[3];
          const closeB = nodeMatch[4];
          if (!inner.startsWith('"') || !inner.endsWith('"')) {
            inner = `"${inner.replace(/"/g, "'")}"`;
          }
          lineContent = `${id}${openB}${inner}${closeB}`;
        } else if (lineContent.startsWith('[') && lineContent.endsWith(']') && !lineContent.startsWith('["')) {
          const inner = lineContent.slice(1, -1).replace(/"/g, "'");
          lineContent = `["${inner}"]`;
        } else if (lineContent.startsWith('(') && lineContent.endsWith(')') && !lineContent.startsWith('("')) {
          const inner = lineContent.slice(1, -1).replace(/"/g, "'");
          lineContent = `("${inner}")`;
        } else if (lineContent.startsWith('((') && lineContent.endsWith('))') && !lineContent.startsWith('(("')) {
          const inner = lineContent.slice(2, -2).replace(/"/g, "'");
          lineContent = `(("${inner}"))`;
        } else if ((lineContent.includes('(') || lineContent.includes('[')) && !lineContent.includes('"')) {
          // General unquoted label containing parens
          const cleanLabel = lineContent.replace(/"/g, "'");
          lineContent = `["${cleanLabel}"]`;
        }

        sanitizedLines.push(indent + lineContent);
      }

      const result = sanitizedLines.join('\n');
      const testVal = this.validate(result);
      if (testVal.valid) {
        return result;
      }
    } else if (diagramType === 'graph' || diagramType === 'flowchart') {
      // Flowchart header fix: add default TD if orientation missing
      for (let i = 0; i < filteredLines.length; i++) {
        let line = filteredLines[i];
        if (i === 0 || sanitizedLines.length === 0) {
          const t = line.trim();
          if (/^graph$/i.test(t)) {
            line = 'graph TD';
          } else if (/^flowchart$/i.test(t)) {
            line = 'flowchart TD';
          }
        }
        sanitizedLines.push(line);
      }
      const result = sanitizedLines.join('\n');
      const testVal = this.validate(result);
      if (testVal.valid) {
        return result;
      }
    }

    return null; // Could not safely sanitize
  }

  /**
   * Generates a safe fallback HTML block for invalid Mermaid diagrams,
   * avoiding red syntax error blocks and preserving diagnostics.
   * @param {string} code
   * @param {string} errorHint
   * @return {string}
   */
  createFallbackHtml(code, errorHint) {
    const safeCode = escapeHtml(code);
    const safeHint = escapeHtml(errorHint || 'Syntax Error');
    return `
      <div class="md-mermaid-fallback">
        <div class="md-mermaid-fallback-header">
          <span class="md-mermaid-fallback-badge">⚠️ ダイアグラム構文警告</span>
          <span class="md-mermaid-fallback-hint">${safeHint}</span>
        </div>
        <pre class="md-code-block"><code class="language-mermaid">${safeCode}</code></pre>
      </div>
    `.trim();
  }
}

  // Export to global scope & Application frameworks namespace
  if (typeof window !== 'undefined') {
    window.MermaidValidator = MermaidValidator;

    window.Application = window.Application || {};
    window.Application.frameworks = window.Application.frameworks || {};
    window.Application.frameworks.MermaidValidator = MermaidValidator;
    window.App = window.Application;
    window.yuzora = window.Application;
  }

  // Export for Node.js / CommonJS testing
  if (typeof module !== 'undefined' && module.exports) {
    module.exports = {
      MermaidValidator: MermaidValidator
    };
  }
})();
