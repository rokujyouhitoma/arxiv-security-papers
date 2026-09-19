/**
 * Event Debouncing & Inactivity Control Infrastructure
 */
"use strict";

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

window['Timing'] = Timing;
Timing.prototype['debounce'] = Timing.debounce;
Timing.prototype['createInactivityTimer'] = Timing.createInactivityTimer;
Timing.prototype['createSettlementBuffer'] = Timing.createSettlementBuffer;
