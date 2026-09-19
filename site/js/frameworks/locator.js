/**
 * Generic Service Locator Module
 */
"use strict";

/**
 * Service Locator manages class instance registrations and dependencies.
 * @implements {LocatorInterface}
 */
class Locator {
    /**
     * @param {Map<?, Object>} [container]
     */
    constructor(container) {
        /**
         * @private
         * @type {Map<?, Object>}
         */
        this.container = container || new Map();
    }

    /**
     * Register an instance for a Class constructor.
     * @param {?} Class
     * @param {!Object} instance
     * @override
     */
    // @ts-expect-error
    register(Class, instance) {
        this.container.set(Class, instance);
    }

    /**
     * Resolve and return the registered instance for a Class.
     * Throws an error if the class is not registered.
     * @param {?} Class
     * @return {!Object}
     * @override
     */
    // @ts-expect-error
    resolve(Class) {
        if (!this.container.has(Class)) {
            throw new Error(`Class ${Class.name || Class} is not registered in Locator.`);
        }
        const instance = this.container.get(Class);
        if (!instance) {
            throw new Error(`Class ${Class.name || Class} instance is null or undefined.`);
        }
        return instance;
    }

    /**
     * Reference-style locating: resolves or auto-instantiates if not registered.
     * Throws an error if auto-instantiation fails.
     * @param {?} Class
     * @return {!Object}
     * @override
     */
    // @ts-expect-error
    locate(Class) {
        if (!this.container.has(Class)) {
            try {
                this.container.set(Class, new (/** @type {function(new:?)} */ (Class))());
            } catch (e) {
                throw new Error(`Failed to auto-instantiate Class ${Class.name || Class} in Locator: ${e instanceof Error ? e.message : String(e)}`);
            }
        }
        const instance = this.container.get(Class);
        if (!instance) {
            throw new Error(`Class ${Class.name || Class} instance is null or undefined.`);
        }
        return instance;
    }
}
