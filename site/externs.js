/**
 * @fileoverview Closure Compiler Externs Definition
 * @externs
 */

/**
 * @type {{
 *   initialize: function(!Object): void,
 *   run: function(!Object): void,
 *   render: function(string, string, function(string): void): void
 * }}
 */
var mermaid;

/**
 * @type {{
 *   compile: function(string): {html: string, mermaidElements: !Array<?>},
 *   renderMermaid: function(!Element): !Promise<void>
 * }}
 */
var MarkdownCompiler;

/** @type {function(string): string} */
var escapeHtml;

/** @type {function(string): !Promise<void>} */
var openPaperModal;

/* ==========================================================================
   Yuzora Frameworks Interfaces & Global Symbols
   ========================================================================== */

/** @interface */
function YuzoraEventInterface() {}
/** @type {string} */ YuzoraEventInterface.prototype.type;
/** @type {*} */ YuzoraEventInterface.prototype.detail;
/** @type {?Object} */ YuzoraEventInterface.prototype.target;

/** @interface */
function YuzoraEventTargetInterface() {}
/** @param {string} type @param {function(!YuzoraEventInterface): void} listener */
YuzoraEventTargetInterface.prototype.addEventListener = function(type, listener) {};
/** @param {string} type @param {function(!YuzoraEventInterface): void} listener */
YuzoraEventTargetInterface.prototype.removeEventListener = function(type, listener) {};
/** @param {!YuzoraEventInterface} event */
YuzoraEventTargetInterface.prototype.dispatchEvent = function(event) {};
/** @param {string} scopePrefix @return {!YuzoraEventTargetInterface} */
YuzoraEventTargetInterface.prototype.scoped = function(scopePrefix) {};

/** @interface */
function LocatorInterface() {}
/** @param {?} Class @return {?} */
LocatorInterface.prototype.resolve = function(Class) {};
/** @param {?} Class @return {?} */
LocatorInterface.prototype.locate = function(Class) {};
/** @param {?} Class @param {!Object} instance */
LocatorInterface.prototype.register = function(Class, instance) {};

/** @interface */
function PublisherInterface() {}
/** @param {string} topic @param {function(*): void} callback */
PublisherInterface.prototype.subscribe = function(topic, callback) {};
/** @param {string} topic @param {function(*): void} callback */
PublisherInterface.prototype.unsubscribe = function(topic, callback) {};
/** @param {string} topic @param {*=} data */
PublisherInterface.prototype.publish = function(topic, data) {};
/** @param {string} topic @param {*=} data */
PublisherInterface.prototype.publishAsync = function(topic, data) {};

/** @interface */
function RouterInterface() {}
/** @type {?string} */ RouterInterface.prototype.currentHash;
/** @param {string} pattern @param {!Function} callback */
RouterInterface.prototype.register = function(pattern, callback) {};
/** @param {string} hash @return {boolean} */
RouterInterface.prototype.resolve = function(hash) {};
RouterInterface.prototype.listen = function() {};
/** @param {string} hash */
RouterInterface.prototype.navigate = function(hash) {};

/** @interface */
function SceneInterface() {}
/** @param {*=} data */ SceneInterface.prototype.enter = function(data) {};
SceneInterface.prototype.exit = function() {};

/** @interface */
function SceneDirectorInterface() {}
/** @type {?string} */ SceneDirectorInterface.prototype.currentSceneName;
/** @type {boolean} */ SceneDirectorInterface.prototype.isTransitioning;
/** @param {string} sceneName @param {!SceneInterface} sceneInstance */
SceneDirectorInterface.prototype.register = function(sceneName, sceneInstance) {};
/** @param {string} sceneName @param {*=} data */
SceneDirectorInterface.prototype.transitionTo = function(sceneName, data) {};

/**
 * @interface
 */
function ApiClientInterface() {}
/**
 * @param {string} path
 * @param {!Object<string, *>=} options
 * @return {!Promise<*>}
 */
ApiClientInterface.prototype.request = function(path, options) {};
/**
 * @param {string} path
 * @param {?Object<string, *>=} params
 * @param {!Object<string, *>=} options
 * @return {!Promise<*>}
 */
