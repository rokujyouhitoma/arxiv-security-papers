/**
 * @fileoverview Disjoint Set (Union-Find) data structure for Web Frontend.
 * Ported from src/core/structures/disjoint_set.py.
 * Provides near-constant time O(alpha(N)) operations using Path Compression and Union by Rank.
 * Enables fast connected-component detection, LCC computation, and isolate clustering in CTI graphs.
 *
 * Zero external dependencies: Pure ES2022 / Closure Compiler compliant.
 */

(function() {
  'use strict';

  /**
   * Disjoint Set Union (DSU) / Union-Find data structure.
   * @constructor
   * @param {(!Array<*>|!Iterable<*>)=} opt_elements Initial elements to insert.
   */
  function DisjointSet(opt_elements) {
    /** @private {!Map<*, *>} Map of element -> parent representative */
    this.parent_ = new Map();

    /** @private {!Map<*, number>} Map of element -> rank tree depth */
    this.rank_ = new Map();

    /** @private {!Map<*, number>} Map of element -> component size */
    this.size_ = new Map();

    /** @private {number} Count of disjoint components */
    this.componentsCount_ = 0;

    if (opt_elements) {
      if (Array.isArray(opt_elements)) {
        for (var i = 0; i < opt_elements.length; i++) {
          this.add(opt_elements[i]);
        }
      } else if (typeof opt_elements[Symbol.iterator] === 'function') {
        var iter = opt_elements[Symbol.iterator]();
        var step = iter.next();
        while (!step.done) {
          this.add(step.value);
          step = iter.next();
        }
      }
    }
  }

  /**
   * Adds a single element as its own representative if not present.
   * @param {*} x
   * @return {boolean} True if newly added, False if already present
   */
  DisjointSet.prototype.add = function(x) {
    if (this.parent_.has(x)) {
      return false;
    }
    this.parent_.set(x, x);
    this.rank_.set(x, 0);
    this.size_.set(x, 1);
    this.componentsCount_++;
    return true;
  };

  /**
   * Checks if item is registered in the disjoint set.
   * @param {*} x
   * @return {boolean}
   */
  DisjointSet.prototype.has = function(x) {
    return this.parent_.has(x);
  };

  /**
   * Returns total number of distinct elements.
   * @return {number}
   */
  DisjointSet.prototype.size = function() {
    return this.parent_.size;
  };

  /**
   * Returns count of disjoint components.
   * @return {number}
   */
  DisjointSet.prototype.componentCount = function() {
    return this.componentsCount_;
  };

  /**
   * Alias for componentCount().
   * @return {number}
   */
  DisjointSet.prototype.getComponentCount = function() {
    return this.componentCount();
  };

  /**
   * Finds representative root of element x using iterative path compression.
   * Automatically registers x if not previously seen.
   * Time complexity: O(alpha(N)) amortized.
   * @param {*} x
   * @return {*} Representative root element
   */
  DisjointSet.prototype.find = function(x) {
    if (!this.parent_.has(x)) {
      this.add(x);
      return x;
    }

    var path = [];
    var curr = x;
    while (this.parent_.get(curr) !== curr) {
      path.push(curr);
      curr = this.parent_.get(curr);
    }

    // Path compression: flatten path directly to root
    for (var i = 0; i < path.length; i++) {
      this.parent_.set(path[i], curr);
    }
    return curr;
  };

  /**
   * Merges sets containing x and y using Union by Rank.
   * @param {*} x
   * @param {*} y
   * @return {boolean} True if merged, False if already in the same set
   */
  DisjointSet.prototype.union = function(x, y) {
    var rootX = this.find(x);
    var rootY = this.find(y);

    if (rootX === rootY) {
      return false;
    }

    var rankX = this.rank_.get(rootX) || 0;
    var rankY = this.rank_.get(rootY) || 0;
    var sizeX = this.size_.get(rootX) || 1;
    var sizeY = this.size_.get(rootY) || 1;

    if (rankX < rankY) {
      this.parent_.set(rootX, rootY);
      this.size_.set(rootY, sizeY + sizeX);
    } else {
      this.parent_.set(rootY, rootX);
      this.size_.set(rootX, sizeX + sizeY);
      if (rankX === rankY) {
        this.rank_.set(rootX, rankX + 1);
      }
    }

    this.componentsCount_--;
    return true;
  };

  /**
   * Returns True if x and y belong to the same connected component.
   * @param {*} x
   * @param {*} y
   * @return {boolean}
   */
  DisjointSet.prototype.connected = function(x, y) {
    if (!this.parent_.has(x) || !this.parent_.has(y)) {
      return false;
    }
    return this.find(x) === this.find(y);
  };

  /**
   * Returns the size of the connected component containing x.
   * @param {*} x
   * @return {number}
   */
  DisjointSet.prototype.componentSize = function(x) {
    var root = this.find(x);
    return this.size_.get(root) || 1;
  };

  /**
   * Groups all elements into disjoint sets keyed by their root representative.
   * @return {!Map<*, !Array<*>>}
   */
  DisjointSet.prototype.getComponents = function() {
    var groups = new Map();
    var keys = this.parent_.keys();
    for (var elem of keys) {
      var root = this.find(elem);
      if (!groups.has(root)) {
        groups.set(root, []);
      }
      groups.get(root).push(elem);
    }
    return groups;
  };

  /**
   * Returns elements of the Largest Connected Component (LCC).
   * @return {!Array<*>}
   */
  DisjointSet.prototype.getLargestComponent = function() {
    var groups = this.getComponents();
    var largest = [];
    for (var list of groups.values()) {
      if (list.length > largest.length) {
        largest = list;
      }
    }
    return largest;
  };

  /**
   * Returns isolated elements with component size == 1.
   * @return {!Array<*>}
   */
  DisjointSet.prototype.getIsolates = function() {
    var groups = this.getComponents();
    var isolates = [];
    for (var list of groups.values()) {
      if (list.length === 1) {
        isolates.push(list[0]);
      }
    }
    return isolates;
  };

  /**
   * Resets the disjoint set.
   */
  DisjointSet.prototype.clear = function() {
    this.parent_.clear();
    this.rank_.clear();
    this.size_.clear();
    this.componentsCount_ = 0;
  };

  // Export to global scope & Application frameworks namespace
  if (typeof window !== 'undefined') {
    window.DisjointSet = DisjointSet;

    window.Application = window.Application || {};
    window.Application.frameworks = window.Application.frameworks || {};
    window.Application.frameworks.DisjointSet = DisjointSet;
    window.App = window.Application;
    window.yuzora = window.Application;
  }

  // Export for Node.js / CommonJS testing
  if (typeof module !== 'undefined' && module.exports) {
    module.exports = {
      DisjointSet: DisjointSet
    };
  }
})();
