/**
 * @fileoverview QueryValidator — PEG Runtime Engine + AOT Lucene query grammar.
 *
 * A complete JavaScript port of src/core/structures/peg.py (DSN-25).
 *
 * Architecture:
 *  1. PEG Runtime — Packrat memoization (O(N)), Warth-style LR handling,
 *     max-position error tracking, Levenshtein typo diagnosis.
 *  2. Lucene Grammar (AOT) — combinators are built once at module load:
 *       Query      ← WS? Expression WS? EOF
 *       Expression ← OrTerm  (WS 'OR'  WS OrTerm)*
 *       OrTerm     ← AndTerm (WS 'AND' WS AndTerm | AndTerm)*
 *       AndTerm    ← ('NOT' WS)? Primary
 *       Primary    ← Group / FieldQuery / Phrase / Word
 *       Group      ← '(' WS? Expression WS? ')'
 *       FieldQuery ← [a-zA-Z_]+ ':' (Phrase / Word)
 *       Phrase     ← '"' [^"]* '"'
 *       Word       ← [^\s():"]+
 *  3. QueryValidator — public facade: validate() / parse().
 *
 * Security notes:
 *  - No eval(), no innerHTML, no external I/O.
 *  - Input is capped at MAX_INPUT_LENGTH (8192) to prevent DoS.
 *  - Memoization key is (ruleId << 20) | pos (matches Python implementation).
 *  - Max recursion depth: MAX_DEPTH (200) prevents stack exhaustion.
 *
 * @package
 */