ApiClientInterface.prototype.get = function(path, params, options) {};
/**
 * @param {string} path
 * @param {*=} body
 * @param {!Object<string, *>=} options
 * @return {!Promise<*>}
 */
ApiClientInterface.prototype.post = function(path, body, options) {};
/**
 * @param {string} path
 * @param {*=} body
 * @param {!Object<string, *>=} options
 * @return {!Promise<*>}
 */
ApiClientInterface.prototype.put = function(path, body, options) {};
/**
 * @param {string} path
 * @param {!Object<string, *>=} options
 * @return {!Promise<*>}
 */
ApiClientInterface.prototype.delete = function(path, options) {};

/**
 * @interface
 */
function StateStoreInterface() {}
/**
 * @param {string} key
 * @param {*=} defaultValue
 * @return {*}
 */
StateStoreInterface.prototype.get = function(key, defaultValue) {};
/**
 * @param {string} key
 * @param {*} value
 * @return {boolean}
 */
StateStoreInterface.prototype.set = function(key, value) {};
/**
 * @param {!Object<string, *>} partialState
 */
StateStoreInterface.prototype.update = function(partialState) {};
/**
 * @param {string} key
 * @param {function(*, *, string): void} callback
 * @return {function(): void}
 */
StateStoreInterface.prototype.subscribe = function(key, callback) {};
/**
 * @return {!Object<string, *>}
 */
StateStoreInterface.prototype.getState = function() {};
/**
 * @param {!Object<string, *>=} initialState
 */
StateStoreInterface.prototype.reset = function(initialState) {};

/**
 * @interface
 */
function SSEStreamManagerInterface() {}
/**
 * @param {string} url
 * @param {!Object<string, function(*, string): void>=} eventHandlers
 * @return {boolean}
 */
SSEStreamManagerInterface.prototype.open = function(url, eventHandlers) {};
/**
 */
SSEStreamManagerInterface.prototype.close = function() {};
/**
 */
SSEStreamManagerInterface.prototype.destroy = function() {};
/**
 * @return {boolean}
 */
SSEStreamManagerInterface.prototype.isConnected = function() {};

/**
 * @interface
 */
function ModalControllerInterface() {}
/**
 * @param {{focusFirstElement: (boolean|undefined)}=} opts
 */
ModalControllerInterface.prototype.open = function(opts) {};
/**
 * @return {!Promise<void>}
 */
ModalControllerInterface.prototype.close = function() {};
/**
 * @return {boolean}
 */
ModalControllerInterface.prototype.isOpen = function() {};
/**
 * @return {!Promise<void>}
 */
ModalControllerInterface.prototype.toggle = function() {};
/**
 */
ModalControllerInterface.prototype.destroy = function() {};

/**
 * @interface
 */
function RadixTrieInterface() {}
/**
 * @return {number}
 */
RadixTrieInterface.prototype.size = function() {};
/**
 * @param {string} key
 * @param {*} value
 */
RadixTrieInterface.prototype.insert = function(key, value) {};
/**
 * @param {string} key
 * @return {*}
 */
RadixTrieInterface.prototype.get = function(key) {};
/**
 * @param {string} key
 * @return {boolean}
 */
RadixTrieInterface.prototype.contains = function(key) {};
/**
 * @param {string} prefix
 * @param {number=} limit
 * @return {!Array<!Array>}
 */
RadixTrieInterface.prototype.searchPrefix = function(prefix, limit) {};
/**
 * @param {string} text
 * @return {?Array}
 */
RadixTrieInterface.prototype.longestPrefix = function(text) {};
/**
 * @param {string} key
 * @return {boolean}
 */
RadixTrieInterface.prototype.delete = function(key) {};
/**
 */
RadixTrieInterface.prototype.clear = function() {};
/**
 * @return {!Array<!Array>}
 */
/**
 * @return {!Array<!Array>}
 */
RadixTrieInterface.prototype.entries = function() {};

/**
 * @interface
 */
function QueryValidatorInterface() {}
/**
 * @param {string} queryString
 * @return {{
 *   valid: boolean,
 *   error: (?string),
 *   offset: (?number),
 *   line: (?number),
 *   col: (?number),
 *   expected: (!Array<string>),
 *   hint: (?string),
 *   ast: *
 * }}
 */
