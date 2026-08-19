/**
 * @fileoverview Closure Compiler Externs Definition
 * @externs
 */

/**
 * @type {{
 *   initialize: function(!Object): void,
 *   run: function(!Object): void,
 *   render: function(string, string, function(string): void): void
 * }}
 */
var mermaid;

/**
 * @type {{
 *   compile: function(string): {html: string, mermaidElements: !Array<?>},
 *   renderMermaid: function(!Element): !Promise<void>
 * }}
 */
var MarkdownCompiler;

/** @type {function(string): string} */
var escapeHtml;

/** @type {function(string): !Promise<void>} */
var openPaperModal;
