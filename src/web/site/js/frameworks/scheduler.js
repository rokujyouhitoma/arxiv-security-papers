/**
 * Task Scheduler & Time-Slicing Infrastructure
 */
(function() {
  'use strict';

class TaskScheduler {
    /**
     * Yields control back to the browser main thread if frame budget (10ms) is exceeded or user input is pending.
     * @param {number=} budgetMs
     * @param {number=} lastYieldTime
     * @return {!Promise<number>}
     */
    // eslint-disable-next-line complexity
    static async yieldToMainThread(budgetMs = 10, lastYieldTime = 0) {
        const now = performance.now();
        const nav = typeof navigator !== 'undefined' ? navigator : null;
        const isInputPending = (nav && nav['scheduling'] && typeof nav['scheduling']['isInputPending'] === 'function')
            ? nav['scheduling']['isInputPending']()
            : false;

        if (now - lastYieldTime >= budgetMs || isInputPending) {
            if (typeof window !== 'undefined' && window['scheduler'] && typeof window['scheduler']['yield'] === 'function') {
                await window['scheduler']['yield']();
            } else {
                await new Promise(resolve => setTimeout(resolve, 0));
            }
            return performance.now();
        }
        return lastYieldTime;
    }

    /**
     * Fallback for running idle background tasks.
     * @param {function(): void} callback
     */
    static requestIdle(callback) {
        if (typeof window !== 'undefined' && window['requestIdleCallback']) {
            window['requestIdleCallback'](callback);
        } else {
            setTimeout(callback, 0);
        }
    }

    /**
     * Delays execution by specified milliseconds.
     * @param {number} ms
     * @return {!Promise<void>}
     */
    static delay(ms) {
        return new Promise(resolve => setTimeout(resolve, ms));
    }
}

  // Export to global scope & Application frameworks namespace
  if (typeof window !== 'undefined') {
    window['TaskScheduler'] = TaskScheduler;
    window['Scheduler'] = /** @type {?} */ (TaskScheduler);
    window.TaskScheduler = TaskScheduler;
    window.Scheduler = TaskScheduler;
    TaskScheduler.prototype['yieldToMainThread'] = TaskScheduler.yieldToMainThread;
    TaskScheduler.prototype['requestIdle'] = TaskScheduler.requestIdle;
    TaskScheduler.prototype['delay'] = TaskScheduler.delay;

    window.Application = window.Application || {};
    window.Application.frameworks = window.Application.frameworks || {};
    window.Application.frameworks.TaskScheduler = TaskScheduler;
    window.Application.frameworks.Scheduler = TaskScheduler;
    window.App = window.Application;
    window.yuzora = window.Application;
  }

  // Export for Node.js / CommonJS testing
  if (typeof module !== 'undefined' && module.exports) {
    module.exports = {
      TaskScheduler: TaskScheduler,
      Scheduler: TaskScheduler
    };
  }
})();