QueryValidatorInterface.prototype.validate = function(queryString) {};
/**
 * @param {string} queryString
 * @return {*}
 */
QueryValidatorInterface.prototype.parse = function(queryString) {};

/**
 * @interface
 */
function HierarchicalStateMachineInterface() {}
/**
 * @param {string} eventName
 * @param {Object<string, *>=} opt_payload
 * @return {boolean}
 */
HierarchicalStateMachineInterface.prototype.dispatch = function(eventName, opt_payload) {};
/**
 * @param {string} eventName
 * @param {Object<string, *>=} opt_payload
 * @return {boolean}
 */
HierarchicalStateMachineInterface.prototype.sendEvent = function(eventName, opt_payload) {};
/**
 * @param {string} stateNameOrPath
 * @return {boolean}
 */
HierarchicalStateMachineInterface.prototype.isInState = function(stateNameOrPath) {};
/**
 * @return {string}
 */
HierarchicalStateMachineInterface.prototype.getStatePath = function() {};
/**
 * @return {string}
 */
HierarchicalStateMachineInterface.prototype.getCurrentStatePath = function() {};
/**
 * @return {!Object}
 */
HierarchicalStateMachineInterface.prototype.getCurrentState = function() {};
/**
 * @param {string} targetPath
 * @param {string=} opt_reason
 * @return {boolean}
 */
HierarchicalStateMachineInterface.prototype.forceTransition = function(targetPath, opt_reason) {};
/**
 * @param {function(!Object, !Object, !Object): void} observer
 */
HierarchicalStateMachineInterface.prototype.addObserver = function(observer) {};
/**
 * @param {function(!Object, !Object, !Object): void} observer
 */
HierarchicalStateMachineInterface.prototype.removeObserver = function(observer) {};

/**
 * @interface
 */
function DisjointSetInterface() {}
/**
 * @param {*} x
 * @return {boolean}
 */
DisjointSetInterface.prototype.add = function(x) {};
/**
 * @param {*} x
 * @return {boolean}
 */
DisjointSetInterface.prototype.has = function(x) {};
/**
 * @return {number}
 */
DisjointSetInterface.prototype.size = function() {};
/**
 * @return {number}
 */
DisjointSetInterface.prototype.componentCount = function() {};
/**
 * @return {number}
 */
DisjointSetInterface.prototype.getComponentCount = function() {};
/**
 * @param {*} x
 * @return {*}
 */
DisjointSetInterface.prototype.find = function(x) {};
/**
 * @param {*} x
 * @param {*} y
 * @return {boolean}
 */
DisjointSetInterface.prototype.union = function(x, y) {};
/**
 * @param {*} x
 * @param {*} y
 * @return {boolean}
 */
DisjointSetInterface.prototype.connected = function(x, y) {};
/**
 * @param {*} x
 * @return {number}
 */
DisjointSetInterface.prototype.componentSize = function(x) {};
/**
 * @return {!Map<*, !Array<*>>}
 */
DisjointSetInterface.prototype.getComponents = function() {};
/**
 * @return {!Array<*>}
 */
DisjointSetInterface.prototype.getLargestComponent = function() {};
/**
 * @return {!Array<*>}
 */
DisjointSetInterface.prototype.getIsolates = function() {};
/**
 * @return {void}
 */
DisjointSetInterface.prototype.clear = function() {};

/**
 * @param {?Object} cache
 * @return {void}
 */
ApiClientInterface.prototype.setCache = function(cache) {};
/**
 * @return {?Object}
 */
ApiClientInterface.prototype.getCache = function() {};

/**
 * @interface
 */
function ARCCacheInterface() {}
/**
 * @return {number}
 */
ARCCacheInterface.prototype.size = function() {};
/**
 * @param {*} key
 * @return {boolean}
 */
ARCCacheInterface.prototype.has = function(key) {};
/**
 * @param {*} key
 * @param {*=} defaultValue
 * @return {*}
 */
ARCCacheInterface.prototype.get = function(key, defaultValue) {};
/**
 * @param {*} key
 * @param {*} value
 * @return {void}
 */
