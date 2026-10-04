(function() {
  'use strict';

/**
 * Safe URI decoder to prevent unhandled URIError exceptions on malformed input.
 * @param {string} str
 * @return {string}
 */
function safeDecode(str) {
  if (!str) return '';
  try {
    return decodeURIComponent(str.replace(/\+/g, ' '));
  } catch (e) {
    return str;
  }
}

/**
 * Route Segment Definition
 * @typedef {{
 *   type: string,
 *   value: (string|undefined),
 *   name: (string|undefined)
 * }}
 */
let RouteSegment;

/**
 * Compiled Route Definition
 * @typedef {{
 *   patternString: string,
 *   segments: !Array<!RouteSegment>,
 *   hasWildcard: boolean,
 *   callback: !Function
 * }}
 */
let CompiledRoute;

/**
 * Router manages the hash-based client-side routing with PEG-based path and query parsing.
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
         * @type {!Array<!CompiledRoute>}
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
     * Compiles a route pattern into structured PEG segments.
     * Supports literal segments, parameter segments (:id), and wildcard (*path).
     * @private
     * @param {string} pattern
     * @return {!Array<!RouteSegment>}
     */
    compilePattern_(pattern) {
        let clean = (pattern || '').trim();
        if (clean.startsWith('#')) clean = clean.slice(1);
        if (clean.startsWith('/')) clean = clean.slice(1);
        if (clean.endsWith('/')) clean = clean.slice(0, -1);

        if (!clean) {
            return [{ type: 'LITERAL', value: '', name: undefined }];
        }

        const rawSegs = clean.split('/');
        /** @type {!Array<!RouteSegment>} */
        const segments = [];

        for (let i = 0; i < rawSegs.length; i++) {
            const seg = rawSegs[i];
            if (seg.startsWith(':') && seg.length > 1) {
                segments.push({
                    type: 'PARAM',
                    name: seg.slice(1),
                    value: undefined
                });
            } else if (seg.startsWith('*')) {
                segments.push({
                    type: 'WILDCARD',
                    name: seg.length > 1 ? seg.slice(1) : 'wildcard',
                    value: undefined
                });
            } else {
                segments.push({
                    type: 'LITERAL',
                    value: seg,
                    name: undefined
                });
            }
        }
        return segments;
    }

    /**
     * Register a route path pattern.
     * Supports path patterns (:param, *wildcard) and query strings (?param=val).
     * @param {string} pattern
     * @param {!Function} callback
     * @override
     */
    // @ts-expect-error
    register(pattern, callback) {
        const segments = this.compilePattern_(pattern);
        const hasWildcard = segments.some(s => s.type === 'WILDCARD');
        this.routes.push({
            patternString: pattern,
            segments: segments,
            hasWildcard: hasWildcard,
            callback: callback
        });
    }

    /**
     * Matches input path segments against a compiled route.
     * @private
     * @param {!CompiledRoute} route
     * @param {!Array<string>} inputSegments
     * @return {{matched: boolean, params: !Object<string, string>}}
     */
    matchRoute_(route, inputSegments) {
        const segs = route.segments;
        /** @type {!Object<string, string>} */
        const pathParams = Object.create(null);

        // Empty root route case (e.g. "")
        if (segs.length === 1 && segs[0].type === 'LITERAL' && segs[0].value === '') {
            if (inputSegments.length === 0 || (inputSegments.length === 1 && inputSegments[0] === '')) {
                return { matched: true, params: pathParams };
            }
            return { matched: false, params: pathParams };
        }

        if (!route.hasWildcard) {
            if (segs.length !== inputSegments.length) {
                return { matched: false, params: pathParams };
            }
            for (let i = 0; i < segs.length; i++) {
                const seg = segs[i];
                const val = inputSegments[i];
                if (seg.type === 'LITERAL') {
                    if (seg.value !== val) return { matched: false, params: pathParams };
                } else if (seg.type === 'PARAM' && seg.name) {
                    pathParams[seg.name] = safeDecode(val);
                }
            }
            return { matched: true, params: pathParams };
        }

        // Wildcard route handling
        const wildcardIdx = segs.findIndex(s => s.type === 'WILDCARD');
        if (inputSegments.length < wildcardIdx) {
            return { matched: false, params: pathParams };
        }

        // Match segments before wildcard
        for (let i = 0; i < wildcardIdx; i++) {
            const seg = segs[i];
            const val = inputSegments[i];
            if (seg.type === 'LITERAL') {
                if (seg.value !== val) return { matched: false, params: pathParams };
            } else if (seg.type === 'PARAM' && seg.name) {
                pathParams[seg.name] = safeDecode(val);
            }
        }

        // Match wildcard remainder
        const wildcardSeg = segs[wildcardIdx];
        const remaining = inputSegments.slice(wildcardIdx).join('/');
        const wildcardName = wildcardSeg.name || 'wildcard';
        pathParams[wildcardName] = safeDecode(remaining);

        return { matched: true, params: pathParams };
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

        let raw = hash || '';
        if (raw.startsWith('#')) {
            raw = raw.slice(1);
        }
        if (raw.startsWith('/')) {
            raw = raw.slice(1);
        }

        const qIdx = raw.indexOf('?');
        let pathPart = qIdx !== -1 ? raw.slice(0, qIdx) : raw;
        const queryPart = qIdx !== -1 ? raw.slice(qIdx + 1) : '';

        if (pathPart.endsWith('/')) {
            pathPart = pathPart.slice(0, -1);
        }
        if (!pathPart) {
            pathPart = this.defaultRoute;
        }

        const inputSegments = pathPart ? pathPart.split('/').filter(Boolean) : [];

        for (let i = 0; i < this.routes.length; i++) {
            const route = this.routes[i];
            const matchResult = this.matchRoute_(route, inputSegments);
            if (matchResult.matched) {
                const queryParams = this.parseQuery_(queryPart);
                const pathParams = matchResult.params;

                /** @type {!Object<string, *>} */
                const mergedParams = Object.assign(Object.create(null), queryParams, pathParams);
                mergedParams['$pathParams'] = pathParams;
                mergedParams['$queryParams'] = queryParams;
                mergedParams['$path'] = pathPart;

                this.currentHash = hash;
                route.callback(mergedParams, {
                    pathParams: pathParams,
                    queryParams: queryParams,
                    path: pathPart
                });
                return true;
            }
        }
        return false;
    }

    /**
     * Parse query parameters with array aggregation and Prototype Pollution defense.
     * @private
     * @param {string} queryStr
     * @return {!Object<string, *>}
     */
    parseQuery_(queryStr) {
        /** @type {!Object<string, *>} */
        const params = Object.create(null);
        if (!queryStr) {
            return params;
        }
        let raw = queryStr;
        if (raw.startsWith('?')) {
            raw = raw.slice(1);
        }
        if (!raw) {
            return params;
        }

        const pairs = raw.split('&');
        for (let i = 0; i < pairs.length; i++) {
            const pairStr = pairs[i];
            if (!pairStr) continue;
            const eqIdx = pairStr.indexOf('=');
            let rawKey, rawVal;
            if (eqIdx !== -1) {
                rawKey = pairStr.slice(0, eqIdx);
                rawVal = pairStr.slice(eqIdx + 1);
            } else {
                rawKey = pairStr;
                rawVal = '';
            }

            const key = safeDecode(rawKey);
            const val = safeDecode(rawVal);

            // STRIDE Tampering Defense: Prevent Prototype Pollution
            if (key === '__proto__' || key === 'constructor' || key === 'prototype' || !key) {
                continue;
            }

            // HTTP Parameter Pollution (HPP) handling: Aggregate duplicates into an Array
            if (Object.prototype.hasOwnProperty.call(params, key)) {
                if (Array.isArray(params[key])) {
                    params[key].push(val);
                } else {
                    params[key] = [params[key], val];
                }
            } else {
                params[key] = val;
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

  // Export to global scope & Application frameworks namespace
  if (typeof window !== 'undefined') {
    window.Router = Router;

    window.Application = window.Application || {};
    window.Application.frameworks = window.Application.frameworks || {};
    window.Application.frameworks.Router = Router;
    window.App = window.Application;
    window.yuzora = window.Application;
  }

  // Export for Node.js / CommonJS testing
  if (typeof module !== 'undefined' && module.exports) {
    module.exports = {
      Router: Router
    };
  }
})();
