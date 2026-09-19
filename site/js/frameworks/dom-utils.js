/**
 * DOM Rendering & Frame Synchronization Infrastructure
 */
"use strict";

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

window['DOMUtils'] = DOMUtils;
DOMUtils.prototype['afterReflow'] = DOMUtils.afterReflow;
DOMUtils.prototype['afterRender'] = DOMUtils.afterRender;
DOMUtils.prototype['nextFrame'] = DOMUtils.nextFrame;