(function(global) {
  'use strict';

  // ===========================================================================
  // Constants
  // ===========================================================================

  /** @const {number} */
  var MAX_INPUT_LENGTH = 8192;

  /** @const {number} Maximum recursion depth guard. */
  var MAX_DEPTH = 200;

  /** @const {number} Bit-shift for memoization key packing (ruleId << MEMO_SHIFT | pos). */
  var MEMO_SHIFT = 20;

  // ===========================================================================
  // Section 1 — Diagnostic helpers (ported from peg.py top-level functions)
  // ===========================================================================

  /**
   * @param {string} text
   * @param {number} pos
   * @return {{line: number, col: number, snippet: string}}
   */
  function calcLineCol(text, pos) {
    var bounded = Math.max(0, Math.min(pos, text.length));
    var prefix = text.slice(0, bounded);
    var lines = prefix.split('\n');
    var lineNum = lines.length;
    var colNum = lines[lines.length - 1].length + 1;
    var allLines = text.split('\n');
    var snippet = allLines[lineNum - 1] || '';
    return {line: lineNum, col: colNum, snippet: snippet};
  }

  /**
   * @param {string} text
   * @return {?string}
   */
  function checkUnclosedQuotes(text) {
    var active = '';
    var esc = false;
    var start = 0;
    for (var i = 0; i < text.length; i++) {
      var ch = text[i];
      if (esc) { esc = false; continue; }
      if (ch === '\\') { esc = true; continue; }
      if (ch === '"' || ch === "'") {
        if (active === ch) {
          active = '';
        } else if (active === '') {
          active = ch;
          start = i;
        }
      }
    }
    if (active) {
      var lc = calcLineCol(text, start);
      return 'Possible unclosed string literal (' + active + ') starting at line ' + lc.line + ', col ' + lc.col;
    }
    return null;
  }

  /**
   * @param {string} text
   * @return {?string}
   */
  function checkUnmatchedBrackets(text) {
    var stack = []; // [{ch, pos}]
    var pairs = {')': '(', ']': '[', '}': '{'};
    for (var i = 0; i < text.length; i++) {
      var ch = text[i];
      if (ch === '(' || ch === '[' || ch === '{') {
        stack.push({ch: ch, pos: i});
      } else if (ch === ')' || ch === ']' || ch === '}') {
        if (stack.length === 0) {
          var lc = calcLineCol(text, i);
          return "Unmatched closing bracket '" + ch + "' at line " + lc.line + ', col ' + lc.col;
        }
        var top = stack.pop();
        if (top.ch !== pairs[ch]) {
          var lc2 = calcLineCol(text, i);
          return "Mismatched bracket: expected closing for '" + top.ch + "', found '" + ch + "' at line " + lc2.line + ', col ' + lc2.col;
        }
      }
    }
    if (stack.length > 0) {
      var last = stack[stack.length - 1];
      var lc3 = calcLineCol(text, last.pos);
      return "Unclosed bracket '" + last.ch + "' opened at line " + lc3.line + ', col ' + lc3.col;
    }
    return null;
  }

  /**
   * Levenshtein distance (case-insensitive).
   * @param {string} s1
   * @param {string} s2
   * @return {number}
   */
  function levenshtein(s1, s2) {
    s1 = s1.toLowerCase();
    s2 = s2.toLowerCase();
    if (s1.length < s2.length) return levenshtein(s2, s1);
    if (!s2.length) return s1.length;
    var prev = [];
    for (var k = 0; k <= s2.length; k++) prev.push(k);
    for (var i = 0; i < s1.length; i++) {
      var curr = [i + 1];
      for (var j = 0; j < s2.length; j++) {
        var cost = s1[i] === s2[j] ? 0 : 1;
        curr.push(Math.min(curr[j] + 1, prev[j + 1] + 1, prev[j] + cost));
      }
      prev = curr;
    }
    return prev[s2.length];
  }

  /**
   * @param {string} text
   * @param {number} pos
   * @param {!Array<string>} expectedTokens
   * @return {?string}
   */
  function diagnoseTypo(text, pos, expectedTokens) {
    var end = pos;
    while (end < text.length && /\w/.test(text[end])) end++;
    var actual = text.slice(pos, end);
    if (!actual || actual.length < 2) return null;
    for (var i = 0; i < expectedTokens.length; i++) {
      var candidate = expectedTokens[i];
      if (!candidate || candidate.length < 2) continue;
      if (Math.abs(actual.length - candidate.length) > 1) continue;
      if (levenshtein(actual, candidate) <= 2 && levenshtein(actual, candidate) > 0) {
        return "Did you mean '" + candidate.toUpperCase() + "' instead of '" + actual + "'?";
      }
    }
    return null;
  }

  /**
   * @param {string} text
   * @param {number} pos
   * @param {!Array<string>} expectedTokens
   * @return {?string}
   */
  function diagnoseSyntaxAnomaly(text, pos, expectedTokens) {
    var q = checkUnclosedQuotes(text);
    if (q) return q;
    var b = checkUnmatchedBrackets(text);
    if (b) return b;
    return diagnoseTypo(text, pos, expectedTokens);
  }

  // ===========================================================================
  // Section 2 — PEGSyntaxError
  // ===========================================================================

  /**
   * @constructor
   * @param {string} message
   * @param {number} pos
   * @param {number} line
   * @param {number} col
   * @param {!Array<string>} expectedTokens
   * @param {string} snippet
   * @param {?string=} hint
   */
  function PEGSyntaxError(message, pos, line, col, expectedTokens, snippet, hint) {
    this.message = message;
    this.pos = pos;
    this.line = line;
    this.col = col;
    this.expected = expectedTokens;
    this.snippet = snippet;
    this.hint = hint || null;

    var tokensStr = expectedTokens.length ? expectedTokens.map(function(t) { return "'" + t + "'"; }).join(', ') : 'none';
    var caretIndent = new Array(Math.max(0, col)).join(' ');
    var hintStr = hint ? '\n  Diagnosis: ' + hint : '';
    this.formattedMessage =
      'Syntax error at line ' + line + ', col ' + col + ': ' + message + '\n' +
      '  ' + snippet + '\n' +
      '  ' + caretIndent + '^ expected: ' + tokensStr + hintStr;

    if (Error.captureStackTrace) {
      Error.captureStackTrace(this, PEGSyntaxError);
    }
  }
  PEGSyntaxError.prototype = Object.create(Error.prototype);
  PEGSyntaxError.prototype.name = 'PEGSyntaxError';
  PEGSyntaxError.prototype.toString = function() { return this.formattedMessage; };

  // ===========================================================================
  // Section 3 — ParseResult (immutable value struct)
  // ===========================================================================

  /**
   * @constructor
   * @param {boolean} success
   * @param {*} value
   * @param {number} nextPos
   * @param {?string=} errorMsg
   * @param {boolean=} committed
   */
  function ParseResult(success, value, nextPos, errorMsg, committed) {
    this.success = success;
    this.value = value;
    this.nextPos = nextPos;
    this.errorMsg = errorMsg || null;
    this.committed = committed || false;
  }

  // ===========================================================================
  // Section 4 — ParseContext (memoization + error tracking)
  // ===========================================================================

  /**
   * @constructor
   * @param {string} text
   * @param {number=} maxDepth
   */
  function ParseContext(text, maxDepth) {
    if (text.length > MAX_INPUT_LENGTH) {
      throw new RangeError('[PEG] Input length (' + text.length + ') exceeds MAX_INPUT_LENGTH (' + MAX_INPUT_LENGTH + ').');
    }
    this.text = text;
    this.length = text.length;
    this.maxDepth = maxDepth || MAX_DEPTH;
    this.depth = 0;
    this.maxPos = 0;
    /** @type {!Array<string>} */
    this.expectedTokens = [];
    /** @type {!Map<number, !ParseResult>} */
    this.memo = new Map();
    /** @type {!Set<number>} */
    this.inProgress = new Set();
    /** @type {!Set<number>} */
    this.lrDetected = new Set();
  }

  /**
   * @param {number} pos
   * @param {string} token
   */
  ParseContext.prototype.updateMaxPos = function(pos, token) {
    if (!token || !token.trim()) return;
    if (pos > this.maxPos) {
      this.maxPos = pos;
      this.expectedTokens = [token];
    } else if (pos === this.maxPos) {
      if (this.expectedTokens.indexOf(token) === -1) {
        this.expectedTokens.push(token);
      }
    }
  };

  /**
   * @param {number} pos
   * @return {{line: number, col: number, snippet: string}}
   */
  ParseContext.prototype.calcLineCol = function(pos) {
    return calcLineCol(this.text, pos);
  };

  // ===========================================================================
  // Section 5 — Rule ID counter (global, matches Python _id_counter)
  // ===========================================================================

  var _ruleIdCounter = 0;

  /** @return {number} */
  function nextRuleId() {
    _ruleIdCounter++;
    return _ruleIdCounter;
  }

  // ===========================================================================
  // Section 6 — Parser base (prototype mixin for all combinator types)
  // ===========================================================================

  /**
   * Base parser. All combinators prototype-chain from this.
   * @constructor
   * @param {string=} name
   * @param {boolean=} memoize
   */
  function Parser(name, memoize) {
    this.ruleId = nextRuleId();
    this.name = name || '';
    this.memoize = memoize !== false;  // default: true
  }

  /**
   * Abstract — subclasses override this.
   * @param {!ParseContext} ctx
   * @param {number} pos
   * @return {!ParseResult}
   */
  Parser.prototype.parseAt = function(ctx, pos) {
    throw new Error('[PEG] parseAt not implemented on ' + this.name);
  };

  /**
   * Packrat memoization wrapper with Warth-style left-recursion support.
   * @param {!ParseContext} ctx
   * @param {number} pos
   * @return {!ParseResult}
   */
  Parser.prototype._evalCached = function(ctx, pos) {
    if (!this.memoize) return this.parseAt(ctx, pos);

    var key = (this.ruleId << MEMO_SHIFT) | pos;

    if (ctx.memo.has(key)) return ctx.memo.get(key);

    if (ctx.inProgress.has(key)) {
      ctx.lrDetected.add(key);
      return new ParseResult(false, null, pos, "Left recursion detected at rule '" + this.name + "'");
    }

    if (ctx.depth > ctx.maxDepth) {
      var lc = ctx.calcLineCol(pos);
      throw new PEGSyntaxError('Maximum parsing recursion depth exceeded', pos, lc.line, lc.col, [], lc.snippet);
    }

    ctx.depth++;
    ctx.inProgress.add(key);
    var res;
    try {
      res = this.parseAt(ctx, pos);
    } finally {
      ctx.depth--;
      ctx.inProgress.delete(key);
    }

    // LR seed-growing (Warth algorithm)
    if (ctx.lrDetected.has(key)) {
      ctx.lrDetected.delete(key);
      if (res.success) {
        res = this._growLRSeed(ctx, pos, key, res);
      }
    }

    ctx.memo.set(key, res);
    return res;
  };

  /**
   * @param {!ParseContext} ctx
   * @param {number} pos
   * @param {number} key
   * @param {!ParseResult} seed
   * @return {!ParseResult}
   */
  Parser.prototype._growLRSeed = function(ctx, pos, key, seed) {
    var curr = seed;
    while (curr.success) {
      ctx.memo.set(key, curr);
      // Clear dependent memo entries
      ctx.memo.forEach(function(v, k) {
        if ((k & ((1 << MEMO_SHIFT) - 1)) >= pos && k !== key) {
          ctx.memo.delete(k);
        }
      });
      var newRes = this.parseAt(ctx, pos);
      if (!newRes.success || newRes.nextPos <= curr.nextPos) break;
      curr = newRes;
    }
    ctx.memo.set(key, curr);
    return curr;
  };

  /**
   * Parses the full input string. Raises PEGSyntaxError on failure.
   * @param {string} text
   * @return {*} AST value
   */
  Parser.prototype.parse = function(text) {
    var ctx = new ParseContext(text);
    var res = this._evalCached(ctx, 0);
    var anomaly = diagnoseSyntaxAnomaly(text, ctx.maxPos, ctx.expectedTokens);

    if (!res.success) {
      var lc = ctx.calcLineCol(ctx.maxPos);
      throw new PEGSyntaxError(
        res.errorMsg || 'Unexpected token',
        ctx.maxPos, lc.line, lc.col, ctx.expectedTokens, lc.snippet, anomaly
      );
    }
    if (res.nextPos < ctx.length) {
      ctx.updateMaxPos(res.nextPos, 'EOF');
      var lc2 = ctx.calcLineCol(res.nextPos);
      throw new PEGSyntaxError(
        'Unconsumed trailing characters',
        res.nextPos, lc2.line, lc2.col, ctx.expectedTokens, lc2.snippet, anomaly
      );
    }
    return res.value;
  };

  /**
   * Convenience: attach a map transform.
   * @param {function(*): *} fn
   * @return {!MappedParser}
   */
  Parser.prototype.map = function(fn) {
    return new MappedParser(this, fn);
  };

  // ===========================================================================
  // Section 7 — Concrete combinator classes
  // ===========================================================================

  // --- Literal ----------------------------------------------------------------

  /**
   * Matches an exact literal string.
   * @constructor
   * @extends {Parser}
   * @param {string} expected
   * @param {string=} name
   */
  function Literal(expected, name) {
    Parser.call(this, name || ("'" + expected + "'"), false);
    this.expected = expected;
    this.expectedLen = expected.length;
  }
  Literal.prototype = Object.create(Parser.prototype);
  Literal.prototype.parseAt = function(ctx, pos) {
    if (ctx.text.substr(pos, this.expectedLen) === this.expected) {
      return new ParseResult(true, this.expected, pos + this.expectedLen);
    }
    ctx.updateMaxPos(pos, this.expected);
    return new ParseResult(false, null, pos, "Expected '" + this.expected + "'");
  };

  // --- Regex ------------------------------------------------------------------

  /**
   * Matches a regex pattern at the current position.
   * @constructor
   * @extends {Parser}
   * @param {!RegExp} pattern
   * @param {string=} name
   */
  function Regex(pattern, name) {
    Parser.call(this, name || ('/' + pattern.source + '/'), false);
    // Ensure the regex starts matching at pos (sticky or anchored)
    this.pattern = new RegExp(pattern.source, 'y');
    this.patternStr = pattern.source;
  }
  Regex.prototype = Object.create(Parser.prototype);
  Regex.prototype.parseAt = function(ctx, pos) {
    this.pattern.lastIndex = pos;
    var m = this.pattern.exec(ctx.text);
    if (m !== null) {
      return new ParseResult(true, m[0], pos + m[0].length);
    }
    ctx.updateMaxPos(pos, this.patternStr);
    return new ParseResult(false, null, pos, 'Expected pattern /' + this.patternStr + '/');
  };

  // --- Sequence ---------------------------------------------------------------

  /**
   * Matches a sequence of parsers e1 e2 ... eN.
   * @constructor
   * @extends {Parser}
   * @param {!Array<!Parser>} parsers
   * @param {string=} name
   */
  function Sequence(parsers, name) {
    Parser.call(this, name || 'Seq', true);
    this.parsers = parsers;
  }
  Sequence.prototype = Object.create(Parser.prototype);
  Sequence.prototype.parseAt = function(ctx, pos) {
    var currPos = pos;
    var values = [];
    var isCommitted = false;
    for (var i = 0; i < this.parsers.length; i++) {
      var p = this.parsers[i];
      var res = p._evalCached(ctx, currPos);
      if (res.committed) isCommitted = true;
      if (!res.success) {
        return new ParseResult(false, null, pos, res.errorMsg, isCommitted);
      }
      if (!(p instanceof Cut)) values.push(res.value);
      currPos = res.nextPos;
    }
    return new ParseResult(true, values, currPos, null, isCommitted);
  };

  // --- Choice -----------------------------------------------------------------

  /**
   * Ordered choice e1 / e2 / ... eN.
   * @constructor
   * @extends {Parser}
   * @param {!Array<!Parser>} alternatives
   * @param {string=} name
   */
  function Choice(alternatives, name) {
    Parser.call(this, name || 'Choice', true);
    this.alternatives = alternatives;
  }
  Choice.prototype = Object.create(Parser.prototype);
  Choice.prototype.parseAt = function(ctx, pos) {
    var lastFail = null;
    for (var i = 0; i < this.alternatives.length; i++) {
      var res = this.alternatives[i]._evalCached(ctx, pos);
      if (res.success) return res;
      lastFail = res;
      if (res.committed) return res;
    }
    return lastFail || new ParseResult(false, null, pos, 'No matching choice alternative');
  };

  // --- Repetition -------------------------------------------------------------

  /**
   * Matches 0+ or 1+ repetitions of child.
   * @constructor
   * @extends {Parser}
   * @param {!Parser} child
   * @param {number=} minCount
   * @param {string=} name
   */
  function Repetition(child, minCount, name) {
    Parser.call(this, name || ('Repetition(min=' + (minCount || 0) + ')'), true);
    this.child = child;
    this.minCount = minCount || 0;
  }
  Repetition.prototype = Object.create(Parser.prototype);
  Repetition.prototype.parseAt = function(ctx, pos) {
    var currPos = pos;
    var results = [];
    while (true) {
      var res = this.child._evalCached(ctx, currPos);
      if (!res.success || res.nextPos === currPos) break;
      results.push(res.value);
      currPos = res.nextPos;
    }
    if (results.length < this.minCount) {
      return new ParseResult(false, null, pos,
        'Expected at least ' + this.minCount + ' repetitions, got ' + results.length);
    }
    return new ParseResult(true, results, currPos);
  };

  // --- Optional ---------------------------------------------------------------

  /**
   * Optional match e?. Always succeeds.
   * @constructor
   * @extends {Parser}
   * @param {!Parser} child
   * @param {*=} defaultValue
   * @param {string=} name
   */
  function Optional(child, defaultValue, name) {
    Parser.call(this, name || 'Optional', true);
    this.child = child;
    this.defaultValue = defaultValue !== undefined ? defaultValue : null;
  }
  Optional.prototype = Object.create(Parser.prototype);
  Optional.prototype.parseAt = function(ctx, pos) {
    var res = this.child._evalCached(ctx, pos);
    if (res.success) return new ParseResult(true, res.value, res.nextPos);
    return new ParseResult(true, this.defaultValue, pos);
  };

  // --- Predicate (lookahead) --------------------------------------------------

  /**
   * Positive (&e) or negative (!e) lookahead. Never consumes input.
   * @constructor
   * @extends {Parser}
   * @param {!Parser} child
   * @param {boolean=} isPositive
   * @param {string=} name
   */
  function Predicate(child, isPositive, name) {
    Parser.call(this, name || (isPositive !== false ? 'AndPred' : 'NotPred'), false);
    this.child = child;
    this.isPositive = isPositive !== false;
  }
  Predicate.prototype = Object.create(Parser.prototype);
  Predicate.prototype.parseAt = function(ctx, pos) {
    var res = this.child._evalCached(ctx, pos);
    if (this.isPositive) {
      if (res.success) return new ParseResult(true, null, pos);
      return new ParseResult(false, null, pos, 'Positive predicate failed');
    }
    if (!res.success) return new ParseResult(true, null, pos);
    return new ParseResult(false, null, pos, 'Negative predicate matched forbidden input');
  };

  // --- Cut --------------------------------------------------------------------

  /**
   * Cut operator — commits choice, prevents backtracking.
   * @constructor
   * @extends {Parser}
   */
  function Cut() {
    Parser.call(this, 'Cut', false);
  }
  Cut.prototype = Object.create(Parser.prototype);
  Cut.prototype.parseAt = function(ctx, pos) {
    return new ParseResult(true, null, pos, null, true /* committed */);
  };

  // --- RuleRef ----------------------------------------------------------------

  /**
   * Lazy forward reference for mutually recursive rules.
   * @constructor
   * @extends {Parser}
   * @param {string} name
   */
  function RuleRef(name) {
    Parser.call(this, name, true);
    this.target = null;
  }
  RuleRef.prototype = Object.create(Parser.prototype);
  RuleRef.prototype.define = function(target) {
    this.target = target;
    return this;
  };
  RuleRef.prototype.parseAt = function(ctx, pos) {
    if (!this.target) throw new Error("[PEG] RuleRef '" + this.name + "' has not been defined.");
    return this.target._evalCached(ctx, pos);
  };

  // --- MappedParser -----------------------------------------------------------

  /**
   * Applies a transform function to the child's successful value.
   * @constructor
   * @extends {Parser}
   * @param {!Parser} child
   * @param {function(*): *} fn
   */
  function MappedParser(child, fn) {
    Parser.call(this, 'Map(' + (child.name || 'anon') + ')', true);
    this.child = child;
    this.fn = fn;
  }
  MappedParser.prototype = Object.create(Parser.prototype);
  MappedParser.prototype.parseAt = function(ctx, pos) {
    var res = this.child._evalCached(ctx, pos);
    if (!res.success) return new ParseResult(false, null, pos, res.errorMsg);
    return new ParseResult(true, this.fn(res.value), res.nextPos);
  };

  // ===========================================================================
  // Section 8 — Combinator factory helpers (mirrors Python shorthand aliases)
  // ===========================================================================

  /** @param {string} s @return {!Literal} */
  function lit(s) { return new Literal(s); }

  /** @param {!RegExp} r @param {string=} n @return {!Regex} */
  function reg(r, n) { return new Regex(r, n); }

  /**
   * @param {!Array<!Parser>} parsers
   * @param {string=} n
   * @return {!Sequence}
   */
  function seq(parsers, n) { return new Sequence(parsers, n); }

  /**
   * @param {!Array<!Parser>} alts
   * @param {string=} n
   * @return {!Choice}
   */
  function choice(alts, n) { return new Choice(alts, n); }

  /** @param {!Parser} p @return {!Repetition} */
  function star(p) { return new Repetition(p, 0); }

  /** @param {!Parser} p @return {!Repetition} */
  function plus(p) { return new Repetition(p, 1); }

  /** @param {!Parser} p @param {*=} def @return {!Optional} */
  function opt(p, def) { return new Optional(p, def); }

  /** @param {!Parser} p @return {!Predicate} */
  function notPred(p) { return new Predicate(p, false); }

  /** @param {!Parser} p @return {!Predicate} */
  function andPred(p) { return new Predicate(p, true); }

  // ===========================================================================
  // Section 9 — AOT-compiled Lucene Boolean Query Grammar
  //
  // The grammar is built ONCE at module load time (AOT compile step).
  // Each parse() invocation creates a fresh ParseContext (memoization table)
  // but reuses the pre-built combinator tree — O(N) per invocation.
  // ===========================================================================

  // Forward refs for mutual recursion
  var _refExpression = new RuleRef('Expression');
  var _refOrTerm = new RuleRef('OrTerm');
  var _refAndTerm = new RuleRef('AndTerm');
  var _refPrimary = new RuleRef('Primary');

  // Whitespace (required and optional)
  var WS_REQ = reg(/[ \t\r\n]+/, 'WS');
  var WS_OPT = opt(WS_REQ, '');

  // Boolean keywords (case-insensitive, not followed by word chars)
  var KW_AND = reg(/AND(?!\w)/, 'AND');
  var KW_OR  = reg(/OR(?!\w)/, 'OR');
  var KW_NOT = reg(/NOT(?!\w)/, 'NOT');

  // Phrase: "anything except closing quote"
  var PHRASE = seq([
    lit('"'),
    reg(/[^"]*/, 'phrase-content'),
    lit('"')
  ], 'Phrase').map(function(v) {
    return {type: 'phrase', value: v[1]};
  });

  // Word: non-whitespace, non-special characters
  // Must not start with a keyword (AND/OR/NOT) to avoid ambiguity
  var WORD_CHARS = reg(/[^\s():"]+/, 'word');
  var WORD = new MappedParser(
    seq([
      notPred(choice([KW_AND, KW_OR, KW_NOT])),
      WORD_CHARS
    ], 'Word'),
    function(v) { return {type: 'word', value: v[1]}; }
  );

  // FieldQuery: identifier ':' (phrase | word)
  var FIELD_NAME = reg(/[a-zA-Z_][a-zA-Z0-9_]*/, 'field-name');
  var FIELD_QUERY = seq([
    FIELD_NAME,
    lit(':'),
    choice([PHRASE, WORD])
  ], 'FieldQuery').map(function(v) {
    return {type: 'field', field: v[0], value: v[2]};
  });

  // Group: '(' Expression ')'
  var GROUP = seq([
    lit('('),
    WS_OPT,
    _refExpression,
    WS_OPT,
    lit(')')
  ], 'Group').map(function(v) {
    return {type: 'group', expr: v[2]};
  });

  // Primary: Group / FieldQuery / Phrase / Word
  var PRIMARY = new Choice([GROUP, FIELD_QUERY, PHRASE, WORD], 'Primary');
  _refPrimary.define(PRIMARY);

  // AndTerm: (NOT WS)? Primary
  var AND_TERM = seq([
    opt(seq([KW_NOT, WS_REQ])),
    _refPrimary
  ], 'AndTerm').map(function(v) {
    var notClause = v[0];
    if (notClause) {
      return {type: 'not', expr: v[1]};
    }
    return v[1];
  });
  _refAndTerm.define(AND_TERM);

  // OrTerm: AndTerm (WS AND WS AndTerm | WS AndTerm)*
  // Implicit AND when terms are adjacent (separated by whitespace)
  var EXPLICIT_AND = seq([WS_REQ, KW_AND, WS_REQ, _refAndTerm]).map(function(v) { return v[3]; });
  var IMPLICIT_AND = seq([WS_REQ, notPred(choice([KW_OR, KW_AND])), _refAndTerm]).map(function(v) { return v[2]; });
  var OR_TERM = seq([
    _refAndTerm,
    star(choice([EXPLICIT_AND, IMPLICIT_AND]))
  ], 'OrTerm').map(function(v) {
    var head = v[0];
    var tail = v[1];
    if (!tail || tail.length === 0) return head;
    var operands = [head].concat(tail);
    return {type: 'and', operands: operands};
  });
  _refOrTerm.define(OR_TERM);

  // Expression: OrTerm (WS OR WS OrTerm)*
  var EXPRESSION = seq([
    _refOrTerm,
    star(seq([WS_OPT, KW_OR, WS_OPT, _refOrTerm]).map(function(v) { return v[3]; }))
  ], 'Expression').map(function(v) {
    var head = v[0];
    var tail = v[1];
    if (!tail || tail.length === 0) return head;
    var operands = [head].concat(tail);
    return {type: 'or', operands: operands};
  });
  _refExpression.define(EXPRESSION);

  // Root Query: WS? Expression WS? (must consume entire input)
  var QUERY_GRAMMAR = seq([WS_OPT, EXPRESSION, WS_OPT], 'Query').map(function(v) {
    return v[1];
  });

  // ===========================================================================
  // Section 10 — QueryValidator public facade
  // ===========================================================================

  /**
   * @typedef {{
   *   valid: boolean,
   *   error: (?string),
   *   offset: (?number),
   *   line: (?number),
   *   col: (?number),
   *   expected: (!Array<string>),
   *   hint: (?string),
   *   ast: (*|undefined)
   * }}
   */
  var ValidationResult;

  /**
   * QueryValidator — validates and parses Lucene-style boolean search queries.
   *
   * The grammar is pre-compiled (AOT) at module load time and shared across
   * all QueryValidator instances. Each validate()/parse() call creates a
   * fresh ParseContext (memoization table) for O(N) parsing.
   *
   * @constructor
   * @struct
   * @final
   */
  function QueryValidator() {}

  /**
   * Validates a query string and returns a structured result.
   *
   * @param {string} queryString  The raw search query to validate.
   * @return {!ValidationResult}
   */
  QueryValidator.prototype.validate = function(queryString) {
    if (typeof queryString !== 'string') {
      return {valid: false, error: 'Query must be a string', offset: null, line: null, col: null, expected: [], hint: null};
    }

    // Empty query is valid (returns null AST)
    var trimmed = queryString.trim();
    if (trimmed.length === 0) {
      return {valid: true, error: null, offset: null, line: null, col: null, expected: [], hint: null, ast: null};
    }

    try {
      var ast = QUERY_GRAMMAR.parse(trimmed);
      return {valid: true, error: null, offset: null, line: null, col: null, expected: [], hint: null, ast: ast};
    } catch (e) {
      if (e instanceof PEGSyntaxError || e.name === 'PEGSyntaxError') {
        return {
          valid: false,
          error: e.message || e.formattedMessage || String(e),
          offset: e.pos != null ? e.pos : null,
          line: e.line != null ? e.line : null,
          col: e.col != null ? e.col : null,
          expected: e.expected || [],
          hint: e.hint || null
        };
      }
      return {valid: false, error: String(e), offset: null, line: null, col: null, expected: [], hint: null};
    }
  };

  /**
   * Parses a query string and returns the AST.
   * Throws PEGSyntaxError on invalid input.
   *
   * @param {string} queryString
   * @return {*} AST node
   */
  QueryValidator.prototype.parse = function(queryString) {
    var trimmed = (queryString || '').trim();
    if (!trimmed) return null;
    return QUERY_GRAMMAR.parse(trimmed);
  };

  // ===========================================================================
  // Section 11 — Export
  //
  // Export both the PEG Runtime primitives (for advanced use) and the
  // high-level QueryValidator facade.
  // ===========================================================================

  var Application = global['Application'] = global['Application'] || {};
  var frameworks = Application['frameworks'] = Application['frameworks'] || {};
  global['App'] = Application;
  global['yuzora'] = Application;

  // High-level facade
  frameworks['QueryValidator'] = QueryValidator;
  global['QueryValidator'] = QueryValidator;

  // PEG Runtime Engine (for grammar composition in other modules)
  var peg = frameworks['peg'] = frameworks['peg'] || {};
  peg['ParseResult']   = ParseResult;
  peg['ParseContext']  = ParseContext;
  peg['PEGSyntaxError'] = PEGSyntaxError;
  peg['Parser']        = Parser;
  peg['Literal']       = Literal;
  peg['Regex']         = Regex;
  peg['Sequence']      = Sequence;
  peg['Choice']        = Choice;
  peg['Repetition']    = Repetition;
  peg['Optional']      = Optional;
  peg['Predicate']     = Predicate;
  peg['Cut']           = Cut;
  peg['RuleRef']       = RuleRef;
  peg['MappedParser']  = MappedParser;
  peg['lit']           = lit;
  peg['reg']           = reg;
  peg['seq']           = seq;
  peg['choice']        = choice;
  peg['star']          = star;
  peg['plus']          = plus;
  peg['opt']           = opt;
  peg['notPred']       = notPred;
  peg['andPred']       = andPred;

})(window);
