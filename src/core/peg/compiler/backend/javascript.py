#!/usr/bin/env python3
"""
JavaScript Code Generator (Emitter) for PEG Grammar AST.
Conforms to DSN-25 Phase 2 Ahead-of-Time PEG Compiler specification.
Converts GrammarDef AST into standalone, high-performance JavaScript parser modules.
Zero external dependencies.
"""

from __future__ import annotations

import json
import re
from typing import Callable, ClassVar, Dict, List, Optional, Set, Tuple, Type, cast

from core.peg.compiler.ast_nodes import (
    ActionExpr,
    AnyCharExpr,
    CharClassExpr,
    ChoiceExpr,
    CutExpr,
    Expression,
    GrammarDef,
    LitExpr,
    NamedExpr,
    OptExpr,
    PredExpr,
    RegexExpr,
    RepeatExpr,
    RuleRefExpr,
    SeqExpr,
)
from core.peg.compiler.backend.base import BaseCodeGenerator


def _collect_flag_chars(raw_flags: str) -> str:
    valid = {"i", "m", "s"}
    return "".join(sorted({ch for ch in raw_flags.lower() if ch in valid}))


def _extract_regex_flags(pattern: str) -> Tuple[str, str]:
    """Extracts inline Python regex flags like (?i) and converts to JS RegExp flags."""
    clean = pattern[1:] if pattern.startswith("^") else pattern
    match = re.match(r"^\(\?([a-zA-Z]+)\)", clean)
    if not match:
        return clean.replace("/", "\\/"), ""
    flags = _collect_flag_chars(match.group(1))
    escaped = clean[match.end() :].replace("/", "\\/")
    return escaped, flags


def _format_repetition(inner: str, min_c: int, max_c: Optional[int]) -> str:
    """Formats repetition combinator with single branch evaluation."""
    if max_c is None and min_c in (0, 1):
        return f"plus({inner})" if min_c == 1 else f"star({inner})"
    max_str = "null" if max_c is None else str(max_c)
    return f"new Repetition({inner}, {min_c}, {max_str})"


def _unescape_class_char(char: str) -> str:
    escapes = {
        "n": "\n",
        "t": "\t",
        "r": "\r",
        "\\": "\\",
        "]": "]",
        "-": "-",
        "/": "/",
    }
    return escapes.get(char, char)


def _tokenize_class_spec(spec: str) -> List[Tuple[str, bool]]:
    tokens: List[Tuple[str, bool]] = []
    i = 0
    n = len(spec)
    while i < n:
        if spec[i] == "\\" and i + 1 < n:
            tokens.append((_unescape_class_char(spec[i + 1]), True))
            i += 2
        else:
            tokens.append((spec[i], False))
            i += 1
    return tokens


def _parse_class_tokens(
    tokens: List[Tuple[str, bool]],
) -> Tuple[List[List[int]], List[int]]:
    ranges: List[List[int]] = []
    singles: Set[int] = set()
    i = 0
    n = len(tokens)
    while i < n:
        if i + 2 < n and not tokens[i + 1][1] and tokens[i + 1][0] == "-":
            s_ord = ord(tokens[i][0])
            e_ord = ord(tokens[i + 2][0])
            ranges.append([min(s_ord, e_ord), max(s_ord, e_ord)])
            i += 3
        else:
            singles.add(ord(tokens[i][0]))
            i += 1
    ranges.sort(key=lambda r: r[0])
    return ranges, sorted(list(singles))


def _parse_char_class_spec(
    spec: str,
) -> Tuple[List[List[int]], List[int]]:
    tokens = _tokenize_class_spec(spec)
    return _parse_class_tokens(tokens)


