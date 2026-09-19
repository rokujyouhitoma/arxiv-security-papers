/**
 * @fileoverview RadixTrie - Compressed prefix tree (Patricia/Radix Tree).
 *
 * A direct port of src/core/structures/radix_trie.py with O(K) insert,
 * exact-search, and prefix-search operations.
 *
 * Primary use case: 0ms incremental autocomplete for the search bars in the
 * enterprise console (#searchInput, #globalSearchInput).
 *
 * Security notes:
 *  - Keys are length-capped at MAX_KEY_LENGTH (512) to prevent DoS via
 *    pathologically deep trees.
 *  - Internal node maps use Map (not plain objects) to prevent Prototype
 *    Pollution attacks such as __proto__ injection.
 *  - No eval, no innerHTML, no external I/O.
 *
 * @package
 */

(function(global) {
  'use strict';

  /** @const {number} Maximum allowed key length. */
  var MAX_KEY_LENGTH = 512;

  /** @const {number} Default suggestion limit. */
  var DEFAULT_LIMIT = 10;

  /** @const {number} Hard upper cap for searchPrefix results. */
  var MAX_LIMIT = 1000;

  // ---------------------------------------------------------------------------
  // Internal helpers
  // ---------------------------------------------------------------------------

  /**
   * Returns the length of the longest common prefix between two strings.
   * @param {string} a
   * @param {string} b
   * @return {number}
   */
  function commonPrefixLen(a, b) {
    var len = Math.min(a.length, b.length);
    for (var i = 0; i < len; i++) {
      if (a[i] !== b[i]) return i;
    }
    return len;
  }

  // ---------------------------------------------------------------------------
  // RadixNode (internal)
  // ---------------------------------------------------------------------------

  /**
   * @constructor
   * @param {string} prefix
   */
  function RadixNode(prefix) {
    /** @type {string} */
    this.prefix = prefix;
    /** @type {boolean} */
    this.isTerminal = false;
    /** @type {*} */
    this.value = undefined;
    /** @type {!Map<string, !RadixNode>} Keyed by first character of child prefix. */
    this.children = new Map();
  }

  // ---------------------------------------------------------------------------
  // RadixTrie (public)
  // ---------------------------------------------------------------------------

  /**
   * RadixTrie is a compressed prefix tree for O(K) prefix operations.
   * All keys are strings; values are arbitrary.
   *
   * @constructor
   * @struct
   * @final
   */
  function RadixTrie() {
    /** @private {!RadixNode} */
    this.root_ = new RadixNode('');
    /** @private {number} */
    this.size_ = 0;
  }

  /**
   * Returns the number of unique keys stored.
   * @return {number}
   */
  RadixTrie.prototype.size = function() {
    return this.size_;
  };

  /**
   * Inserts or updates a key-value pair.
   * @param {string} key
   * @param {*} value
   */
  RadixTrie.prototype.insert = function(key, value) {
    if (typeof key !== 'string') {
      throw new TypeError('[RadixTrie] key must be a string.');
    }
    if (key.length > MAX_KEY_LENGTH) {
      throw new RangeError('[RadixTrie] key exceeds MAX_KEY_LENGTH (' + MAX_KEY_LENGTH + ').');
    }

    var curr = this.root_;
    var rem = key;

    while (rem.length > 0) {
      var firstChar = rem[0];
      if (!curr.children.has(firstChar)) {
        // No matching child — create a new leaf
        var leaf = new RadixNode(rem);
        leaf.isTerminal = true;
        leaf.value = value;
        curr.children.set(firstChar, leaf);
        this.size_++;
        return;
      }

      var child = curr.children.get(firstChar);
      var cLen = commonPrefixLen(rem, child.prefix);

      if (cLen < child.prefix.length) {
        // Need to split the existing edge
        var splitNode = new RadixNode(child.prefix.slice(0, cLen));
        child.prefix = child.prefix.slice(cLen);
        splitNode.children.set(child.prefix[0], child);
        curr.children.set(firstChar, splitNode);
        curr = splitNode;
      } else {
        curr = child;
      }
      rem = rem.slice(cLen);
    }

    // curr is the node for the full key
    if (!curr.isTerminal) {
      curr.isTerminal = true;
      this.size_++;
    }
    curr.value = value;
  };

  /**
   * Retrieves the value associated with an exact key, or undefined if not found.
   * @param {string} key
   * @return {*}
   */
  RadixTrie.prototype.get = function(key) {
    var node = this.findExactNode_(key);
    if (node !== null && node.isTerminal) return node.value;
    return undefined;
  };

  /**
   * Returns true if the exact key exists.
   * @param {string} key
   * @return {boolean}
   */
  RadixTrie.prototype.contains = function(key) {
    var node = this.findExactNode_(key);
    return node !== null && node.isTerminal;
  };

  /**
   * Finds all key-value entries whose keys start with prefix.
   * @param {string} prefix
   * @param {number=} limit  Maximum results (default: 10, cap: 1000).
   * @return {!Array<!Array>}  Array of [key, value] pairs.
   */
  RadixTrie.prototype.searchPrefix = function(prefix, limit) {
    var effLimit = Math.min(
        Math.max(1, typeof limit === 'number' ? limit : DEFAULT_LIMIT),
        MAX_LIMIT);

    var found = this.findPrefixNode_(prefix);
    if (found === null) return [];

    var startNode = found[0];
    var baseKey = found[1];

    var results = [];
    // Iterative DFS via explicit stack
    var stack = [[startNode, baseKey]];

    while (stack.length > 0 && results.length < effLimit) {
      var top = stack.pop();
      var curr = top[0];
      var pathAcc = top[1];

      if (curr.isTerminal && curr.value !== undefined) {
        results.push([pathAcc, curr.value]);
      }

      // Push children in reverse-sorted order for deterministic forward output
      var childKeys = Array.from(curr.children.keys()).sort().reverse();
      for (var i = 0; i < childKeys.length; i++) {
        var ch = curr.children.get(childKeys[i]);
        stack.push([ch, pathAcc + ch.prefix]);
      }
    }

    return results;
  };

  /**
   * Finds the longest prefix of text that exists as a key in the trie.
   * Returns [key, value] or null.
   * @param {string} text
   * @return {?Array}
   */
  RadixTrie.prototype.longestPrefix = function(text) {
    var curr = this.root_;
    var rem = text;
    var accum = '';
    var best = null;

    while (curr !== null && rem.length > 0) {
      var firstChar = rem[0];
      var child = curr.children.get(firstChar);
      if (!child || !rem.startsWith(child.prefix)) break;
      accum += child.prefix;
      rem = rem.slice(child.prefix.length);
      curr = child;
      if (curr.isTerminal && curr.value !== undefined) {
        best = [accum, curr.value];
      }
    }

    return best;
  };

  /**
   * Deletes a key from the trie. Returns true if the key was found and removed.
   * @param {string} key
   * @return {boolean}
   */
  RadixTrie.prototype.delete = function(key) {
    return this.deleteHelper_(this.root_, key);
  };

  /**
   * Recursive helper for delete.
   * @param {!RadixNode} curr
   * @param {string} rem
   * @return {boolean}
   * @private
   */
  RadixTrie.prototype.deleteHelper_ = function(curr, rem) {
    if (rem.length === 0) {
      if (!curr.isTerminal) return false;
      curr.isTerminal = false;
      curr.value = undefined;
      this.size_--;
      return true;
    }

    var firstChar = rem[0];
    var child = curr.children.get(firstChar);
    if (!child || !rem.startsWith(child.prefix)) return false;

    var deleted = this.deleteHelper_(child, rem.slice(child.prefix.length));
    if (!deleted) return false;

    // Prune empty non-terminal leaf nodes
    if (!child.isTerminal && child.children.size === 0) {
      curr.children.delete(firstChar);
    } else if (!child.isTerminal && child.children.size === 1) {
      // Merge single-child node
      var onlyChild = child.children.values().next().value;
      child.prefix = child.prefix + onlyChild.prefix;
      child.isTerminal = onlyChild.isTerminal;
      child.value = onlyChild.value;
      child.children = onlyChild.children;
    }
    return true;
  };

  /**
   * Clears all entries.
   */
  RadixTrie.prototype.clear = function() {
    this.root_ = new RadixNode('');
    this.size_ = 0;
  };

  /**
   * Returns all key-value pairs as an array of [key, value].
   * @return {!Array<!Array>}
   */
  RadixTrie.prototype.entries = function() {
    return this.searchPrefix('', MAX_LIMIT);
  };

  /**
   * Navigate to node exactly matching key.
   * @param {string} key
   * @return {?RadixNode}
   * @private
   */
  RadixTrie.prototype.findExactNode_ = function(key) {
    var curr = this.root_;
    var rem = key;
    while (rem.length > 0) {
      var child = curr.children.get(rem[0]);
      if (!child || !rem.startsWith(child.prefix)) return null;
      rem = rem.slice(child.prefix.length);
      curr = child;
    }
    return curr;
  };

  /**
   * Locate the subtree root and accumulated key prefix matching a given prefix.
   * @param {string} prefix
   * @return {?Array}  [RadixNode, accumulatedKey] or null.
   * @private
   */
  RadixTrie.prototype.findPrefixNode_ = function(prefix) {
    var curr = this.root_;
    var rem = prefix;
    var accum = '';

    if (prefix.length === 0) return [curr, accum];

    while (rem.length > 0) {
      var firstChar = rem[0];
      var child = curr.children.get(firstChar);
      if (!child) return null;

      if (rem.length <= child.prefix.length) {
        // rem is a prefix of child.prefix
        if (child.prefix.startsWith(rem)) {
          accum += child.prefix;
          return [child, accum];
        }
        return null;
      }

      if (!rem.startsWith(child.prefix)) return null;

      accum += child.prefix;
      rem = rem.slice(child.prefix.length);
      curr = child;
    }

    return [curr, accum];
  };

  // ---------------------------------------------------------------------------
  // Export
  // ---------------------------------------------------------------------------
  var yuzora = global['yuzora'] = global['yuzora'] || {};
  var frameworks = yuzora['frameworks'] = yuzora['frameworks'] || {};
  frameworks['RadixTrie'] = RadixTrie;

})(window);
