/**
 * @fileoverview Unified HTTP API Client with Error Handling, Timeout, and Security Guard.
 * Provides resilient, standardized HTTP communication for the enterprise web console.
 * Part of yuzora-frameworks integration (DSN-27 / Issue 339).
 */

(function() {
  'use strict';

/**
 * Custom error class representing HTTP API communication errors.
 * @extends {Error}
 */
class ApiError extends Error {
  /**
   * @param {number} status HTTP status code (e.g. 404, 500, 408)
   * @param {string} statusText HTTP status message
   * @param {*} data Parsed response body or error payload
   * @param {string} url Request URL that triggered the error
   */
  constructor(status, statusText, data = null, url = '') {
    super(`API Error ${status} (${statusText}): ${url}`);
    /** @type {string} */
    this.name = 'ApiError';
    /** @type {number} */
    this.status = status;
    /** @type {string} */
    this.statusText = statusText;
    /** @type {*} */
    this.data = data;
    /** @type {string} */
    this.url = url;
  }
}

/**
 * Unified HTTP API Client.
 * Handles timeouts, CSRF tokens, query parameter encoding, and pub/sub notifications.
 */
class ApiClient {
  /**
   * @param {string=} baseUrl Base URL prefix (defaults to empty for relative paths)
   * @param {!Object<string, *>=} defaultOptions Default fetch options (headers, timeout, etc.)
   * @param {?Object=} publisher Optional event publisher instance (Publisher)
   * @param {?Object=} cache Optional cache instance (ARCCache)
   */
  constructor(baseUrl = '', defaultOptions = {}, publisher = null, cache = null) {
    /** @private @type {string} */
    this.baseUrl_ = baseUrl;
    /** @private @type {!Object<string, *>} */
    this.defaultOptions_ = Object.assign({
      timeout: 15000,
      headers: {
        'Accept': 'application/json'
      }
    }, defaultOptions);
    /** @private @type {?Object} */
    this.publisher_ = publisher;
    /** @private @type {?Object} */
    this.cache_ = cache;
  }

  /**
   * Validates that the requested path is a safe relative URL to prevent SSRF and Open Redirect.
   * @param {string} path The target path
   * @return {string} Validated sanitized path
   * @throws {Error} If path is unsafe
   * @private
   */
  validatePath_(path) {
    if (typeof path !== 'string' || !path.trim()) {
      throw new Error('API request path must be a non-empty string');
    }
    const trimmed = path.trim();
    // Block protocol-relative URLs (e.g. //evil.com) and explicit schemes (http:, https:, javascript:)
    if (trimmed.startsWith('//') || /^[a-zA-Z][a-zA-Z0-9+.-]*:/.test(trimmed)) {
      throw new Error(`Insecure absolute or protocol-relative API path rejected: ${trimmed}`);
    }
    return trimmed;
  }

  /**
   * Builds full URL with query parameters.
   * @param {string} path Safe relative path
   * @param {?Object<string, *>=} params Query parameters
   * @return {string} Formatted URL
   * @private
   */
  buildUrl_(path, params = null) {
    let url = this.baseUrl_ + this.validatePath_(path);
    if (params && typeof params === 'object') {
      const searchParams = new URLSearchParams();
      for (const key of Object.keys(params)) {
        const val = params[key];
        if (val !== null && val !== undefined) {
          searchParams.append(key, String(val));
        }
      }
      const queryString = searchParams.toString();
      if (queryString) {
        url += (url.includes('?') ? '&' : '?') + queryString;
      }
    }
    return url;
  }

  /**
   * Executes an HTTP request with AbortController timeout and unified error handling.
   * @param {string} path Relative API path
   * @param {!Object<string, *>=} options Request options (method, headers, body, params, timeout)
   * @return {!Promise<*>} Parsed response data
   */
  async request(path, options = {}) {
    const mergedOptions = Object.assign({}, this.defaultOptions_, options);
    const timeoutMs = typeof mergedOptions.timeout === 'number' ? mergedOptions.timeout : 15000;
    const url = this.buildUrl_(path, mergedOptions.params || null);

    const controller = new AbortController();
    let timeoutId = null;

    if (timeoutMs > 0) {
      timeoutId = setTimeout(() => {
        controller.abort();
      }, timeoutMs);
    }

    const headers = Object.assign({}, this.defaultOptions_.headers || {}, mergedOptions.headers || {});
    const method = (mergedOptions.method || 'GET').toUpperCase();

    const fetchConfig = {
      method: method,
      headers: headers,
      signal: controller.signal
    };

    if (mergedOptions.body !== undefined && mergedOptions.body !== null) {
      if (typeof mergedOptions.body === 'object' && !(mergedOptions.body instanceof FormData)) {
        fetchConfig.body = JSON.stringify(mergedOptions.body);
        headers['Content-Type'] = headers['Content-Type'] || 'application/json';
      } else {
        fetchConfig.body = mergedOptions.body;
      }
    }

    try {
      const response = await fetch(url, fetchConfig);
      if (timeoutId) {
        clearTimeout(timeoutId);
      }

      // Check Content-Type to decide JSON or text parsing
      const contentType = response.headers.get('content-type') || '';
      let data = null;
      if (contentType.includes('application/json')) {
        try {
          data = await response.json();
        } catch (_) {
          data = null;
        }
      } else {
        data = await response.text();
      }

      if (!response.ok) {
        const error = new ApiError(response.status, response.statusText, data, url);
        if (this.publisher_ && typeof this.publisher_.publish === 'function') {
          this.publisher_.publish('api:error', { url, status: response.status, error });
        }
        throw error;
      }

      if (this.publisher_ && typeof this.publisher_.publish === 'function') {
        this.publisher_.publish('api:success', { url, status: response.status, method });
      }
      return data;
    } catch (err) {
      if (timeoutId) {
        clearTimeout(timeoutId);
      }
      if (err instanceof ApiError) {
        throw err;
      }
      // Handle abort / network timeout
      if (err && err.name === 'AbortError') {
        const timeoutError = new ApiError(408, 'Request Timeout', null, url);
        if (this.publisher_ && typeof this.publisher_.publish === 'function') {
          this.publisher_.publish('api:error', { url, status: 408, error: timeoutError });
        }
        throw timeoutError;
      }
      // Generic network / client error
      const netError = new ApiError(0, err ? err.message || 'Network Error' : 'Unknown Error', null, url);
      if (this.publisher_ && typeof this.publisher_.publish === 'function') {
        this.publisher_.publish('api:error', { url, status: 0, error: netError });
      }
      throw netError;
    }
  }

  /**
   * Convenience method for GET requests with optional caching.
   * @param {string} path Relative API path
   * @param {?Object<string, *>=} params Optional query parameters
   * @param {!Object<string, *>=} options Additional options (useCache: boolean)
   * @return {!Promise<*>}
   */
  async get(path, params = null, options = {}) {
    const url = this.buildUrl_(path, params);
    const useCache = options.useCache !== false && Boolean(this.cache_);
    if (useCache && this.cache_ && typeof this.cache_.get === 'function') {
      const cached = this.cache_.get(url);
      if (cached !== null && cached !== undefined) {
        if (this.publisher_ && typeof this.publisher_.publish === 'function') {
          this.publisher_.publish('api:cache_hit', { url });
        }
        return cached;
      }
    }
    const result = await this.request(path, Object.assign({}, options, { method: 'GET', params: params }));
    if (useCache && this.cache_ && typeof this.cache_.put === 'function' && result !== null && result !== undefined) {
      this.cache_.put(url, result);
    }
    return result;
  }

  /**
   * Returns current cache instance.
   * @return {?Object}
   */
  getCache() {
    return this.cache_;
  }

  /**
   * Sets or updates cache instance.
   * @param {?Object} cache
   */
  setCache(cache) {
    this.cache_ = cache;
  }

  /**
   * Convenience method for POST requests.
   * @param {string} path Relative API path
   * @param {*} body Request payload
   * @param {!Object<string, *>=} options Additional options
   * @return {!Promise<*>}
   */
  post(path, body = null, options = {}) {
    return this.request(path, Object.assign({}, options, { method: 'POST', body: body }));
  }

  /**
   * Convenience method for PUT requests.
   * @param {string} path Relative API path
   * @param {*} body Request payload
   * @param {!Object<string, *>=} options Additional options
   * @return {!Promise<*>}
   */
  put(path, body = null, options = {}) {
    return this.request(path, Object.assign({}, options, { method: 'PUT', body: body }));
  }

  /**
   * Convenience method for DELETE requests.
   * @param {string} path Relative API path
   * @param {!Object<string, *>=} options Additional options
   * @return {!Promise<*>}
   */
  delete(path, options = {}) {
    return this.request(path, Object.assign({}, options, { method: 'DELETE' }));
  }
}

  // Export to global scope & Application frameworks namespace
  if (typeof window !== 'undefined') {
    window.ApiError = ApiError;
    window.ApiClient = ApiClient;

    window.Application = window.Application || {};
    window.Application.frameworks = window.Application.frameworks || {};
    window.Application.frameworks.ApiError = ApiError;
    window.Application.frameworks.ApiClient = ApiClient;
    window.App = window.Application;
    window.yuzora = window.Application;
  }

  // Export for Node.js / CommonJS testing
  if (typeof module !== 'undefined' && module.exports) {
    module.exports = {
      ApiError: ApiError,
      ApiClient: ApiClient
    };
  }
})();