class JSCodeGenerator(BaseCodeGenerator):
    """Generates standalone, optimized JavaScript source code for a GrammarDef AST."""

    _EXPR_EMITTERS: ClassVar[
        Dict[
            Type[Expression],
            Callable[["JSCodeGenerator", Expression, str], str],
        ]
    ] = {
        LitExpr: lambda self, e, r: f"lit({json.dumps(cast(LitExpr, e).value)})",
        RegexExpr: lambda self, e, r: self._emit_regex(cast(RegexExpr, e)),
        CharClassExpr: lambda self, e, r: self._emit_char_class(cast(CharClassExpr, e)),
        AnyCharExpr: lambda self, e, r: "anyChar()",
        CutExpr: lambda self, e, r: "cut()",
        RuleRefExpr: lambda self, e, r: f"this._r_{cast(RuleRefExpr, e).name}",
        OptExpr: lambda self, e, r: f"opt({self._emit_expr(cast(OptExpr, e).expr, r)})",
        RepeatExpr: lambda self, e, r: self._emit_repeat(cast(RepeatExpr, e), r),
        PredExpr: lambda self, e, r: self._emit_pred(cast(PredExpr, e), r),
        SeqExpr: lambda self, e, r: self._emit_seq(cast(SeqExpr, e), r),
        ChoiceExpr: lambda self, e, r: self._emit_choice(cast(ChoiceExpr, e), r),
        NamedExpr: lambda self, e, r: self._emit_expr(cast(NamedExpr, e).expr, r),
        ActionExpr: lambda self, e, r: self._emit_action(cast(ActionExpr, e), r),
    }

    def __init__(
        self,
        grammar: GrammarDef,
        embedded_runtime: bool = True,
        ast_only: bool = False,
    ) -> None:
        super().__init__(grammar)
        self.embedded_runtime = embedded_runtime
        self.ast_only = ast_only
        self.action_counter = 0
        self.action_methods: List[str] = []

    def generate(self) -> str:
        """Generates complete JavaScript module source code."""
        lines: List[str] = [
            "/**",
            f" * Auto-generated Packrat PEG Parser for grammar: {self.grammar.name}",
            " * Conforms to DSN-25 Phase 2 Ahead-of-Time PEG Compiler specification.",
            " * Generated by peg_compiler --target js. DO NOT EDIT DIRECTLY.",
            " */",
            "'use strict';",
            "",
            "(function(global) {",
        ]

        if self.embedded_runtime:
            lines.extend(self._build_embedded_runtime())
        else:
            lines.extend(self._build_external_runtime_resolution())

        lines.extend(self._build_class_definition())
        lines.extend(self._build_module_exports())
        lines.extend(
            [
                "})(typeof window !== 'undefined' ? window : (typeof global !== 'undefined' ? global : this));",
                "",
            ]
        )
        return "\n".join(lines)

    @classmethod
    def generate_runtime_module(cls) -> str:
        """Generates standalone Packrat PEG runtime module (UMD format)."""
        lines: List[str] = [
            "/**",
            " * Standalone Packrat PEG Runtime Engine for Web Frontend & Node.js",
            " * Conforms to DSN-25 Phase 2 Ahead-of-Time PEG Compiler specification.",
            " * Generated by peg_compiler. DO NOT EDIT DIRECTLY.",
            " */",
            "'use strict';",
            "",
            "(function(global) {",
        ]
        lines.extend(cls.get_runtime_body())
        lines.extend(
            [
                "  // --- Section 2: Universal Module Exports for Runtime ---",
                "  var runtimeExports = {",
                "    ParseResult: ParseResult,",
                "    PEGSyntaxError: PEGSyntaxError,",
                "    ParseContext: ParseContext,",
                "    Parser: Parser,",
                "    Literal: Literal,",
                "    Regex: Regex,",
                "    Sequence: Sequence,",
                "    Choice: Choice,",
                "    Repetition: Repetition,",
                "    Optional: Optional,",
                "    Predicate: Predicate,",
                "    Cut: Cut,",
                "    AnyChar: AnyChar,",
                "    CharClass: CharClass,",
                "    RuleRef: RuleRef,",
                "    MappedParser: MappedParser,",
                "    lit: lit,",
                "    reg: reg,",
                "    seq: seq,",
                "    choice: choice,",
                "    star: star,",
                "    plus: plus,",
                "    opt: opt,",
                "    andPred: andPred,",
                "    notPred: notPred,",
                "    cut: cut,",
                "    anyChar: anyChar,",
                "    charClass: charClass",
                "  };",
                "",
                "  if (typeof module !== 'undefined' && module.exports) {",
                "    module.exports = runtimeExports;",
                "  }",
                "  if (typeof window !== 'undefined') {",
                "    window.PEGRuntime = runtimeExports;",
                "    window.Application = window.Application || {};",
                "    window.Application.frameworks = window.Application.frameworks || {};",
                "    window.Application.frameworks.PEGRuntime = runtimeExports;",
                "  }",
                "})(typeof window !== 'undefined' ? window : (typeof global !== 'undefined' ? global : this));",
                "",
            ]
        )
        return "\n".join(lines)

    def _build_external_runtime_resolution(self) -> List[str]:
        """Provides external runtime resolution for modular parser execution."""
        return [
            "  // --- Section 1: External Packrat PEG Runtime Resolution ---",
            "  var runtime = (typeof require === 'function' && typeof module !== 'undefined' && module.exports)",
            "    ? (function() {",
            "        try { return require('./peg-runtime'); } catch(e) {",
            "          return (typeof global !== 'undefined' && global.PEGRuntime) ||",
            "                 (typeof window !== 'undefined' && window.PEGRuntime);",
            "        }",
            "      })()",
            "    : ((typeof window !== 'undefined' && window.PEGRuntime) ||",
            "       (typeof global !== 'undefined' && global.PEGRuntime));",
            "",
            "  if (!runtime) {",
            "    throw new Error('PEGRuntime not found. Ensure peg-runtime.js is loaded ' +",
            f"                    'before {self.grammar.name}Parser.');",
            "  }",
            "",
            "  var ParseResult = runtime.ParseResult;",
            "  var PEGSyntaxError = runtime.PEGSyntaxError;",
            "  var ParseContext = runtime.ParseContext;",
            "  var Parser = runtime.Parser;",
            "  var RuleRef = runtime.RuleRef;",
            "  var Repetition = runtime.Repetition;",
            "  var lit = runtime.lit;",
            "  var reg = runtime.reg;",
            "  var seq = runtime.seq;",
            "  var choice = runtime.choice;",
            "  var star = runtime.star;",
            "  var plus = runtime.plus;",
            "  var opt = runtime.opt;",
            "  var andPred = runtime.andPred;",
            "  var notPred = runtime.notPred;",
            "  var cut = runtime.cut;",
            "  var anyChar = runtime.anyChar;",
            "  var charClass = runtime.charClass;",
            "",
        ]

    def _build_embedded_runtime(self) -> List[str]:
        """Provides minimal self-contained Packrat PEG runtime for standalone execution."""
        return self.get_runtime_body()

    @classmethod
    def get_runtime_body(cls) -> List[str]:
        """Provides full Packrat PEG runtime engine lines."""
        return [
            "  // --- Section 1: Embedded Packrat PEG Runtime Engine ---",
            "  /**",
            "   * @constructor",
            "   * @param {boolean} success",
            "   * @param {*} value",
            "   * @param {number} nextPos",
            "   * @param {?string=} errorMsg",
            "   * @param {boolean=} committed",
            "   */",
            "  function ParseResult(success, value, nextPos, errorMsg, committed) {",
            "    this.success = success;",
            "    this.value = value;",
            "    this.nextPos = nextPos;",
            "    this.errorMsg = errorMsg || null;",
            "    this.committed = committed || false;",
            "  }",
            "",
            "  /**",
            "   * @constructor",
            "   * @param {string} message",
            "   * @param {number=} offset",
            "   * @param {number=} line",
            "   * @param {number=} col",
            "   * @param {Array<string>=} expectedTokens",
            "   * @param {string=} snippet",
            "   */",
            "  function PEGSyntaxError(message, offset, line, col, expectedTokens, snippet) {",
            "    this.name = 'PEGSyntaxError';",
            "    var loc = offset !== undefined ? (' at offset ' + offset + ' (' + line + ':' + col + ')') : '';",
            "    this.message = message + loc;",
            "    this.offset = offset;",
            "    this.line = line;",
            "    this.col = col;",
            "    this.expectedTokens = expectedTokens || [];",
            "    this.snippet = snippet || '';",
            "    this.stack = (new Error()).stack;",
            "  }",
            "  PEGSyntaxError.prototype = Object.create(Error.prototype);",
            "",
            "  /**",
            "   * @constructor",
            "   * @param {string} text",
            "   * @param {number=} maxDepth",
            "   */",
            "  function ParseContext(text, maxDepth) {",
            "    this.text = text;",
            "    this.length = text.length;",
            "    this.maxDepth = maxDepth || 200;",
            "    this.currDepth = 0;",
            "    this.maxPos = 0;",
            "    this.expectedTokens = [];",
            "    this.memo = new Map();",
            "    this.inProgress = new Set();",
            "    this.lrDetected = new Set();",
            "  }",
            "  ParseContext.prototype.updateMaxPos = function(pos, token) {",
            "    if (pos > this.maxPos) {",
            "      this.maxPos = pos;",
            "      this.expectedTokens = [token];",
            "    } else if (pos === this.maxPos && this.expectedTokens.indexOf(token) === -1) {",
            "      this.expectedTokens.push(token);",
            "    }",
            "  };",
            "  ParseContext.prototype.calcLineCol = function(pos) {",
            "    var bounded = Math.max(0, Math.min(pos, this.text.length));",
            "    var prefix = this.text.slice(0, bounded);",
            "    var lines = prefix.split('\\n');",
            "    return { line: lines.length, col: lines[lines.length - 1].length + 1 };",
            "  };",
            "  ParseContext.prototype.getSnippet = function(pos, windowLen) {",
            "    var w = windowLen || 20;",
            "    var start = Math.max(0, pos - w);",
            "    var end = Math.min(this.text.length, pos + w);",
            "    return this.text.slice(start, end);",
            "  };",
            "",
            "  /**",
            "   * @constructor",
            "   * @param {string=} name",
            "   * @param {boolean=} memoize",
            "   */",
            "  function Parser(name, memoize) {",
            "    this.name = name || 'Parser';",
            "    this.memoize = memoize !== false;",
            "    this.ruleId = Parser._nextId++;",
            "  }",
            "  Parser._nextId = 1;",
            "  Parser.prototype.parseAt = function(ctx, pos) {",
            "    throw new Error('parseAt not implemented on ' + this.name);",
            "  };",
            "  Parser.prototype._clearLrDependentMemo = function(ctx, pos, key) {",
            "    var toDelete = [];",
            "    ctx.memo.forEach(function(val, k) {",
            "      if ((k & 0xFFFFF) >= pos && k !== key) {",
            "        toDelete.push(k);",
            "      }",
            "    });",
            "    for (var i = 0; i < toDelete.length; i++) {",
            "      ctx.memo.delete(toDelete[i]);",
            "    }",
            "  };",
            "  Parser.prototype._growLrSeed = function(ctx, pos, key, seed) {",
            "    var curr = seed;",
            "    while (curr.success) {",
            "      ctx.memo.set(key, curr);",
            "      this._clearLrDependentMemo(ctx, pos, key);",
            "      var newRes = this.parseAt(ctx, pos);",
            "      if (!newRes.success || newRes.nextPos <= curr.nextPos) {",
            "        break;",
            "      }",
            "      curr = newRes;",
            "    }",
            "    ctx.memo.set(key, curr);",
            "    return curr;",
            "  };",
            "  Parser.prototype._evalCached = function(ctx, pos) {",
            "    if (!this.memoize) return this.parseAt(ctx, pos);",
            "    var key = (this.ruleId << 20) | pos;",
            "    var cached = ctx.memo.get(key);",
            "    if (cached !== undefined) return cached;",
            "",
            "    if (ctx.inProgress.has(key)) {",
            "      ctx.lrDetected.add(key);",
            "      return new ParseResult(false, null, pos, 'Left recursion detected at ' + this.name);",
            "    }",
            "",
            "    if (ctx.currDepth >= ctx.maxDepth) {",
            "      var lc = ctx.calcLineCol(pos);",
            "      throw new PEGSyntaxError('Maximum parsing recursion depth exceeded', pos, lc.line, lc.col);",
            "    }",
            "",
            "    ctx.currDepth++;",
            "    ctx.inProgress.add(key);",
            "    var rawRes;",
            "    try {",
            "      rawRes = this.parseAt(ctx, pos);",
            "    } finally {",
            "      ctx.currDepth--;",
            "      ctx.inProgress.delete(key);",
            "    }",
            "",
            "    if (ctx.lrDetected.has(key)) {",
            "      ctx.lrDetected.delete(key);",
            "      if (rawRes.success) {",
            "        rawRes = this._growLrSeed(ctx, pos, key, rawRes);",
            "      }",
            "    }",
            "    ctx.memo.set(key, rawRes);",
            "    return rawRes;",
            "  };",
            "  Parser.prototype.parse = function(text) {",
            "    var ctx = new ParseContext(text);",
            "    var res = this._evalCached(ctx, 0);",
            "    if (!res.success) {",
            "      var lc = ctx.calcLineCol(ctx.maxPos);",
            "      var snippet = ctx.getSnippet(ctx.maxPos, 20);",
            "      throw new PEGSyntaxError(",
            "        res.errorMsg || 'Syntax error', ctx.maxPos, lc.line, lc.col, ctx.expectedTokens.slice(), snippet",
            "      );",
            "    }",
            "    if (res.nextPos < ctx.length) {",
            "      var lc2 = ctx.calcLineCol(res.nextPos);",
            "      var snippet2 = ctx.getSnippet(res.nextPos, 20);",
            "      throw new PEGSyntaxError(",
            "        'Unconsumed trailing input', res.nextPos, lc2.line, lc2.col, ['EOF'], snippet2",
            "      );",
            "    }",
            "    return res.value;",
            "  };",
            "  Parser.prototype.parseWithDiagnostics = function(text) {",
            "    var ctx = new ParseContext(text);",
            "    var res = this._evalCached(ctx, 0);",
            "    if (res.success && res.nextPos === ctx.length) {",
            "      return { success: true, value: res.value, diagnostics: null };",
            "    }",
            "    var errPos = !res.success ? ctx.maxPos : res.nextPos;",
            "    var errMsg = !res.success ? (res.errorMsg || 'Syntax error') : 'Unconsumed trailing input';",
            "    var lc = ctx.calcLineCol(errPos);",
            "    var snippet = ctx.getSnippet(errPos, 20);",
            "    var expected = !res.success ? ctx.expectedTokens.slice() : ['EOF'];",
            "    return {",
            "      success: false,",
            "      value: null,",
            "      diagnostics: {",
            "        errorMsg: errMsg,",
            "        offset: errPos,",
            "        line: lc.line,",
            "        col: lc.col,",
            "        expectedTokens: expected,",
            "        snippet: snippet",
            "      }",
            "    };",
            "  };",
            "  Parser.prototype.map = function(fn) { return new MappedParser(this, fn); };",
            "",
            "  /**",
            "   * @constructor",
            "   * @extends {Parser}",
            "   * @param {string} expected",
            "   */",
            "  function Literal(expected) {",
            "    Parser.call(this, jsonExpected(expected), false);",
            "    this.expected = expected;",
            "    this.len = expected.length;",
            "  }",
            "  Literal.prototype = Object.create(Parser.prototype);",
            "  Literal.prototype.parseAt = function(ctx, pos) {",
            "    if (ctx.text.startsWith(this.expected, pos)) {",
            "      return new ParseResult(true, this.expected, pos + this.len);",
            "    }",
            "    ctx.updateMaxPos(pos, this.expected);",
            "    return new ParseResult(false, null, pos, 'Expected ' + JSON.stringify(this.expected));",
            "  };",
            "  function jsonExpected(s) { return JSON.stringify(s); }",
            "",
            "  /**",
            "   * @constructor",
            "   * @extends {Parser}",
            "   * @param {!RegExp} pattern",
            "   */",
            "  function Regex(pattern) {",
            "    var flags = 'y';",
            "    if (pattern.ignoreCase) flags += 'i';",
            "    if (pattern.multiline) flags += 'm';",
            "    if (pattern.dotAll) flags += 's';",
            "    Parser.call(this, '/' + pattern.source + '/' + flags, false);",
            "    this.pattern = new RegExp(pattern.source, flags);",
            "    this.source = pattern.source;",
            "  }",
            "  Regex.prototype = Object.create(Parser.prototype);",
            "  Regex.prototype.parseAt = function(ctx, pos) {",
            "    this.pattern.lastIndex = pos;",
            "    var m = this.pattern.exec(ctx.text);",
            "    if (m !== null) {",
            "      return new ParseResult(true, m[0], pos + m[0].length);",
            "    }",
            "    ctx.updateMaxPos(pos, '/' + this.source + '/');",
            "    return new ParseResult(false, null, pos, 'Expected pattern /' + this.source + '/');",
            "  };",
            "",
            "  /**",
            "   * @constructor",
            "   * @extends {Parser}",
            "   * @param {Array} parsers",
            "   */",
            "  function Sequence(parsers) {",
            "    Parser.call(this, 'Seq', true);",
            "    this.parsers = parsers;",
            "  }",
            "  Sequence.prototype = Object.create(Parser.prototype);",
            "  Sequence.prototype.parseAt = function(ctx, pos) {",
            "    var currPos = pos;",
            "    var values = [];",
            "    var isCommitted = false;",
            "    for (var i = 0; i < this.parsers.length; i++) {",
            "      var p = this.parsers[i];",
            "      var res = p._evalCached(ctx, currPos);",
            "      if (res.committed) isCommitted = true;",
            "      if (!res.success) return new ParseResult(false, null, pos, res.errorMsg, isCommitted);",
            "      if (!(p instanceof Cut)) values.push(res.value);",
            "      currPos = res.nextPos;",
            "    }",
            "    return new ParseResult(true, values, currPos, null, isCommitted);",
            "  };",
            "",
            "  /**",
            "   * @constructor",
            "   * @extends {Parser}",
            "   * @param {Array} alts",
            "   */",
            "  function Choice(alts) {",
            "    Parser.call(this, 'Choice', true);",
            "    this.alts = alts;",
            "  }",
            "  Choice.prototype = Object.create(Parser.prototype);",
            "  Choice.prototype.parseAt = function(ctx, pos) {",
            "    var lastErr = null;",
            "    for (var i = 0; i < this.alts.length; i++) {",
            "      var res = this.alts[i]._evalCached(ctx, pos);",
            "      if (res.success) return res;",
            "      if (res.committed) return res;",
            "      lastErr = res.errorMsg;",
            "    }",
            "    return new ParseResult(false, null, pos, lastErr || 'No choice alternative matched');",
            "  };",
            "",
            "  /**",
            "   * @constructor",
            "   * @extends {Parser}",
            "   * @param {*} parser",
            "   * @param {number=} minCount",
            "   * @param {?number=} maxCount",
            "   */",
            "  function Repetition(parser, minCount, maxCount) {",
            "    Parser.call(this, 'Repeat', true);",
            "    this.parser = parser;",
            "    this.minCount = minCount || 0;",
            "    this.maxCount = maxCount || null;",
            "  }",
            "  Repetition.prototype = Object.create(Parser.prototype);",
            "  Repetition.prototype.parseAt = function(ctx, pos) {",
            "    var currPos = pos;",
            "    var values = [];",
            "    while (this.maxCount === null || values.length < this.maxCount) {",
            "      var res = this.parser._evalCached(ctx, currPos);",
            "      if (!res.success) break;",
            "      if (res.nextPos === currPos) break;",
            "      values.push(res.value);",
            "      currPos = res.nextPos;",
            "    }",
            "    if (values.length < this.minCount) {",
            "      return new ParseResult(false, null, pos, 'Expected at least ' + this.minCount + ' repetition(s)');",
            "    }",
            "    return new ParseResult(true, values, currPos);",
            "  };",
            "",
            "  /**",
            "   * @constructor",
            "   * @extends {Parser}",
            "   * @param {*} parser",
            "   */",
            "  function Optional(parser) {",
            "    Parser.call(this, 'Opt', false);",
            "    this.parser = parser;",
            "  }",
            "  Optional.prototype = Object.create(Parser.prototype);",
            "  Optional.prototype.parseAt = function(ctx, pos) {",
            "    var res = this.parser._evalCached(ctx, pos);",
            "    if (res.success) return res;",
            "    return new ParseResult(true, null, pos);",
            "  };",
            "",
            "  /**",
            "   * @constructor",
            "   * @extends {Parser}",
            "   * @param {*} parser",
            "   * @param {boolean=} isPositive",
            "   */",
            "  function Predicate(parser, isPositive) {",
            "    Parser.call(this, isPositive ? 'AndPred' : 'NotPred', false);",
            "    this.parser = parser;",
            "    this.isPositive = isPositive !== false;",
            "  }",
            "  Predicate.prototype = Object.create(Parser.prototype);",
            "  Predicate.prototype.parseAt = function(ctx, pos) {",
            "    var res = this.parser._evalCached(ctx, pos);",
            "    if (this.isPositive) {",
            "      return res.success ? new ParseResult(true, null, pos) :",
            "                           new ParseResult(false, null, pos, 'Predicate failed');",
            "    } else {",
            "      return res.success ? new ParseResult(false, null, pos, 'Negative predicate matched') :",
            "                           new ParseResult(true, null, pos);",
            "    }",
            "  };",
            "",
            "  /**",
            "   * @constructor",
            "   * @extends {Parser}",
            "   */",
            "  function Cut() { Parser.call(this, '^', false); }",
            "  Cut.prototype = Object.create(Parser.prototype);",
            "  Cut.prototype.parseAt = function(ctx, pos) {",
            "    return new ParseResult(true, null, pos, null, true);",
            "  };",
            "",
            "  /**",
            "   * @constructor",
            "   * @extends {Parser}",
            "   */",
            "  function AnyChar() { Parser.call(this, 'anyChar', false); }",
            "  AnyChar.prototype = Object.create(Parser.prototype);",
            "  AnyChar.prototype.parseAt = function(ctx, pos) {",
            "    if (pos < ctx.length) {",
            "      return new ParseResult(true, ctx.text[pos], pos + 1);",
            "    }",
            "    ctx.updateMaxPos(pos, 'any character');",
            "    return new ParseResult(false, null, pos, 'Unexpected EOF');",
            "  };",
            "",
            "  /**",
            "   * @constructor",
            "   * @extends {Parser}",
            "   * @param {Array} ranges",
            "   * @param {Array} singles",
            "   * @param {boolean=} inverted",
            "   * @param {string=} name",
            "   */",
            "  function CharClass(ranges, singles, inverted, name) {",
            "    Parser.call(this, name || 'CharClass', false);",
            "    this.ranges = ranges;",
            "    this.singles = singles;",
            "    this.inverted = inverted;",
            "    this.singlesSet = singles.length > 8 ? new Set(singles) : null;",
            "  }",
            "  CharClass.prototype = Object.create(Parser.prototype);",
            "  CharClass.prototype.parseAt = function(ctx, pos) {",
            "    if (pos >= ctx.length) {",
            "      ctx.updateMaxPos(pos, this.name);",
            "      return new ParseResult(false, null, pos, 'Unexpected EOF');",
            "    }",
            "    var code = ctx.text.charCodeAt(pos);",
            "    var matched = false;",
            "    for (var i = 0; i < this.ranges.length; i++) {",
            "      if (code >= this.ranges[i][0] && code <= this.ranges[i][1]) {",
            "        matched = true;",
            "        break;",
            "      }",
            "    }",
            "    if (!matched) {",
            "      if (this.singlesSet !== null) {",
            "        matched = this.singlesSet.has(code);",
            "      } else {",
            "        for (var j = 0; j < this.singles.length; j++) {",
            "          if (code === this.singles[j]) {",
            "            matched = true;",
            "            break;",
            "          }",
            "        }",
            "      }",
            "    }",
            "    if (this.inverted ? !matched : matched) {",
            "      return new ParseResult(true, ctx.text[pos], pos + 1);",
            "    }",
            "    ctx.updateMaxPos(pos, this.name);",
            "    return new ParseResult(false, null, pos, 'Expected character matching ' + this.name);",
            "  };",
            "",
            "  /**",
            "   * @constructor",
            "   * @extends {Parser}",
            "   * @param {string} name",
            "   */",
            "  function RuleRef(name) {",
            "    Parser.call(this, name, true);",
            "    this.name = name;",
            "    this._inner = null;",
            "  }",
            "  RuleRef.prototype = Object.create(Parser.prototype);",
            "  RuleRef.prototype.define = function(p) { this._inner = p; };",
            "  RuleRef.prototype.parseAt = function(ctx, pos) {",
            "    if (!this._inner) throw new Error('Rule ' + this.name + ' undefined');",
            "    return this._inner._evalCached(ctx, pos);",
            "  };",
            "",
            "  /**",
            "   * @constructor",
            "   * @extends {Parser}",
            "   * @param {*} parser",
            "   * @param {function(*): *} fn",
            "   */",
            "  function MappedParser(parser, fn) {",
            "    Parser.call(this, parser.name + '.map', parser.memoize);",
            "    this.parser = parser;",
            "    this.fn = fn;",
            "  }",
            "  MappedParser.prototype = Object.create(Parser.prototype);",
            "  MappedParser.prototype.parseAt = function(ctx, pos) {",
            "    var res = this.parser._evalCached(ctx, pos);",
            "    if (!res.success) return res;",
            "    try {",
            "      var mapped = this.fn(res.value);",
            "      return new ParseResult(true, mapped, res.nextPos, null, res.committed);",
            "    } catch (e) {",
            "      return new ParseResult(false, null, pos, e.message, true);",
            "    }",
            "  };",
            "",
            "  // Combinator factories",
            "  function lit(s) { return new Literal(s); }",
            "  function reg(p) { return new Regex(p); }",
            "  function seq(parsers) { return new Sequence(parsers); }",
            "  function choice(alts) { return new Choice(alts); }",
            "  function star(p) { return new Repetition(p, 0); }",
            "  function plus(p) { return new Repetition(p, 1); }",
            "  function opt(p) { return new Optional(p); }",
            "  function andPred(p) { return new Predicate(p, true); }",
            "  function notPred(p) { return new Predicate(p, false); }",
            "  function cut() { return new Cut(); }",
            "  function anyChar() { return new AnyChar(); }",
            "  function charClass(ranges, singles, inverted, name) {",
            "    return new CharClass(ranges, singles, inverted, name);",
            "  }",
            "",
        ]

    def _build_class_definition(self) -> List[str]:
        class_name = f"{self.grammar.name}Parser"
        lines: List[str] = [
            f"  // --- Section 2: {class_name} Class Definition ---",
            f"  function {class_name}() {{",
            "    this._initRules();",
            "  }",
            "",
            f"  {class_name}.prototype._initRules = function() {{",
        ]
        lines.extend(self._emit_rule_declarations())
        lines.extend(self._emit_rule_definitions())
        lines.extend(self._emit_root_parser_setup())
        lines.extend(self._emit_facade_methods(class_name))
        for method in self.action_methods:
            lines.append("")
            lines.append(method)
        return lines

    def _emit_rule_declarations(self) -> List[str]:
        lines: List[str] = []
        for rule in self.grammar.rules:
            lines.append(f'    this._r_{rule.name} = new RuleRef("{rule.name}");')
        lines.append("")
        return lines

    def _emit_rule_definitions(self) -> List[str]:
        lines: List[str] = []
        for rule in self.grammar.rules:
            expr_code = self._emit_expr(rule.expr, rule.name)
            if self.ast_only:
                qname = json.dumps(rule.name)
                wrapped = f"({expr_code}).map(function(val) {{ return {{ type: {qname}, value: val }}; }})"
                lines.append(f"    this._r_{rule.name}.define({wrapped});")
            else:
                lines.append(f"    this._r_{rule.name}.define({expr_code});")
        return lines

    def _emit_root_parser_setup(self) -> List[str]:
        start_r = self.grammar.start_rule or (
            self.grammar.rules[0].name if self.grammar.rules else "root"
        )
        return [
            "",
            f"    this.rootParser = this._r_{start_r};",
            "  };",
            "",
        ]

    def _emit_facade_methods(self, class_name: str) -> List[str]:
        return [
            f"  {class_name}.prototype.parse = function(text) {{",
            "    return this.rootParser.parse(text);",
            "  };",
            "",
            f"  {class_name}.prototype.parseWithDiagnostics = function(text) {{",
            "    return this.rootParser.parseWithDiagnostics(text);",
            "  };",
            "",
            f"  {class_name}.prototype.parseAt = function(ctx, pos) {{",
            "    return this.rootParser.parseAt(ctx, pos);",
            "  };",
        ]

    def _build_module_exports(self) -> List[str]:
        class_name = f"{self.grammar.name}Parser"
        return [
            "",
            "  // --- Section 3: Universal Module Exports ---",
            "  if (typeof module !== 'undefined' && module.exports) {",
            f"    module.exports = {{ {class_name}: {class_name}, PEGSyntaxError: PEGSyntaxError }};",
            "  }",
            "  if (typeof window !== 'undefined') {",
            f"    window['{class_name}'] = {class_name};",
            "    window.Application = window.Application || {};",
            "    window.Application.frameworks = window.Application.frameworks || {};",
            f"    window.Application.frameworks['{class_name}'] = {class_name};",
            "  }",
        ]

    def _emit_expr(self, expr: Expression, rule_name: str) -> str:
        """Emits combinator instantiation string via dispatch table."""
        emitter = self._EXPR_EMITTERS.get(type(expr))
        if emitter is not None:
            return emitter(self, expr, rule_name)
        return 'lit("")'

    def _emit_regex(self, expr: RegexExpr) -> str:
        escaped_pattern, flags = _extract_regex_flags(expr.pattern)
        return f"reg(/{escaped_pattern}/{flags})"

    def _emit_char_class(self, expr: CharClassExpr) -> str:
        ranges, singles = _parse_char_class_spec(expr.raw_spec)
        prefix = "^" if expr.inverted else ""
        name = f"[{prefix}{expr.raw_spec}]"
        return (
            f"charClass({json.dumps(ranges)}, {json.dumps(singles)}, "
            f"{json.dumps(expr.inverted)}, {json.dumps(name)})"
        )

    def _emit_repeat(self, expr: RepeatExpr, rule_name: str) -> str:
        inner = self._emit_expr(expr.expr, rule_name)
        return _format_repetition(inner, expr.min_count, expr.max_count)

    def _emit_pred(self, expr: PredExpr, rule_name: str) -> str:
        inner = self._emit_expr(expr.expr, rule_name)
        return f"andPred({inner})" if expr.is_positive else f"notPred({inner})"

    def _emit_seq(self, expr: SeqExpr, rule_name: str) -> str:
        elems = [self._emit_expr(e, rule_name) for e in expr.elements]
        return f"seq([{', '.join(elems)}])"

    def _emit_choice(self, expr: ChoiceExpr, rule_name: str) -> str:
        alts = [self._emit_expr(a, rule_name) for a in expr.alternatives]
        return f"choice([{', '.join(alts)}])"

    def _emit_action(self, expr: ActionExpr, rule_name: str) -> str:
        if self.ast_only:
            return self._emit_expr(expr.expr, rule_name)
        inner = self._emit_expr(expr.expr, rule_name)
        class_name = f"{self.grammar.name}Parser"
        method_name = f"_action_{rule_name}_{self.action_counter}"
        self.action_counter += 1

        named_bindings = self._collect_named_bindings(expr.expr)
        action_code = self._build_action_method(
            class_name, method_name, expr.action_code, named_bindings
        )
        self.action_methods.append(action_code)
        return f"{inner}.map(this.{method_name}.bind(this))"

    def _collect_named_bindings(
        self, expr: Expression
    ) -> Tuple[bool, List[Tuple[str, int]]]:
        """Finds named expressions in a sequence or single expression. Returns (is_seq, bindings)."""
        if isinstance(expr, NamedExpr):
            return (False, [(expr.name, 0)])
        if isinstance(expr, SeqExpr):
            bindings: List[Tuple[str, int]] = []
            for i, child in enumerate(expr.elements):
                if isinstance(child, NamedExpr):
                    bindings.append((child.name, i))
            return (True, bindings)
        return (False, [])

    def _build_action_method(
        self,
        class_name: str,
        method_name: str,
        code: str,
        named_info: Tuple[bool, List[Tuple[str, int]]],
    ) -> str:
        """Constructs an action method attached to the parser prototype."""
        lines: List[str] = [
            f"  {class_name}.prototype.{method_name} = function(val) {{"
        ]
        lines.extend(self._emit_action_bindings(named_info))
        lines.extend(self._emit_action_body(code))
        lines.append("  };")
        return "\n".join(lines)

    def _emit_action_bindings(
        self, named_info: Tuple[bool, List[Tuple[str, int]]]
    ) -> List[str]:
        is_seq, bindings = named_info
        lines: List[str] = []
        if not bindings:
            return lines
        if not is_seq:
            name, _ = bindings[0]
            lines.append(f"    var {name} = val;")
        else:
            for name, idx in bindings:
                lines.append(
                    f"    var {name} = Array.isArray(val) ? val[{idx}] : undefined;"
                )
        return lines

    def _emit_action_body(self, code: str) -> List[str]:
        lines: List[str] = []
        for line in code.strip().split("\n"):
            stripped = line.strip()
            if stripped.startswith("return ") and not stripped.endswith(";"):
                stripped += ";"
            lines.append(f"    {stripped}")
        return lines
