/**
 * Generic Event Driven Architecture Module
 */
"use strict";

/**
 * AppEvent class.
 */
class AppEvent {
    /**
     * @param {string} type The event type.
     * @param {*} [detail] Optional event payload data.
     */
    constructor(type, detail = null) {
        /**
         * @public
         * @type {string}
         */
        this.type = type;
        /**
         * @public
         * @type {*}
         */
        this.detail = detail;
        /**
         * @public
         * @type {?Object}
         */
        this.target = null;
    }
}

/**
 * AppEventTarget class.
 * @implements {YuzoraEventTargetInterface}
 */
class AppEventTarget {
    constructor() {
        /**
         * @private
         * @type {!Object<string, !Array<function(!YuzoraEventInterface): void>>}
         */
        this.listeners_ = {};
    }

    /**
     * Add an event listener callback function.
     * @param {string} type The event type.
     * @param {function(!YuzoraEventInterface): void} listener The event listener function.
     * @override
     */
    // @ts-expect-error
    addEventListener(type, listener) {
        if (!this.listeners_[type]) {
            this.listeners_[type] = [];
        }
        this.listeners_[type].push(listener);
    }

    /**
     * Remove a registered event listener callback function.
     * @param {string} type The event type.
     * @param {function(!YuzoraEventInterface): void} listener The event listener function.
     * @override
     */
    // @ts-expect-error
    removeEventListener(type, listener) {
        if (!this.listeners_[type]) {
            return;
        }
        this.listeners_[type] = this.listeners_[type].filter(l => l !== listener);
    }

    /**
     * Dispatch an event to all registered listeners.
     * @param {!YuzoraEventInterface} event The event instance to dispatch.
     * @override
     */
    // @ts-expect-error
    dispatchEvent(event) {
        const type = event.type;
        if (window['__DEBUG_EVENT__']) {
            let detailStr = '';
            try {
                detailStr = JSON.stringify(event.detail);
            } catch (e) {
                detailStr = String(event.detail);
            }
            console.log(`[Event Audit] Dispatched event "${type}" (Payload: ${detailStr}) to ${this.listeners_[type] ? this.listeners_[type].length : 0} listener(s)`);
        }
        if (!this.listeners_[type]) {
            return;
        }
        event.target = this;
        // Copy listener array to prevent mutations during loop dispatch
        const targets = [...this.listeners_[type]];
        for (const listener of targets) {
            listener(event);
        }
    }

    /**
     * Creates a scoped event target wrapper.
     * @param {string} scopePrefix The scope prefix.
     * @return {!ScopedEventTarget}
     * @override
     */
    // @ts-expect-error
    scoped(scopePrefix) {
        return new ScopedEventTarget(this, scopePrefix);
    }
}

/**
 * ScopedEventTarget class.
 * @implements {YuzoraEventTargetInterface}
 */
class ScopedEventTarget {
    /**
     * @param {!AppEventTarget} parentTarget
     * @param {string} scopePrefix
     */
    constructor(parentTarget, scopePrefix) {
        /**
         * @private
         * @type {!AppEventTarget}
         */
        this.parent_ = parentTarget;
        /**
         * @private
         * @type {string}
         */
        this.scopePrefix_ = scopePrefix;
    }

    /**
     * Add a scoped event listener.
     * @param {string} type The event type.
     * @param {function(!YuzoraEventInterface): void} listener The event listener function.
     * @override
     */
    // @ts-expect-error
    addEventListener(type, listener) {
        const fullType = type.startsWith(this.scopePrefix_ + ':') ? type : `${this.scopePrefix_}:${type}`;
        this.parent_.addEventListener(fullType, listener);
    }

    /**
     * Remove a registered event listener callback function.
     * @param {string} type The event type.
     * @param {function(!YuzoraEventInterface): void} listener The event listener function.
     * @override
     */
    // @ts-expect-error
    removeEventListener(type, listener) {
        const fullType = type.startsWith(this.scopePrefix_ + ':') ? type : `${this.scopePrefix_}:${type}`;
        this.parent_.removeEventListener(fullType, listener);
    }

    /**
     * Dispatch an event to all registered listeners.
     * @param {!YuzoraEventInterface} event The event instance to dispatch.
     * @override
     */
    // @ts-expect-error
    dispatchEvent(event) {
        if (!event.type.startsWith(this.scopePrefix_ + ':')) {
            event.type = `${this.scopePrefix_}:${event.type}`;
        }
        this.parent_.dispatchEvent(event);
    }

    /**
     * Creates a nested scoped event target wrapper.
     * @param {string} scopePrefix The scope prefix.
     * @return {!ScopedEventTarget}
     * @override
     */
    // @ts-expect-error
    scoped(scopePrefix) {
        return new ScopedEventTarget(this.parent_, `${this.scopePrefix_}:${scopePrefix}`);
    }
}
