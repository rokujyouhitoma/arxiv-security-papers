/**
 * DOM Rendering & Frame Synchronization Infrastructure
 */
(function() {
  'use strict';

class DOMUtils {
    /**
     * Executes callback after reflow and DOM rendering settle on the next frame.
     * @param {function(): void} callback
     */
    static afterReflow(callback) {
        if (typeof window !== 'undefined' && window.requestAnimationFrame) {
            window.requestAnimationFrame(() => {
                setTimeout(callback, 0);
            });
        } else {
            setTimeout(callback, 0);
        }
    }

    /**
     * Executes callback after initial rendering completes.
     * @param {function(): (void|!Promise<void>)} callback
     */
    static afterRender(callback) {
        setTimeout(async () => {
            await callback();
        }, 0);
    }

    /**
     * Scheduling helper for 60fps frame updates.
     * @param {function(): void} callback
     */
    static nextFrame(callback) {
        if (typeof window !== 'undefined' && window.requestAnimationFrame) {
            window.requestAnimationFrame(callback);
        } else {
            setTimeout(callback, 16);
        }
    }
}

  // Export to global scope & Application frameworks namespace
  if (typeof window !== 'undefined') {
    window['DOMUtils'] = DOMUtils;
    window.DOMUtils = DOMUtils;
    DOMUtils.prototype['afterReflow'] = DOMUtils.afterReflow;
    DOMUtils.prototype['afterRender'] = DOMUtils.afterRender;
    DOMUtils.prototype['nextFrame'] = DOMUtils.nextFrame;

    window.Application = window.Application || {};
    window.Application.frameworks = window.Application.frameworks || {};
    window.Application.frameworks.DOMUtils = DOMUtils;
    window.App = window.Application;
    window.yuzora = window.Application;
  }

  // Export for Node.js / CommonJS testing
  if (typeof module !== 'undefined' && module.exports) {
    module.exports = {
      DOMUtils: DOMUtils
    };
  }
})();
