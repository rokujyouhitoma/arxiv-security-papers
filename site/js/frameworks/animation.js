/**
 * Event-Driven Animation & CSS Transition Infrastructure
 */
"use strict";

class AnimationUtils {
    /**
     * Waits for CSS transition completion on target element with fallback safety timer.
     * @param {!Element} element
     * @param {number} fallbackMs
     * @return {!Promise<void>}
     */
    static waitForTransition(element, fallbackMs) {
        return new Promise((resolve) => {
            let done = false;
            let timerId = null;

            const cleanup = () => {
                if (done) return;
                done = true;
                if (timerId !== null) {
                    clearTimeout(timerId);
                    timerId = null;
                }
                if (element && typeof element.removeEventListener === 'function') {
                    element.removeEventListener('transitionend', onTransitionEnd);
                    element.removeEventListener('animationend', onTransitionEnd);
                }
                resolve();
            };

            const onTransitionEnd = () => {
                cleanup();
            };

            if (element && typeof element.addEventListener === 'function') {
                element.addEventListener('transitionend', onTransitionEnd, { 'once': true });
                element.addEventListener('animationend', onTransitionEnd, { 'once': true });
            }

            timerId = setTimeout(() => {
                cleanup();
            }, fallbackMs);
        });
    }

    /**
     * Delays visual transition by specified duration.
     * @param {number} ms
     * @return {!Promise<void>}
     */
    static delay(ms) {
        return new Promise((resolve) => {
            setTimeout(resolve, ms);
        });
    }
}

window['AnimationUtils'] = AnimationUtils;
AnimationUtils.prototype['waitForTransition'] = AnimationUtils.waitForTransition;
AnimationUtils.prototype['delay'] = AnimationUtils.delay;
