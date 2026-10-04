/**
 * Event Debouncing & Inactivity Control Infrastructure
 */
(function() {
  'use strict';

class Timing {
    /**
     * Creates a debounced function wrapper.
     * @param {function(...*): void} fn
     * @param {number} waitMs
     * @return {function(...*): void}
     */
    static debounce(fn, waitMs) {
        let timerId = null;
        return function(...args) {
            if (timerId !== null) {
                clearTimeout(timerId);
            }
            timerId = setTimeout(() => {
                timerId = null;
                fn(...args);
            }, waitMs);
        };
    }

    /**
     * Creates an inactivity auto-hide timer.
     * @param {function(): void} onInactivity
     * @param {number} timeoutMs
     * @return {{ trigger: function(): void, cancel: function(): void }}
     */
    static createInactivityTimer(onInactivity, timeoutMs) {
        let timerId = null;
        return {
            trigger: () => {
                if (timerId !== null) {
                    clearTimeout(timerId);
                }
                timerId = setTimeout(() => {
                    timerId = null;
                    onInactivity();
                }, timeoutMs);
            },
            cancel: () => {
                if (timerId !== null) {
                    clearTimeout(timerId);
                    timerId = null;
                }
            }
        };
    }

    /**
     * Delays clearing state to prevent viewport bounce during resize/reflow.
     * @param {function(): void} callback
     * @param {number} bufferMs
     */
    static createSettlementBuffer(callback, bufferMs) {
        setTimeout(callback, bufferMs);
    }
}

  // Export to global scope & Application frameworks namespace
  if (typeof window !== 'undefined') {
    window['Timing'] = Timing;
    window.Timing = Timing;
    Timing.prototype['debounce'] = Timing.debounce;
    Timing.prototype['createInactivityTimer'] = Timing.createInactivityTimer;
    Timing.prototype['createSettlementBuffer'] = Timing.createSettlementBuffer;

    window.Application = window.Application || {};
    window.Application.frameworks = window.Application.frameworks || {};
    window.Application.frameworks.Timing = Timing;
    window.App = window.Application;
    window.yuzora = window.Application;
  }

  // Export for Node.js / CommonJS testing
  if (typeof module !== 'undefined' && module.exports) {
    module.exports = {
      Timing: Timing
    };
  }
})();
