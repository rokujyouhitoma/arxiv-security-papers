/**
 * @fileoverview Hierarchical State Machine (HSM / Statecharts) for Web Frontend.
 * Ported from src/core/hsm/ (engine.py, tree.py, contracts.py).
 * Provides deterministic LCCA transitions, event bubbling, entry/exit passes,
 * guard evaluation, and fail-secure recovery.
 *
 * Zero external dependencies: Pure ES2022 / Closure Compiler compliant.
 */

(function() {
  'use strict';

  /**
   * Immutable event context passing payload across transitions.
   * @constructor
   * @param {string} eventName
   * @param {Object<string, *>=} opt_payload
   * @param {number=} opt_timestamp
   */
  function EventContext(eventName, opt_payload, opt_timestamp) {
    /** @type {string} */
    this.eventName = eventName;
    /** @type {string} */
    this.event_name = eventName;
    /** @type {!Object<string, *>} */
    this.payload = opt_payload || {};
    /** @type {number} */
    this.timestamp = typeof opt_timestamp === 'number' ? opt_timestamp : Date.now();
  }

  /**
   * Transition rule encapsulating source, event, target, guard, and action.
   * @constructor
   * @param {string} sourceName
   * @param {string} eventName
   * @param {string} targetName
   * @param {?function(!EventContext): boolean=} opt_guard
   * @param {?function(!EventContext): void=} opt_action
   */
  function TransitionRule(sourceName, eventName, targetName, opt_guard, opt_action) {
    /** @type {string} */
    this.sourceName = sourceName;
    /** @type {string} */
    this.eventName = eventName;
    /** @type {string} */
    this.targetName = targetName;
    /** @type {?function(!EventContext): boolean} */
    this.guard = opt_guard || null;
    /** @type {?function(!EventContext): void} */
    this.action = opt_action || null;
  }

  /**
   * Represents a composite or leaf node in the state hierarchy.
   * @constructor
   * @param {string} name
   * @param {?StateNode=} opt_parent
   * @param {?string=} opt_initialChild
   * @param {?function(!EventContext): void=} opt_onEntry
   * @param {?function(!EventContext): void=} opt_onExit
   */
  function StateNode(name, opt_parent, opt_initialChild, opt_onEntry, opt_onExit) {
    /** @type {string} */
    this.name = name;
    /** @type {?StateNode} */
    this.parent = opt_parent || null;
    /** @type {?string} */
    this.initialChild = opt_initialChild || null;
    /** @type {?function(!EventContext): void} */
    this.onEntry = opt_onEntry || null;
    /** @type {?function(!EventContext): void} */
    this.onExit = opt_onExit || null;
    /** @type {!Object<string, !StateNode>} */
    this.children = {};
    /** @type {!Object<string, !Array<!TransitionRule>>} */
    this.transitions = {};
  }

  /**
   * @param {!StateNode} child
   * @return {!StateNode}
   */
  StateNode.prototype.addChild = function(child) {
    child.parent = this;
    this.children[child.name] = child;
    return child;
  };

  /**
   * @param {!TransitionRule} rule
   * @return {!StateNode}
   */
  StateNode.prototype.addTransition = function(rule) {
    if (!this.transitions[rule.eventName]) {
      this.transitions[rule.eventName] = [];
    }
    this.transitions[rule.eventName].push(rule);
    return this;
  };

  /**
   * @return {boolean}
   */
  StateNode.prototype.isLeaf = function() {
    return Object.keys(this.children).length === 0;
  };

  /**
   * @return {boolean}
   */
  StateNode.prototype.isRoot = function() {
    return this.parent === null;
  };

  /**
   * @return {number}
   */
  StateNode.prototype.getDepth = function() {
    var depth = 0;
    var curr = this.parent;
    while (curr !== null) {
      depth++;
      curr = curr.parent;
    }
    return depth;
  };

  /**
   * @return {string}
   */
  StateNode.prototype.getPath = function() {
    if (this.parent === null) {
      return this.name === 'ROOT' ? '' : this.name;
    }
    var parentPath = this.parent.getPath();
    if (!parentPath) {
      return this.name;
    }
    return parentPath + '.' + this.name;
  };

  /**
   * @return {!Array<!StateNode>}
   */
  StateNode.prototype.getAncestors = function() {
    var ancestors = [];
    var curr = this.parent;
    while (curr !== null) {
      ancestors.push(curr);
      curr = curr.parent;
    }
    return ancestors;
  };

  /**
   * Finds Lowest Common Composite Ancestor (LCCA) between source and target.
   * @param {!StateNode} source
   * @param {!StateNode} target
   * @return {?StateNode}
   */
  function findLCCA(source, target) {
    if (source === target) {
      return source.parent;
    }
    var sourceAncestors = [source].concat(source.getAncestors());
    var sourceSet = new Set(sourceAncestors);

    if (sourceSet.has(target)) {
      return target.parent;
    }

    var curr = target.parent;
    while (curr !== null) {
      if (sourceSet.has(curr)) {
        return curr;
      }
      curr = curr.parent;
    }
    return null;
  }

  /**
   * Resolves exit path from source up to (excluding) LCCA.
   * @param {!StateNode} source
   * @param {?StateNode} lcca
   * @return {!Array<!StateNode>}
   */
  function resolveExitPath(source, lcca) {
    var exitPath = [];
    var curr = source;
    while (curr !== null && curr !== lcca) {
      exitPath.push(curr);
      curr = curr.parent;
    }
    return exitPath;
  }

  /**
   * Resolves entry path from (excluding) LCCA down to target.
   * @param {!StateNode} target
   * @param {?StateNode} lcca
   * @return {!Array<!StateNode>}
   */
  function resolveEntryPath(target, lcca) {
    var entryPath = [];
    var curr = target;
    while (curr !== null && curr !== lcca) {
      entryPath.push(curr);
      curr = curr.parent;
    }
    entryPath.reverse();
    return entryPath;
  }

  /**
   * Descends initialChild links to find active leaf node.
   * @param {!StateNode} composite
   * @return {{leaf: !StateNode, descendants: !Array<!StateNode>}}
   */
  function resolveInitialLeaf(composite) {
    var descendants = [];
    var curr = composite;
    while (curr.initialChild && curr.children[curr.initialChild]) {
      curr = curr.children[curr.initialChild];
      descendants.push(curr);
    }
    return {leaf: curr, descendants: descendants};
  }

  /**
   * @param {!StateNode} root
   * @param {string} path
   * @return {?StateNode}
   */
  function findNodeByPath(root, path) {
    if (!path) {
      return root;
    }
    var segments = path.split('.').map(function(s) { return s.trim(); }).filter(function(s) { return !!s; });
    if (segments.length > 0 && root.name === segments[0]) {
      segments = segments.slice(1);
    }
    var curr = root;
    for (var i = 0; i < segments.length; i++) {
      var seg = segments[i];
      if (!curr.children[seg]) {
        return null;
      }
      curr = curr.children[seg];
    }
    return curr;
  }

  /**
   * Validates tree structure (acyclic, valid initial children).
   * @param {!StateNode} root
   */
  function validateTree(root) {
    var visited = new Set();
    function dfs(node) {
      if (visited.has(node)) {
        throw new Error('Cyclic graph detected in HSM StateNode tree: ' + node.name);
      }
      visited.add(node);
      if (node.initialChild && !node.children[node.initialChild]) {
        throw new Error('Initial child "' + node.initialChild + '" not found in children of ' + node.name);
      }
      var childNames = Object.keys(node.children);
      for (var i = 0; i < childNames.length; i++) {
        dfs(node.children[childNames[i]]);
      }
    }
    dfs(root);
  }

  /**
   * Hierarchical State Machine (HSM / Statecharts) execution engine.
   * @constructor
   * @param {!StateNode} root
   * @param {?StateNode=} opt_initialState
   * @param {?string=} opt_failSecureTarget
   */
  function HierarchicalStateMachine(root, opt_initialState, opt_failSecureTarget) {
    validateTree(root);
    /** @type {!StateNode} */
    this.root = root;
    /** @type {?string} */
    this.failSecureTarget = opt_failSecureTarget || null;
    /** @type {!Array<function(!StateNode, !StateNode, !EventContext): void>} */
    this.observers_ = [];

    if (opt_initialState) {
      /** @type {!StateNode} */
      this.currentState = opt_initialState;
    } else {
      var res = resolveInitialLeaf(root);
      this.currentState = res.leaf;
      this.enterInitialNodes_(res.descendants);
    }
  }

  /**
   * @private
   * @param {!Array<!StateNode>} nodes
   */
  HierarchicalStateMachine.prototype.enterInitialNodes_ = function(nodes) {
    var initCtx = new EventContext('__INIT__');
    for (var i = 0; i < nodes.length; i++) {
      if (nodes[i].onEntry) {
        nodes[i].onEntry(initCtx);
      }
    }
  };

  /**
   * Registers a transition observer.
   * @param {function(!StateNode, !StateNode, !EventContext): void} observer
   */
  HierarchicalStateMachine.prototype.addObserver = function(observer) {
    this.observers_.push(observer);
  };

  /**
   * Unregisters a transition observer.
   * @param {function(!StateNode, !StateNode, !EventContext): void} observer
   */
  HierarchicalStateMachine.prototype.removeObserver = function(observer) {
    this.observers_ = this.observers_.filter(function(o) { return o !== observer; });
  };

  /**
   * Evaluates whether current active state matches or is descendant of target.
   * @param {string} stateNameOrPath
   * @return {boolean}
   */
  HierarchicalStateMachine.prototype.isInState = function(stateNameOrPath) {
    if (this.matchesNameOrPath_(this.currentState, stateNameOrPath)) {
      return true;
    }
    var ancestors = this.currentState.getAncestors();
    for (var i = 0; i < ancestors.length; i++) {
      if (this.matchesNameOrPath_(ancestors[i], stateNameOrPath)) {
        return true;
      }
    }
    return false;
  };

  /**
   * @private
   * @param {!StateNode} node
   * @param {string} target
   * @return {boolean}
   */
  HierarchicalStateMachine.prototype.matchesNameOrPath_ = function(node, target) {
    return node.name === target || node.getPath() === target;
  };

  /**
   * Returns dotted path of currently active state.
   * @return {string}
   */
  HierarchicalStateMachine.prototype.getStatePath = function() {
    return this.currentState.getPath();
  };

  /**
   * Alias for getStatePath().
   * @return {string}
   */
  HierarchicalStateMachine.prototype.getCurrentStatePath = function() {
    return this.getStatePath();
  };

  /**
   * Returns current active state node.
   * @return {!StateNode}
   */
  HierarchicalStateMachine.prototype.getCurrentState = function() {
    return this.currentState;
  };

  /**
   * @private
   * @param {string} eventName
   * @param {!EventContext} context
   * @return {?{sourceNode: !StateNode, rule: !TransitionRule}}
   */
  HierarchicalStateMachine.prototype.findRule_ = function(eventName, context) {
    var curr = this.currentState;
    while (curr !== null) {
      var rules = curr.transitions[eventName];
      if (rules && rules.length > 0) {
        for (var i = 0; i < rules.length; i++) {
          var rule = rules[i];
          if (!rule.guard || rule.guard(context)) {
            return {sourceNode: curr, rule: rule};
          }
        }
      }
      curr = curr.parent;
    }
    return null;
  };

  /**
   * @private
   * @param {!StateNode} sourceNode
   * @param {string} targetName
   * @return {?StateNode}
   */
  HierarchicalStateMachine.prototype.resolveTargetNode_ = function(sourceNode, targetName) {
    if (targetName.indexOf('.') !== -1) {
      return findNodeByPath(this.root, targetName);
    }
    var parent = sourceNode.parent;
    if (parent && parent.children[targetName]) {
      return parent.children[targetName];
    }
    return findNodeByPath(this.root, targetName);
  };

  /**
   * @private
   * @param {!StateNode} targetNode
   * @return {{exitNodes: !Array<!StateNode>, entryNodes: !Array<!StateNode>, finalLeaf: !StateNode}}
   */
  HierarchicalStateMachine.prototype.computeTransitionPlan_ = function(targetNode) {
    var lcca = findLCCA(this.currentState, targetNode);
    var exitNodes = resolveExitPath(this.currentState, lcca);
    var entryNodes = resolveEntryPath(targetNode, lcca);

    var res = resolveInitialLeaf(targetNode);
    entryNodes = entryNodes.concat(res.descendants);
    return {exitNodes: exitNodes, entryNodes: entryNodes, finalLeaf: res.leaf};
  };

  /**
   * @private
   * @param {!StateNode} targetNode
   * @param {?function(!EventContext): void} action
   * @param {!EventContext} context
   * @return {boolean}
   */
  HierarchicalStateMachine.prototype.dispatchTransition_ = function(targetNode, action, context) {
    var plan = this.computeTransitionPlan_(targetNode);
    var priorState = this.currentState;
    try {
      // 1. Bottom-up exit passes
      for (var i = 0; i < plan.exitNodes.length; i++) {
        if (plan.exitNodes[i].onExit) {
          plan.exitNodes[i].onExit(context);
        }
      }
      // 2. Transition action
      if (action) {
        action(context);
      }
      // 3. Top-down entry passes
      for (var j = 0; j < plan.entryNodes.length; j++) {
        if (plan.entryNodes[j].onEntry) {
          plan.entryNodes[j].onEntry(context);
        }
      }
      // 4. Update current state to final leaf
      this.currentState = plan.finalLeaf;

      // 5. Notify observers
      for (var k = 0; k < this.observers_.length; k++) {
        try {
          this.observers_[k](priorState, plan.finalLeaf, context);
        } catch (e) {
          console.error('HSM transition observer failed:', e);
        }
      }
      return true;
    } catch (err) {
      console.error('Uncaught exception in HSM transition:', err);
      if (this.failSecureTarget) {
        this.forceTransition(this.failSecureTarget, 'FAIL_SECURE');
      }
      throw err;
    }
  };

  /**
   * Dispatches an event to the HSM, triggering transition if rule matches and guard passes.
   * @param {string} eventName
   * @param {Object<string, *>=} opt_payload
   * @return {boolean} True if transition executed, False if ignored
   */
  HierarchicalStateMachine.prototype.dispatch = function(eventName, opt_payload) {
    var context = new EventContext(eventName, opt_payload || {});
    var match = this.findRule_(eventName, context);
    if (!match) {
      return false;
    }
    var targetNode = this.resolveTargetNode_(match.sourceNode, match.rule.targetName);
    if (!targetNode) {
      console.warn('HSM transition target not found:', match.rule.targetName);
      return false;
    }
    return this.dispatchTransition_(targetNode, match.rule.action, context);
  };

  /**
   * Alias for dispatch().
   * @param {string} eventName
   * @param {Object<string, *>=} opt_payload
   * @return {boolean}
   */
  HierarchicalStateMachine.prototype.sendEvent = function(eventName, opt_payload) {
    return this.dispatch(eventName, opt_payload);
  };

  /**
   * Forces transition to target state path unconditionally with proper exit/entry lifecycle.
   * @param {string} targetPath
   * @param {string=} opt_reason
   * @return {boolean}
   */
  HierarchicalStateMachine.prototype.forceTransition = function(targetPath, opt_reason) {
    var targetNode = findNodeByPath(this.root, targetPath);
    if (!targetNode) {
      console.warn('HSM forced transition target not found:', targetPath);
      return false;
    }
    var context = new EventContext('__FORCE__', {reason: opt_reason || 'FORCED'});
    return this.dispatchTransition_(targetNode, null, context);
  };

  /**
   * Declarative tree builder from plain configuration object.
   * @param {!Object} config
   * @return {!HierarchicalStateMachine}
   */
  HierarchicalStateMachine.fromConfig = function(config) {
    function buildNode(cfg, parent) {
      var node = new StateNode(
        cfg.name,
        parent,
        cfg.initial || null,
        cfg.onEntry || null,
        cfg.onExit || null
      );
      if (cfg.children) {
        var childKeys = Object.keys(cfg.children);
        for (var i = 0; i < childKeys.length; i++) {
          var k = childKeys[i];
          var childCfg = cfg.children[k];
          childCfg.name = childCfg.name || k;
          var childNode = buildNode(childCfg, node);
          node.addChild(childNode);
        }
      }
      if (cfg.transitions) {
        var eventKeys = Object.keys(cfg.transitions);
        for (var j = 0; j < eventKeys.length; j++) {
          var ev = eventKeys[j];
          var tr = cfg.transitions[ev];
          if (Array.isArray(tr)) {
            for (var m = 0; m < tr.length; m++) {
              node.addTransition(new TransitionRule(
                node.name,
                ev,
                typeof tr[m] === 'string' ? tr[m] : tr[m].target,
                tr[m].guard || null,
                tr[m].action || null
              ));
            }
          } else if (typeof tr === 'string') {
            node.addTransition(new TransitionRule(node.name, ev, tr));
          } else if (tr && typeof tr === 'object') {
            node.addTransition(new TransitionRule(
              node.name,
              ev,
              tr.target,
              tr.guard || null,
              tr.action || null
            ));
          }
        }
      }
      return node;
    }

    var rootNode = buildNode(config, null);
    return new HierarchicalStateMachine(rootNode, null, config.failSecureTarget || null);
  };

  // Export to global scope & yuzora frameworks namespace
  if (typeof window !== 'undefined') {
    window.EventContext = EventContext;
    window.TransitionRule = TransitionRule;
    window.StateNode = StateNode;
    window.HierarchicalStateMachine = HierarchicalStateMachine;
    window.HSM = HierarchicalStateMachine;

    window.yuzora = window.yuzora || {};
    window.yuzora.frameworks = window.yuzora.frameworks || {};
    window.yuzora.frameworks.EventContext = EventContext;
    window.yuzora.frameworks.TransitionRule = TransitionRule;
    window.yuzora.frameworks.StateNode = StateNode;
    window.yuzora.frameworks.HierarchicalStateMachine = HierarchicalStateMachine;
    window.yuzora.frameworks.HSM = HierarchicalStateMachine;
  }

  // Export for Node.js / CommonJS testing
  if (typeof module !== 'undefined' && module.exports) {
    module.exports = {
      EventContext: EventContext,
      TransitionRule: TransitionRule,
      StateNode: StateNode,
      HierarchicalStateMachine: HierarchicalStateMachine,
      findLCCA: findLCCA,
      resolveExitPath: resolveExitPath,
      resolveEntryPath: resolveEntryPath,
      resolveInitialLeaf: resolveInitialLeaf,
      findNodeByPath: findNodeByPath,
      validateTree: validateTree
    };
  }
})();