ARCCacheInterface.prototype.put = function(key, value) {};
/**
 * @param {*} key
 * @param {*} value
 * @return {void}
 */
ARCCacheInterface.prototype.set = function(key, value) {};
/**
 * @param {*} key
 * @return {boolean}
 */
ARCCacheInterface.prototype.delete = function(key) {};
/**
 * @return {void}
 */
ARCCacheInterface.prototype.clear = function() {};
/**
 * @return {!Array<*>}
 */
ARCCacheInterface.prototype.keys = function() {};
/**
 * @return {{
 *   hits: number,
 *   misses: number,
 *   hitRatio: number,
 *   p: number,
 *   capacity: number,
 *   t1Size: number,
 *   t2Size: number,
 *   b1Size: number,
 *   b2Size: number,
 *   totalEntries: number
 * }}
 */
ARCCacheInterface.prototype.getStats = function() {};

/**
 * @interface
 */
function GraphCanvasEngineInterface() {}
/**
 * @param {{nodes: !Array<!Object<string, *>>, edges: !Array<!Object<string, *>>}} data
 * @return {void}
 */
GraphCanvasEngineInterface.prototype.loadData = function(data) {};
/**
 * @param {number=} opt_dt
 * @return {void}
 */
GraphCanvasEngineInterface.prototype.stepPhysics = function(opt_dt) {};
/**
 * @return {void}
 */
GraphCanvasEngineInterface.prototype.render = function() {};
/**
 * @return {void}
 */
GraphCanvasEngineInterface.prototype.start = function() {};
/**
 * @return {void}
 */
GraphCanvasEngineInterface.prototype.stop = function() {};
/**
 * @param {number=} opt_factor
 * @return {void}
 */
GraphCanvasEngineInterface.prototype.zoomIn = function(opt_factor) {};
/**
 * @param {number=} opt_factor
 * @return {void}
 */
GraphCanvasEngineInterface.prototype.zoomOut = function(opt_factor) {};
/**
 * @param {number} px
 * @param {number} py
 * @param {number} factor
 * @return {void}
 */
GraphCanvasEngineInterface.prototype.zoomAt = function(px, py, factor) {};
/**
 * @return {void}
 */
GraphCanvasEngineInterface.prototype.resetView = function() {};
/**
 * @param {number} width
 * @param {number} height
 * @return {void}
 */
GraphCanvasEngineInterface.prototype.resize = function(width, height) {};
/**
 * @param {number} sx
 * @param {number} sy
 * @return {{x: number, y: number}}
 */
GraphCanvasEngineInterface.prototype.screenToWorld = function(sx, sy) {};
/**
 * @param {number} wx
 * @param {number} wy
 * @return {{x: number, y: number}}
 */
GraphCanvasEngineInterface.prototype.worldToScreen = function(wx, wy) {};
/**
 * @param {(!MouseEvent|!Event)} e
 * @return {{x: number, y: number}}
 */
GraphCanvasEngineInterface.prototype.getNormalizedCanvasMouse = function(e) {};
/**
 * @param {number} wx
 * @param {number} wy
 * @param {number=} opt_radius
 * @return {?Object<string, *>}
 */
GraphCanvasEngineInterface.prototype.findNodeAtWorld = function(wx, wy, opt_radius) {};
/**
 * @param {!Array<!Object<string, *>>} nodes
 * @param {!Array<!Object<string, *>>} edges
 * @return {!Array<!Object<string, *>>}
 */
GraphCanvasEngineInterface.prototype.computeLargestConnectedComponent = function(nodes, edges) {};
/**
 * @return {void}
 */
GraphCanvasEngineInterface.prototype.destroy = function() {};

/* ==========================================================================
   Application & Generic Global Namespaces (Issue 355)
   ========================================================================== */

/** @type {!Object<string, *>} */
var Application;
/** @type {!Object<string, *>} */
var App;
/** @type {!Object<string, *>} */
var yuzora;

/** @typedef {YuzoraEventInterface} */
var AppEventInterface;
/** @typedef {YuzoraEventTargetInterface} */
var AppEventTargetInterface;


