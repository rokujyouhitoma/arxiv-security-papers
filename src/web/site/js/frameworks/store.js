/**
 * @fileoverview Lightweight Reactive State Store with Pub/Sub Integration and Prototype Pollution Defense.
 * Centralizes single-source-of-truth state for the enterprise console.
 * Part of yuzora-frameworks integration (DSN-27 / Issue 342).
 */

(function() {
  'use strict';

/**
 * Reactive State Store.
 * Provides granular key-level subscriptions, Pub/Sub event broadcasting,
 * shallow snapshot isolation, and prototype pollution defenses.
 */
class StateStore {
  /**
   * @param {!Object<string, *>=} initialState Initial state dictionary
   * @param {?Object=} publisher Optional event publisher instance (Publisher)
   */
  constructor(initialState = {}, publisher = null) {
    /** @private @type {!Object<string, *>} */
    this.state_ = Object.create(null);
    /** @private @type {?Object} */
    this.publisher_ = publisher;
    /** @private @type {!Map<string, !Set<function(*, *, string): void>>} */
    this.listeners_ = new Map();

    if (initialState && typeof initialState === 'object') {
      this.update(initialState);
    }
  }

  /**
   * Validates key against prototype pollution.
   * @param {string} key
   * @private
   */
  validateKey_(key) {
    if (typeof key !== 'string' || !key) {
      throw new Error('State key must be a non-empty string');
    }
    if (key === '__proto__' || key === 'constructor' || key === 'prototype') {
      throw new Error(`Prototype pollution attempt detected for key: ${key}`);
    }
  }

  /**
   * Retrieves value for a given key, or defaultValue if undefined.
   * @param {string} key
   * @param {*=} defaultValue
   * @return {*}
   */
  get(key, defaultValue = undefined) {
    this.validateKey_(key);
    return Object.prototype.hasOwnProperty.call(this.state_, key)
      ? this.state_[key]
      : defaultValue;
  }

  /**
   * Sets value for a single key and notifies subscribers if changed.
   * @param {string} key
   * @param {*} value
   * @return {boolean} True if value changed, false otherwise
   */
  set(key, value) {
    this.validateKey_(key);
    const prev = this.get(key, undefined);

    if (Object.is(prev, value)) {
      return false;
    }

    this.state_[key] = value;
    this.notify_(key, prev, value);
    return true;
  }

  /**
   * Atomically updates multiple state properties.
   * @param {!Object<string, *>} partialState
   */
  update(partialState) {
    if (!partialState || typeof partialState !== 'object') {
      return;
    }
    const keys = Object.keys(partialState);
    for (const key of keys) {
      this.set(key, partialState[key]);
    }
  }

  /**
   * Notifies subscribers and broadcasts via Publisher.
   * @param {string} key
   * @param {*} prev
   * @param {*} current
   * @private
   */
  notify_(key, prev, current) {
    // 1. Direct key subscribers
    const keyListeners = this.listeners_.get(key);
    if (keyListeners) {
      for (const listener of keyListeners) {
        try {
          listener(current, prev, key);
        } catch (e) {
          console.error(`Error in StateStore listener for key '${key}':`, e);
        }
      }
    }

    // 2. Wildcard subscribers
    const wildcardListeners = this.listeners_.get('*');
    if (wildcardListeners) {
      for (const listener of wildcardListeners) {
        try {
          listener(current, prev, key);
        } catch (e) {
          console.error(`Error in StateStore wildcard listener:`, e);
        }
      }
    }

    // 3. Publisher Pub/Sub integration
    if (this.publisher_ && typeof this.publisher_.publish === 'function') {
      this.publisher_.publish(`state:change:${key}`, { key, prev, current });
      this.publisher_.publish('state:changed', { key, prev, current });
    }
  }

  /**
   * Subscribes to changes for a specific key (or '*' for all changes).
   * Returns an unsubscribe function.
   * @param {string} key Target state key or '*'
   * @param {function(*, *, string): void} callback Receives (current, prev, key)
   * @return {function(): void} Unsubscribe function
   */
  subscribe(key, callback) {
    if (key !== '*') {
      this.validateKey_(key);
    }
    if (typeof callback !== 'function') {
      throw new Error('Subscriber callback must be a function');
    }

    if (!this.listeners_.has(key)) {
      this.listeners_.set(key, new Set());
    }
    const set = this.listeners_.get(key);
    set.add(callback);

    return () => {
      set.delete(callback);
      if (set.size === 0) {
        this.listeners_.delete(key);
      }
    };
  }

  /**
   * Returns a shallow clone of the current state snapshot.
   * @return {!Object<string, *>}
   */
  getState() {
    const snapshot = Object.create(null);
    return Object.assign(snapshot, this.state_);
  }

  /**
   * Resets all state to given initial dictionary and notifies.
   * @param {!Object<string, *>=} initialState
   */
  reset(initialState = {}) {
    const oldSnapshot = this.getState();
    this.state_ = Object.create(null);

    if (initialState && typeof initialState === 'object') {
      const keys = Object.keys(initialState);
      for (const key of keys) {
        this.validateKey_(key);
        this.state_[key] = initialState[key];
      }
    }

    if (this.publisher_ && typeof this.publisher_.publish === 'function') {
      this.publisher_.publish('state:reset', { prev: oldSnapshot, current: this.getState() });
    }
  }
}

  // Export to global scope & Application frameworks namespace
  if (typeof window !== 'undefined') {
    window.StateStore = StateStore;

    window.Application = window.Application || {};
    window.Application.frameworks = window.Application.frameworks || {};
    window.Application.frameworks.StateStore = StateStore;
    window.App = window.Application;
    window.yuzora = window.Application;
  }

  // Export for Node.js / CommonJS testing
  if (typeof module !== 'undefined' && module.exports) {
    module.exports = {
      StateStore: StateStore
    };
  }
})();
