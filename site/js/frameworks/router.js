/**
 * Generic Hash Routing Framework
 */
"use strict";

/**
 * Router manages the hash-based client-side routing
 * @implements {RouterInterface}
 */
class Router {
    /**
     * @param {string=} defaultRoute The fallback route when no hash path is present.
     */
    constructor(defaultRoute = "welcome") {
        /**
         * @private
         * @type {string}
         */
        this.defaultRoute = defaultRoute;

        /**
         * Registered Routes
         * @private
         * @type {!Array<{pattern: !RegExp, callback: !Function}>}
         */
        this.routes = [];

        /**
         * Current Active Hash Value
         * @public
         * @type {?string}
         */
        this.currentHash = null;
    }

    /**
     * Register a route path pattern.
     * Supports path patterns and parses query query strings (?param=val).
     * @param {string} pattern
     * @param {!Function} callback
     * @override
     */
    // @ts-expect-error
    register(pattern, callback) {
        // Convert the pattern into a RegExp matching starting hash path.
        // Optional leading '/' is allowed.
        const regexSource = "^\\/?" + pattern.replace(/^\//, "").replace(/\//g, "\\/") + "(?:\\?(.*))?$";
        const regex = new RegExp(regexSource);
        this.routes.push({ pattern: regex, callback });
    }

    /**
     * Resolve path and invoke callback.
     * @param {string} hash
     * @return {boolean} True if matched and executed.
     * @override
     */
    // @ts-expect-error
    resolve(hash) {
        if (this.currentHash !== null && hash === this.currentHash) {
            return false;
        }

        let path = hash;
        if (path.startsWith("#")) {
            path = path.slice(1);
        }
        if (path.startsWith("/")) {
            path = path.slice(1);
        }
        if (!path) {
            path = this.defaultRoute;
        }

        for (let i = 0; i < this.routes.length; i++) {
            const route = this.routes[i];
            const match = path.match(route.pattern);
            if (match) {
                const queryStr = match[1] || "";
                const params = this.parseQuery_(queryStr);
                
                this.currentHash = hash;
                route.callback(params);
                return true;
            }
        }
        return false;
    }

    /**
     * Parse query parameters.
     * @private
     * @param {string} queryStr
     * @return {!Object<string, string>}
     */
    parseQuery_(queryStr) {
        /** @type {!Object<string, string>} */
        const params = {};
        if (!queryStr) {
            return params;
        }
        const pairs = queryStr.split("&");
        for (let i = 0; i < pairs.length; i++) {
            const pair = pairs[i].split("=");
            if (pair[0]) {
                params[decodeURIComponent(pair[0])] = decodeURIComponent(pair[1] || "");
            }
        }
        return params;
    }

    /**
     * Start listening to hashchange events.
     * @override
     */
    // @ts-expect-error
    listen() {
        window.addEventListener("hashchange", () => {
            this.resolve(window.location.hash);
        });
        // Resolve initial hash route or redirect to default
        const initialHash = window.location.hash;
        if (!initialHash || initialHash === "#" || initialHash === "#/") {
            this.navigate("#/" + this.defaultRoute);
        } else {
            this.resolve(initialHash);
        }
    }

    /**
     * Force navigate to a hash path.
     * @param {string} hash
     * @override
     */
    // @ts-expect-error
    navigate(hash) {
        window.location.hash = hash;
        this.resolve(hash);
    }
}
