/**
 * @fileoverview Adaptive Replacement Cache (ARC) for Web Frontend.
 * Self-tuning cache balancing Recency (T1, B1) and Frequency (T2, B2) with scan resistance.
 * Megiddo & Modha (FAST '03) compliant.
 * Port of src/core/structures/arc_cache.py to JavaScript.
 * Part of yuzora-frameworks integration (DSN-27 / Issue 346).
 */

(function() {
  'use strict';

  /**
   * Pops and returns the least recently used key and value from a Map.
   * @param {!Map} map
   * @return {?Array<*>} [key, value] or null if empty
   * @private
   */
  function popLru_(map) {
    var it = map.keys().next();
    if (it.done) {
      return null;
    }
    var key = it.value;
    var val = map.get(key);
    map.delete(key);
    return [key, val];
  }

  /**
   * Evaluates if T1 should be evicted rather than T2.
   * @param {number} t1Len
   * @param {number} p
   * @param {boolean} inB2
   * @return {boolean}
   * @private
   */
  function shouldEvictT1_(t1Len, p, inB2) {
    if (t1Len === 0) {
      return false;
    }
    if (t1Len > p) {
      return true;
    }
    return inB2 && (t1Len === Math.floor(p));
  }

  /**
   * Evicts from T1 to B1 or from T2 to B2 based on parameter p when full.
   * @param {!Map<*, *>} t1
   * @param {!Map<*, *>} t2
   * @param {!Map<*, *>} b1
   * @param {!Map<*, *>} b2
   * @param {number} p
   * @param {number} capacity
   * @param {boolean} inB2
   * @private
   */
  function stepReplace_(t1, t2, b1, b2, p, capacity, inB2) {
    if (t1.size + t2.size < capacity) {
      return;
    }
    if (shouldEvictT1_(t1.size, p, inB2)) {
      var popped1 = popLru_(t1);
      if (popped1) {
        b1.set(popped1[0], null);
      }
    } else if (t2.size > 0) {
      var popped2 = popLru_(t2);
      if (popped2) {
        b2.set(popped2[0], null);
      }
    }
  }

  /**
   * Discards an old ghost entry when history capacity bounds are reached.
   * @param {!Map<*, *>} t1
   * @param {!Map<*, *>} t2
   * @param {!Map<*, *>} b1
   * @param {!Map<*, *>} b2
   * @param {number} capacity
   * @private
   */
  function pruneGhostForMiss_(t1, t2, b1, b2, capacity) {
    if (t1.size + b1.size === capacity) {
      if (t1.size < capacity && b1.size > 0) {
        popLru_(b1);
      }
    } else {
      var total = t1.size + t2.size + b1.size + b2.size;
      if (total >= 2 * capacity && b2.size > 0) {
        popLru_(b2);
      }
    }
  }

  /**
   * Adaptive Replacement Cache (ARC).
   * Maintains self-tuning balance between recency and frequency caches with scan resistance.
   *
   * @constructor
   * @param {number=} capacity Maximum number of active cache entries (default: 128)
   */
  function ARCCache(capacity) {
    var capNum = Number(capacity);
    if (!Number.isFinite(capNum) || capNum < 1) {
      this.capacity = 128;
    } else {
      this.capacity = Math.min(Math.floor(capNum), 1000000);
    }

    /** @type {number} */
    this.p = 0.0;
    /** @type {!Map<*, *>} */
    this.t1 = new Map();
    /** @type {!Map<*, *>} */
    this.t2 = new Map();
    /** @type {!Map<*, *>} */
    this.b1 = new Map();
    /** @type {!Map<*, *>} */
    this.b2 = new Map();
    /** @private @type {number} */
    this.hits_ = 0;
    /** @private @type {number} */
    this.misses_ = 0;
  }

  /**
   * Returns current count of active cache entries (T1 + T2).
   * @return {number}
   */
  ARCCache.prototype.size = function() {
    return this.t1.size + this.t2.size;
  };

  /**
   * Checks if key exists in active cache (T1 or T2).
   * @param {*} key
   * @return {boolean}
   */
  ARCCache.prototype.has = function(key) {
    return this.t1.has(key) || this.t2.has(key);
  };

  /**
   * Looks up key in cache. On hit, promotes entry to T2 (MRU).
   * @param {*} key
   * @param {*=} defaultValue
   * @return {*} Cached value or defaultValue on miss
   */
  ARCCache.prototype.get = function(key, defaultValue) {
    var defaultVal = (defaultValue !== undefined) ? defaultValue : null;
    if (this.t1.has(key)) {
      var val1 = this.t1.get(key);
      this.t1.delete(key);
      this.t2.set(key, val1);
      this.hits_++;
      return val1;
    }
    if (this.t2.has(key)) {
      var val2 = this.t2.get(key);
      this.t2.delete(key);
      this.t2.set(key, val2);
      this.hits_++;
      return val2;
    }

    this.misses_++;
    return defaultVal;
  };

  /**
   * Internal eviction step.
   * @param {boolean} inB2
   * @private
   */
  ARCCache.prototype.replace_ = function(inB2) {
    stepReplace_(this.t1, this.t2, this.b1, this.b2, this.p, this.capacity, inB2);
  };

  /**
   * Adapts parameter p and moves key from B1 to T2.
   * @param {*} key
   * @param {*} value
   * @private
   */
  ARCCache.prototype.adaptB1_ = function(key, value) {
    var delta = Math.max(1.0, this.b2.size / Math.max(1, this.b1.size));
    this.p = Math.min(this.capacity, this.p + delta);
    this.replace_(false);
    this.b1.delete(key);
    this.t2.set(key, value);
  };

  /**
   * Adapts parameter p and moves key from B2 to T2.
   * @param {*} key
   * @param {*} value
   * @private
   */
  ARCCache.prototype.adaptB2_ = function(key, value) {
    var delta = Math.max(1.0, this.b1.size / Math.max(1, this.b2.size));
    this.p = Math.max(0.0, this.p - delta);
    this.replace_(true);
    this.b2.delete(key);
    this.t2.set(key, value);
  };

  /**
   * Inserts a new item missing from all lists into T1.
   * @param {*} key
   * @param {*} value
   * @private
   */
  ARCCache.prototype.insertMiss_ = function(key, value) {
    pruneGhostForMiss_(this.t1, this.t2, this.b1, this.b2, this.capacity);
    this.replace_(false);
    this.t1.set(key, value);
  };

  /**
   * Inserts or updates key-value pair with self-tuning eviction.
   * @param {*} key
   * @param {*} value
   */
  ARCCache.prototype.put = function(key, value) {
    if (this.t1.has(key)) {
      this.t1.delete(key);
      this.t2.set(key, value);
    } else if (this.t2.has(key)) {
      this.t2.delete(key);
      this.t2.set(key, value);
    } else if (this.b1.has(key)) {
      this.adaptB1_(key, value);
    } else if (this.b2.has(key)) {
      this.adaptB2_(key, value);
    } else {
      this.insertMiss_(key, value);
    }
  };

  /**
   * Alias for put(key, value).
   * @param {*} key
   * @param {*} value
   */
  ARCCache.prototype.set = function(key, value) {
    this.put(key, value);
  };

  /**
   * Deletes key from active and ghost caches.
   * @param {*} key
   * @return {boolean} True if key was present and deleted from active cache
   */
  ARCCache.prototype.delete = function(key) {
    var deleted = false;
    if (this.t1.has(key)) {
      this.t1.delete(key);
      deleted = true;
    }
    if (this.t2.has(key)) {
      this.t2.delete(key);
      deleted = true;
    }
    this.b1.delete(key);
    this.b2.delete(key);
    return deleted;
  };

  /**
   * Clears all active and ghost entries, resetting statistics and adapt parameter.
   */
  ARCCache.prototype.clear = function() {
    this.t1.clear();
    this.t2.clear();
    this.b1.clear();
    this.b2.clear();
    this.p = 0.0;
    this.hits_ = 0;
    this.misses_ = 0;
  };

  /**
   * Returns an array of all active keys in T1 and T2.
   * @return {!Array<*>}
   */
  ARCCache.prototype.keys = function() {
    var res = [];
    for (var k1 of this.t1.keys()) {
      res.push(k1);
    }
    for (var k2 of this.t2.keys()) {
      res.push(k2);
    }
    return res;
  };

  /**
   * Returns cache metrics and current internal partition state.
   * @return {{
   *   hits: number,
   *   misses: number,
   *   hitRatio: number,
   *   p: number,
   *   capacity: number,
   *   t1Size: number,
   *   t2Size: number,
   *   b1Size: number,
   *   b2Size: number,
   *   totalEntries: number
   * }}
   */
  ARCCache.prototype.getStats = function() {
    var total = this.hits_ + this.misses_;
    var ratio = total > 0 ? this.hits_ / total : 0.0;
    return {
      hits: this.hits_,
      misses: this.misses_,
      hitRatio: ratio,
      p: this.p,
      capacity: this.capacity,
      t1Size: this.t1.size,
      t2Size: this.t2.size,
      b1Size: this.b1.size,
      b2Size: this.b2.size,
      totalEntries: this.t1.size + this.t2.size
    };
  };

  // Export to global scope & Application frameworks namespace
  if (typeof window !== 'undefined') {
    window.ARCCache = ARCCache;

    window.Application = window.Application || {};
    window.Application.frameworks = window.Application.frameworks || {};
    window.Application.frameworks.ARCCache = ARCCache;
    window.App = window.Application;
    window.yuzora = window.Application;
  }

  // Export for Node.js / CommonJS testing
  if (typeof module !== 'undefined' && module.exports) {
    module.exports = {
      ARCCache: ARCCache
    };
  }
})();
