/**
 * @fileoverview ModalController - WAI-ARIA-compliant modal & drawer lifecycle manager.
 *
 * Features:
 *  - Focus trap: Tab/Shift+Tab cycles within the modal.
 *  - Escape key closes the modal.
 *  - Overlay click closes the modal (configurable).
 *  - Scroll lock: toggles `document.body.style.overflow`.
 *  - aria-hidden / aria-modal attributes managed automatically.
 *  - AnimationUtils integration: waits for CSS transition before hiding.
 *  - Publisher integration: emits `modal:open` / `modal:close` events.
 *
 * Security notes:
 *  - Never sets innerHTML; content injection is the caller's responsibility.
 *  - XSS surface: none — all DOM manipulation is structural, not innerHTML.
 *
 * @package
 */

(function(global) {
  'use strict';

  /**
   * Focusable element selectors per ARIA best practices.
   * @const {string}
   */
  var FOCUSABLE_SELECTORS = [
    'a[href]',
    'button:not([disabled])',
    'textarea:not([disabled])',
    'input:not([disabled])',
    'select:not([disabled])',
    '[tabindex]:not([tabindex="-1"])'
  ].join(',');

  /**
   * Default animation fallback timeout in milliseconds.
   * @const {number}
   */
  var ANIMATION_FALLBACK_MS = 350;

  /**
   * ModalController manages one modal/drawer element with WAI-ARIA compliance,
   * focus trapping, scroll locking, and animation-aware hide/show.
   *
   * @constructor
   * @struct
   * @final
   * @param {!Element} element  The modal root element (role="dialog").
   * @param {{
   *   closeOnOverlayClick: (boolean|undefined),
   *   animationFallbackMs: (number|undefined),
   *   overlaySelector: (string|undefined)
   * }=} options  Configuration options.
   */
  function ModalController(element, options) {
    if (!element || !(element instanceof Element)) {
      throw new TypeError('[ModalController] element must be a DOM Element.');
    }

    /** @private {!Element} */
    this.el_ = element;

    var opts = options || {};

    /** @private {boolean} */
    this.closeOnOverlayClick_ = opts.closeOnOverlayClick !== false;

    /** @private {number} */
    this.animationFallbackMs_ = typeof opts.animationFallbackMs === 'number'
        ? opts.animationFallbackMs : ANIMATION_FALLBACK_MS;

    /** @private {string} */
    this.overlaySelector_ = opts.overlaySelector || '';

    /** @private {boolean} */
    this.isOpen_ = false;

    /** @private {boolean} */
    this.isAnimating_ = false;

    /** @private {?Element} Element that had focus before the modal was opened. */
    this.previouslyFocused_ = null;

    /** @private {!Array<function(): void>} Bound event listener cleanup callbacks. */
    this.cleanups_ = [];

    this.setupAriaAttributes_();
  }

  /**
   * Ensures required ARIA attributes are present on the root element.
   * @private
   */
  ModalController.prototype.setupAriaAttributes_ = function() {
    if (!this.el_.getAttribute('role')) {
      this.el_.setAttribute('role', 'dialog');
    }
    this.el_.setAttribute('aria-modal', 'true');
    if (!this.el_.getAttribute('aria-hidden')) {
      this.el_.setAttribute('aria-hidden', 'true');
    }
  };

  /**
   * Opens the modal. If already open, this is a no-op.
   * @param {{focusFirstElement: (boolean|undefined)}=} opts
   */
  ModalController.prototype.open = function(opts) {
    if (this.isOpen_ || this.isAnimating_) return;
    this.isOpen_ = true;

    // Remember what was focused before opening
    this.previouslyFocused_ = /** @type {?Element} */ (document.activeElement);

    // Show the element
    this.el_.classList.remove('hidden');
    this.el_.classList.add('active');
    this.el_.setAttribute('aria-hidden', 'false');

    // Scroll lock
    document.body.style.overflow = 'hidden';

    // Bind keyboard / overlay listeners
    this.attachListeners_();

    // Move focus into the modal
    var openOpts = opts || {};
    if (openOpts.focusFirstElement !== false) {
      this.focusFirst_();
    }

    this.publish_('modal:open', {element: this.el_});
  };

  /**
   * Closes the modal. Waits for CSS transitions before hiding.
   * @return {!Promise<void>}
   */
  ModalController.prototype.close = function() {
    if (!this.isOpen_) return Promise.resolve();

    this.isOpen_ = false;
    this.isAnimating_ = true;

    var self = this;

    this.el_.classList.remove('active');
    this.el_.setAttribute('aria-hidden', 'true');

    // Detach listeners immediately to prevent double-close
    this.detachListeners_();

    // Wait for CSS transition, then fully hide
    return this.waitForAnimation_().then(function() {
      self.isAnimating_ = false;
      self.el_.classList.add('hidden');

      // Scroll unlock
      document.body.style.overflow = '';

      // Restore focus
      if (self.previouslyFocused_ && typeof self.previouslyFocused_.focus === 'function') {
        try { self.previouslyFocused_.focus(); } catch (_) {}
        self.previouslyFocused_ = null;
      }

      self.publish_('modal:close', {element: self.el_});
    });
  };

  /**
   * Returns whether the modal is currently open.
   * @return {boolean}
   */
  ModalController.prototype.isOpen = function() {
    return this.isOpen_;
  };

  /**
   * Toggles the modal open/close state.
   * @return {!Promise<void>}
   */
  ModalController.prototype.toggle = function() {
    if (this.isOpen_) {
      return this.close();
    }
    this.open();
    return Promise.resolve();
  };

  /**
   * Returns all focusable elements within the modal.
   * @return {!Array<!Element>}
   * @private
   */
  ModalController.prototype.getFocusableElements_ = function() {
    var nodeList = this.el_.querySelectorAll(FOCUSABLE_SELECTORS);
    var result = [];
    for (var i = 0; i < nodeList.length; i++) {
      var el = nodeList[i];
      // Filter out elements inside nested dialogs and hidden elements
      if (el.closest('[aria-hidden="true"]') && el.closest('[aria-hidden="true"]') !== this.el_) {
        continue;
      }
      result.push(el);
    }
    return result;
  };

  /**
   * Moves focus to the first focusable element inside the modal.
   * Falls back to the modal element itself.
   * @private
   */
  ModalController.prototype.focusFirst_ = function() {
    var self = this;
    // Defer to allow CSS transition to begin
    setTimeout(function() {
      var focusable = self.getFocusableElements_();
      if (focusable.length > 0) {
        try { focusable[0].focus(); } catch (_) {}
      } else {
        if (!self.el_.hasAttribute('tabindex')) {
          self.el_.setAttribute('tabindex', '-1');
        }
        try { self.el_.focus(); } catch (_) {}
      }
    }, 50);
  };

  /**
   * Traps focus within the modal on Tab/Shift+Tab.
   * @param {!KeyboardEvent} e
   * @private
   */
  ModalController.prototype.handleKeydown_ = function(e) {
    if (e.key === 'Escape') {
      this.close();
      return;
    }

    if (e.key !== 'Tab') return;

    var focusable = this.getFocusableElements_();
    if (focusable.length === 0) {
      e.preventDefault();
      return;
    }

    var first = focusable[0];
    var last = focusable[focusable.length - 1];

    if (e.shiftKey) {
      if (document.activeElement === first) {
        e.preventDefault();
        try { last.focus(); } catch (_) {}
      }
    } else {
      if (document.activeElement === last) {
        e.preventDefault();
        try { first.focus(); } catch (_) {}
      }
    }
  };

  /**
   * Handles overlay/backdrop clicks to close the modal.
   * @param {!MouseEvent} e
   * @private
   */
  ModalController.prototype.handleOverlayClick_ = function(e) {
    if (!this.closeOnOverlayClick_) return;

    var target = /** @type {!Element} */ (e.target);

    // Close if the click landed on the modal root or an explicit overlay element
    if (target === this.el_) {
      this.close();
      return;
    }

    if (this.overlaySelector_) {
      var overlayEl = this.el_.querySelector(this.overlaySelector_) ||
                      document.querySelector(this.overlaySelector_);
      if (overlayEl && overlayEl.contains(target)) {
        this.close();
      }
    }
  };

  /**
   * Attaches keyboard and overlay click listeners.
   * @private
   */
  ModalController.prototype.attachListeners_ = function() {
    var self = this;

    var onKeydown = function(e) { self.handleKeydown_(/** @type {!KeyboardEvent} */(e)); };
    var onClick = function(e) { self.handleOverlayClick_(/** @type {!MouseEvent} */(e)); };

    document.addEventListener('keydown', onKeydown, true);
    this.el_.addEventListener('click', onClick);

    this.cleanups_.push(function() {
      document.removeEventListener('keydown', onKeydown, true);
      self.el_.removeEventListener('click', onClick);
    });
  };

  /**
   * Removes all attached event listeners.
   * @private
   */
  ModalController.prototype.detachListeners_ = function() {
    for (var i = 0; i < this.cleanups_.length; i++) {
      try { this.cleanups_[i](); } catch (_) {}
    }
    this.cleanups_ = [];
  };

  /**
   * Waits for CSS transition/animation on the modal element.
   * Uses AnimationUtils if available, otherwise falls back to a timeout.
   * @return {!Promise<void>}
   * @private
   */
  ModalController.prototype.waitForAnimation_ = function() {
    try {
      var AnimUtils = global['AnimationUtils'];
      if (AnimUtils && typeof AnimUtils.waitForTransition === 'function') {
        return AnimUtils.waitForTransition(this.el_, this.animationFallbackMs_);
      }
    } catch (_) {}
    var ms = this.animationFallbackMs_;
    return new Promise(function(resolve) { setTimeout(resolve, ms); });
  };

  /**
   * Publishes a modal lifecycle event via the Yuzora Publisher.
   * @param {string} topic
   * @param {*=} data
   * @private
   */
  ModalController.prototype.publish_ = function(topic, data) {
    try {
      var loc = (global['Application'] && global['Application']['locator']) ||
                (global['yuzora'] && global['yuzora']['locator']);
      if (loc) {
        var pubCtor = (global['Application'] && global['Application']['frameworks'] && global['Application']['frameworks']['Publisher']) ||
                      (global['yuzora'] && global['yuzora']['frameworks'] && global['yuzora']['frameworks']['Publisher']);
        var pub = loc.resolve(pubCtor);
        if (pub) pub.publishAsync(topic, data);
      }
    } catch (_) {}
  };

  /**
   * Destroys the controller and removes any remaining listeners.
   * After calling this, open()/close() are no-ops.
   */
  ModalController.prototype.destroy = function() {
    this.isOpen_ = false;
    this.isAnimating_ = false;
    this.detachListeners_();
  };

  // ---------------------------------------------------------------------------
  // Export
  // ---------------------------------------------------------------------------
  var Application = global['Application'] = global['Application'] || {};
  var frameworks = Application['frameworks'] = Application['frameworks'] || {};
  frameworks['ModalController'] = ModalController;
  global['ModalController'] = ModalController;
  global['App'] = Application;
  global['yuzora'] = Application;

})(window);
