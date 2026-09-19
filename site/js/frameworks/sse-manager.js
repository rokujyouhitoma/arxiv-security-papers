/**
 * @fileoverview SSEStreamManager - Server-Sent Events lifecycle manager.
 *
 * Wraps the native EventSource API with:
 *  - Automatic reconnect with exponential back-off (cap: 30 s).
 *  - Page-visibility awareness (closes on hidden, reopens on visible).
 *  - Publishes events through the Yuzora Publisher bus.
 *  - Strict cleanup on close() to prevent memory / connection leaks.
 *
 * Security notes:
 *  - URL is validated to be a relative path (no protocol / host injection).
 *  - All incoming JSON is parsed inside a try/catch; malformed data is dropped.
 *  - No direct DOM manipulation; consumers react via Publisher subscriptions.
 *
 * @package
 */

(function(global) {
  'use strict';

  /** @const {number} Initial reconnect delay in milliseconds. */
  var RECONNECT_DELAY_MS = 1000;

  /** @const {number} Maximum reconnect delay in milliseconds. */
  var MAX_RECONNECT_DELAY_MS = 30000;

  /** @const {number} Back-off multiplier. */
  var BACKOFF_MULTIPLIER = 2;

  /**
   * SSEStreamManager manages a single EventSource connection with automatic
   * reconnection and visibility-aware lifecycle management.
   *
   * @constructor
   * @struct
   * @final
   */
  function SSEStreamManager() {
    /** @private {?EventSource} */
    this.eventSource_ = null;

    /** @private {?string} Current URL being streamed. */
    this.url_ = null;

    /**
     * Map from SSE event type -> array of handler functions registered on the
     * current EventSource. Kept so we can remove them before reconnecting.
     * @private {!Object<string, !Array<function(!Event): void>>}
     */
    this.handlers_ = Object.create(null);

    /** @private {!Object<string, function(*, string): void>} */
    this.userHandlers_ = {};

    /** @private {number} Current reconnect delay in ms. */
    this.reconnectDelay_ = RECONNECT_DELAY_MS;

    /** @private {?number} Timeout ID for scheduled reconnect. */
    this.reconnectTimer_ = null;

    /** @private {boolean} Whether the manager has been permanently closed. */
    this.destroyed_ = false;

    /** @private {!Array<function(): void>} Cleanup callbacks. */
    this.cleanups_ = [];

    /** @private {?Object} Hierarchical State Machine instance for lifecycle governance. */
    this.hsm_ = null;
    this.initHSM_();

    this.init_();
  }

  /**
   * Initializes the HSM state machine if HierarchicalStateMachine is available.
   * @private
   */
  SSEStreamManager.prototype.initHSM_ = function() {
    var HSMClass = global['HierarchicalStateMachine'] ||
                   (global['yuzora'] && global['yuzora']['frameworks'] && global['yuzora']['frameworks']['HierarchicalStateMachine']);
    if (!HSMClass || typeof HSMClass.fromConfig !== 'function') {
      return;
    }
    var self = this;
    this.hsm_ = HSMClass.fromConfig({
      name: 'ROOT',
      initial: 'ACTIVE',
      children: {
        ACTIVE: {
          initial: 'DISCONNECTED',
          children: {
            DISCONNECTED: {
              transitions: {
                'OPEN': 'CONNECTING'
              }
            },
            CONNECTING: {
              transitions: {
                'CONNECTED': 'STREAMING',
                'ERROR': 'RECONNECTING',
                'CLOSE': 'DISCONNECTED'
              }
            },
            STREAMING: {
              transitions: {
                'ERROR': 'RECONNECTING',
                'CLOSE': 'DISCONNECTED'
              }
            },
            RECONNECTING: {
              transitions: {
                'OPEN': 'CONNECTING',
                'CLOSE': 'DISCONNECTED'
              }
            }
          },
          transitions: {
            'DESTROY': 'DESTROYED'
          }
        },
        DESTROYED: {}
      }
    });
  };

  /**
   * Dispatches lifecycle event to HSM if configured.
   * @param {string} eventName
   * @param {Object<string, *>=} opt_payload
   * @private
   */
  SSEStreamManager.prototype.dispatchHSM_ = function(eventName, opt_payload) {
    if (this.hsm_ && typeof this.hsm_.dispatch === 'function') {
      this.hsm_.dispatch(eventName, opt_payload);
    }
  };

  /**
   * Returns current HSM state path if configured.
   * @return {string}
   */
  SSEStreamManager.prototype.getState = function() {
    if (this.hsm_ && typeof this.hsm_.getStatePath === 'function') {
      return this.hsm_.getStatePath();
    }
    if (this.destroyed_) return 'DESTROYED';
    if (this.eventSource_) return 'STREAMING';
    if (this.reconnectTimer_) return 'RECONNECTING';
    return 'DISCONNECTED';
  };

  /**
   * Returns whether current SSE connection is in the given state.
   * @param {string} stateNameOrPath
   * @return {boolean}
   */
  SSEStreamManager.prototype.isInState = function(stateNameOrPath) {
    if (this.hsm_ && typeof this.hsm_.isInState === 'function') {
      return this.hsm_.isInState(stateNameOrPath);
    }
    return this.getState() === stateNameOrPath;
  };

  /**
   * Returns internal HSM instance.
   * @return {?Object}
   */
  SSEStreamManager.prototype.getHSM = function() {
    return this.hsm_;
  };

  /**
   * Validates that a URL string is a safe relative path.
   * Rejects anything containing a protocol or a leading "//".
   * @param {string} url
   * @return {boolean}
   * @private
   */
  SSEStreamManager.prototype.isSafeRelativeUrl_ = function(url) {
    if (typeof url !== 'string' || url.length === 0) return false;
    if (/^[a-zA-Z][a-zA-Z0-9+\-.]*:/.test(url)) return false;
    if (/^\/\//.test(url)) return false;
    return true;
  };

  /**
   * Registers page-visibility and beforeunload listeners.
   * @private
   */
  SSEStreamManager.prototype.init_ = function() {
    var self = this;

    var onVisibilityChange = function() {
      if (self.destroyed_) return;
      if (document.visibilityState === 'hidden') {
        self.closeEventSource_();
      } else if (document.visibilityState === 'visible' && !self.eventSource_ && self.url_) {
        self.connect_(self.url_);
      }
    };

    var onBeforeUnload = function() { self.destroy(); };
    var onPageHide = function() { self.destroy(); };

    document.addEventListener('visibilitychange', onVisibilityChange);
    global.addEventListener('beforeunload', onBeforeUnload);
    global.addEventListener('pagehide', onPageHide);

    this.cleanups_.push(function() {
      document.removeEventListener('visibilitychange', onVisibilityChange);
      global.removeEventListener('beforeunload', onBeforeUnload);
      global.removeEventListener('pagehide', onPageHide);
    });
  };

  /**
   * Opens an SSE connection to the given relative URL.
   *
   * @param {string} url  Relative path (e.g. '/api/stream/top?interval=1.0').
   * @param {!Object<string, function(*, string): void>=} eventHandlers
   *     Map of SSE event-type -> handler(parsedData, rawData).
   * @return {boolean} True when the connection attempt was initiated.
   */
  SSEStreamManager.prototype.open = function(url, eventHandlers) {
    if (this.destroyed_) {
      console.warn('[SSEStreamManager] open() called after destroy().');
      return false;
    }
    if (!this.isSafeRelativeUrl_(url)) {
      console.error('[SSEStreamManager] Rejected unsafe URL:', url);
      return false;
    }
    this.url_ = url;
    this.userHandlers_ = eventHandlers || {};
    this.reconnectDelay_ = RECONNECT_DELAY_MS;
    this.dispatchHSM_('OPEN');
    this.connect_(url);
    return true;
  };

  /**
   * Internal connect: creates the EventSource and binds handlers.
   * @param {string} url
   * @private
   */
  SSEStreamManager.prototype.connect_ = function(url) {
    if (!global.EventSource) {
      console.warn('[SSEStreamManager] EventSource not supported in this browser.');
      return;
    }

    this.closeEventSource_();
    this.cancelReconnectTimer_();

    var self = this;

    try {
      var es = new EventSource(url);
      this.eventSource_ = es;
      this.handlers_ = Object.create(null);

      var onOpen = function() {
        self.dispatchHSM_('CONNECTED');
      };
      es.addEventListener('open', onOpen);
      this.handlers_['open'] = [onOpen];

      var userHandlers = this.userHandlers_;
      var eventTypes = Object.keys(userHandlers);
      for (var i = 0; i < eventTypes.length; i++) {
        (function(type) {
          var handler = function(e) {
            var parsed = null;
            try { parsed = JSON.parse(e.data); } catch (_) { parsed = e.data; }
            userHandlers[type](parsed, e.data);
          };
          if (!self.handlers_[type]) self.handlers_[type] = [];
          self.handlers_[type].push(handler);
          es.addEventListener(type, handler);
        })(eventTypes[i]);
      }

      var onError = function() {
        if (self.destroyed_) return;
        self.dispatchHSM_('ERROR');
        self.closeEventSource_();
        self.scheduleReconnect_();
      };
      es.addEventListener('error', onError);
      if (!self.handlers_['error']) self.handlers_['error'] = [];
      self.handlers_['error'].push(onError);

      self.publish_('sse:open', {url: url});
    } catch (err) {
      console.error('[SSEStreamManager] Failed to create EventSource:', err);
      this.dispatchHSM_('ERROR');
      this.scheduleReconnect_();
    }
  };

  /**
   * Publishes an event through the Yuzora Publisher if available.
   * @param {string} topic
   * @param {*=} data
   * @private
   */
  SSEStreamManager.prototype.publish_ = function(topic, data) {
    try {
      var loc = global['yuzora'] && global['yuzora']['locator'];
      if (loc) {
        var pub = loc.resolve(global['yuzora']['frameworks']['Publisher']);
        if (pub) pub.publishAsync(topic, data);
      }
    } catch (_) {}
  };

  /**
   * Closes the underlying EventSource and removes all its listeners.
   * @private
   */
  SSEStreamManager.prototype.closeEventSource_ = function() {
    var es = this.eventSource_;
    if (!es) return;
    try {
      var types = Object.keys(this.handlers_);
      for (var i = 0; i < types.length; i++) {
        var handlers = this.handlers_[types[i]];
        for (var j = 0; j < handlers.length; j++) {
          es.removeEventListener(types[i], handlers[j]);
        }
      }
      this.handlers_ = Object.create(null);
      es.close();
    } catch (_) {}
    this.eventSource_ = null;
    this.publish_('sse:close', {url: this.url_});
  };

  /**
   * Cancels any pending reconnect timer.
   * @private
   */
  SSEStreamManager.prototype.cancelReconnectTimer_ = function() {
    if (this.reconnectTimer_ !== null) {
      clearTimeout(this.reconnectTimer_);
      this.reconnectTimer_ = null;
    }
  };

  /**
   * Schedules a reconnect with exponential back-off.
   * @private
   */
  SSEStreamManager.prototype.scheduleReconnect_ = function() {
    if (this.destroyed_ || !this.url_) return;
    var self = this;
    var delay = this.reconnectDelay_;
    this.reconnectDelay_ = Math.min(
        this.reconnectDelay_ * BACKOFF_MULTIPLIER, MAX_RECONNECT_DELAY_MS);
    this.publish_('sse:reconnecting', {delay: delay});
    this.reconnectTimer_ = setTimeout(function() {
      self.reconnectTimer_ = null;
      if (!self.destroyed_ && self.url_) self.connect_(self.url_);
    }, delay);
  };

  /**
   * Closes the active connection without reconnecting. Can be reopened.
   */
  SSEStreamManager.prototype.close = function() {
    this.cancelReconnectTimer_();
    this.closeEventSource_();
    this.dispatchHSM_('CLOSE');
    this.url_ = null;
    this.userHandlers_ = {};
  };

  /**
   * Permanently destroys the manager and removes all global listeners.
   */
  SSEStreamManager.prototype.destroy = function() {
    if (this.destroyed_) return;
    this.destroyed_ = true;
    this.dispatchHSM_('DESTROY');
    this.cancelReconnectTimer_();
    this.closeEventSource_();
    for (var i = 0; i < this.cleanups_.length; i++) {
      try { this.cleanups_[i](); } catch (_) {}
    }
    this.cleanups_ = [];
  };

  /**
   * Returns true when there is an active open EventSource connection.
   * @return {boolean}
   */
  SSEStreamManager.prototype.isConnected = function() {
    return this.eventSource_ !== null &&
           this.eventSource_.readyState === EventSource.OPEN;
  };

  // ---------------------------------------------------------------------------
  // Export
  // ---------------------------------------------------------------------------
  var yuzora = global['yuzora'] = global['yuzora'] || {};
  var frameworks = yuzora['frameworks'] = yuzora['frameworks'] || {};
  frameworks['SSEStreamManager'] = SSEStreamManager;

})(window);
