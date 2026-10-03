/**
 * CTI Knowledge Graph Query DSL In-Memory Evaluator
 * Conforms to DSN-25 Phase 2 Ahead-of-Time PEG Compiler & Issue #419 specifications.
 * Evaluates parsed CTI query ASTs against in-memory graph mesh (nodes & edges).
 */
'use strict';

(function(global) {
  /**
   * Helper to normalize string for case-insensitive comparison.
   * @param {*} val
   * @returns {string}
   */
  function _normalize(val) {
    if (val === null || val === undefined) return '';
    return String(val).toLowerCase().trim();
  }

  /**
   * Safe property reader preventing prototype pollution.
   * @param {Object} obj
   * @param {string} prop
   * @returns {*}
   */
  function _safeGet(obj, prop) {
    if (!obj || typeof obj !== 'object') return undefined;
    if (prop === '__proto__' || prop === 'prototype' || prop === 'constructor') return undefined;
    if (Object.prototype.hasOwnProperty.call(obj, prop)) {
      return obj[prop];
    }
    return undefined;
  }

  /**
   * CTIQueryEvaluator constructor.
   * @constructor
   * @param {Object=} options
   */
  function CTIQueryEvaluator(options) {
    this.options = options || {};
  }

  /**
   * Extracts clean query structure from PEG AST.
   * @param {Object} ast Root AST node from CTIQueryParser
   * @returns {Object|null}
   */
  CTIQueryEvaluator.prototype.extractQueryModel = function(ast) {
    if (!ast || ast.type !== 'query' || !Array.isArray(ast.value)) return null;

    // query <- opt_ws (path_query / filter_query) opt_ws
    var inner = ast.value[1];
    if (!inner) return null;

    if (inner.type === 'filter_query') {
      return this._extractFilterModel(inner.value);
    } else if (inner.type === 'path_query') {
      return this._extractPathModel(inner.value);
    }
    return null;
  };

  /**
   * Extracts filter items from filter_expr AST.
   * @private
   */
  CTIQueryEvaluator.prototype._extractFilterModel = function(filterExprAst) {
    if (!filterExprAst || filterExprAst.type !== 'filter_expr') return null;
    var list = [];
    var val = filterExprAst.value;
    if (!Array.isArray(val) || val.length < 1) return null;

    // First item
    var first = val[0];
    if (first && first.type === 'filter_item' && Array.isArray(first.value)) {
      list.push({
        key: first.value[0].value,
        val: first.value[2].value
      });
    }

    // Rest items: star(seq([opt_ws, and_kw, opt_ws, filter_item]))
    var rest = val[1];
    if (Array.isArray(rest)) {
      for (var i = 0; i < rest.length; i++) {
        var seqItem = rest[i];
        if (Array.isArray(seqItem) && seqItem.length >= 4) {
          var fItem = seqItem[3];
          if (fItem && fItem.type === 'filter_item' && Array.isArray(fItem.value)) {
            list.push({
              key: fItem.value[0].value,
              val: fItem.value[2].value
            });
          }
        }
      }
    }

    return {
      kind: 'filter',
      filters: list
    };
  };

  /**
   * Extracts node and edge step sequence from path_pattern AST.
   * @private
   */
  CTIQueryEvaluator.prototype._extractPathModel = function(pathPatternAst) {
    if (!pathPatternAst || pathPatternAst.type !== 'path_pattern') return null;
    var val = pathPatternAst.value;
    if (!Array.isArray(val) || val.length < 2) return null;

    var startNodeAst = val[0];
    var startPattern = this._extractNodePattern(startNodeAst);

    var steps = [];
    var restSteps = val[1];
    if (Array.isArray(restSteps)) {
      for (var i = 0; i < restSteps.length; i++) {
        var stepSeq = restSteps[i];
        if (Array.isArray(stepSeq) && stepSeq.length >= 4) {
          var edgeAst = stepSeq[1];
          var nodeAst = stepSeq[3];
          steps.push({
            edge: this._extractEdgePattern(edgeAst),
            node: this._extractNodePattern(nodeAst)
          });
        }
      }
    }

    return {
      kind: 'path',
      start: startPattern,
      steps: steps
    };
  };

  /**
   * Extracts node matching criteria.
   * @private
   */
  CTIQueryEvaluator.prototype._extractNodePattern = function(nodeAst) {
    if (!nodeAst || nodeAst.type !== 'node_pattern') {
      return { alias: null, label: null, name: null };
    }
    var inner = nodeAst.value;
    if (inner.type === 'simple_node') {
      var nameVal = inner.value && inner.value.value;
      return { alias: null, label: null, name: nameVal };
    } else if (inner.type === 'paren_node') {
      // "(" opt_ws node_body? opt_ws ")"
      var body = inner.value[2];
      if (!body || body.type !== 'node_body' || !Array.isArray(body.value)) {
        return { alias: null, label: null, name: null };
      }
      var aliasIdent = body.value[0];
      var labelPart = body.value[1];
      var aliasStr = aliasIdent ? aliasIdent.value : null;
      var labelStr = null;
      if (labelPart && labelPart.type === 'label_part' && Array.isArray(labelPart.value)) {
        labelStr = labelPart.value[1] ? labelPart.value[1].value : null;
      }
      return {
        alias: aliasStr,
        label: labelStr,
        name: null
      };
    }
    return { alias: null, label: null, name: null };
  };

  /**
   * Extracts edge matching criteria.
   * @private
   */
  CTIQueryEvaluator.prototype._extractEdgePattern = function(edgeAst) {
    if (!edgeAst || edgeAst.type !== 'edge_pattern') {
      return { direction: 'both', label: null };
    }
    var inner = edgeAst.value;
    var t = inner.type;

    if (t === 'arrow_out') return { direction: 'out', label: null };
    if (t === 'arrow_in') return { direction: 'in', label: null };
    if (t === 'arrow_both') return { direction: 'both', label: null };

    var colonLabel = null;
    if (t === 'bracket_out' || t === 'bracket_in' || t === 'bracket_both') {
      // "-[" opt_ws colon_label? opt_ws "]->"
      colonLabel = inner.value[2];
    } else if (t === 'arrow_bracket_arrow') {
      // "->[" opt_ws colon_label? opt_ws "]->"
      colonLabel = inner.value[4];
    }

    var labelName = null;
    if (colonLabel && colonLabel.type === 'colon_label' && Array.isArray(colonLabel.value)) {
      labelName = colonLabel.value[1] ? colonLabel.value[1].value : null;
    }

    var dir = 'both';
    if (t === 'bracket_out' || t === 'arrow_bracket_arrow') dir = 'out';
    else if (t === 'bracket_in') dir = 'in';

    return {
      direction: dir,
      label: labelName
    };
  };

  /**
   * Matches a node against pattern criteria.
   * @private
   */
  CTIQueryEvaluator.prototype._matchesNode = function(node, pattern) {
    if (!node || !pattern) return false;
    if (pattern.name) {
      var nName = _normalize(pattern.name);
      var idMatch = _normalize(node.id).indexOf(nName) !== -1;
      var lblMatch = _normalize(node.label || node.name || node.title).indexOf(nName) !== -1;
      var typeMatch = _normalize(node.type) === nName;
      if (!idMatch && !lblMatch && !typeMatch) return false;
    }

    if (pattern.label) {
      var pLabel = _normalize(pattern.label);
      var nType = _normalize(node.type);
      var nLabel = _normalize(node.label || node.name);
      if (nType !== pLabel && nLabel.indexOf(pLabel) === -1) {
        return false;
      }
    }
    return true;
  };

  /**
   * Matches an edge against criteria.
   * @private
   */
  CTIQueryEvaluator.prototype._matchesEdge = function(edge, sourceId, targetId, edgePattern) {
    if (!edge) return false;
    var matchesDir = false;

    if (edgePattern.direction === 'out') {
      matchesDir = (edge.source === sourceId && edge.target === targetId);
    } else if (edgePattern.direction === 'in') {
      matchesDir = (edge.target === sourceId && edge.source === targetId);
    } else {
      // both
      matchesDir = (edge.source === sourceId && edge.target === targetId) ||
                   (edge.target === sourceId && edge.source === targetId);
    }
    if (!matchesDir) return false;

    if (edgePattern.label) {
      var pRel = _normalize(edgePattern.label);
      var eRel = _normalize(edge.label || edge.relation || edge.rel);
      if (eRel !== pRel && eRel.indexOf(pRel) === -1) {
        return false;
      }
    }
    return true;
  };

  /**
   * Evaluates parsed AST against in-memory graph.
   * @param {Object} ast Parsed PEG query AST
   * @param {Array<Object>} nodes Node list
   * @param {Array<Object>} edges Edge list
   * @returns {Object} Evaluation result
   */
  CTIQueryEvaluator.prototype.evaluate = function(ast, nodes, edges) {
    var rawNodes = Array.isArray(nodes) ? nodes : [];
    var rawEdges = Array.isArray(edges) ? edges : [];

    var model = this.extractQueryModel(ast);
    if (!model) {
      return {
        success: false,
        kind: 'unknown',
        matchedNodeIds: new Set(),
        matchedEdgeKeys: new Set(),
        matchedNodes: [],
        matchedEdges: [],
        count: 0
      };
    }

    if (model.kind === 'filter') {
      return this._evaluateFilter(model.filters, rawNodes, rawEdges);
    } else if (model.kind === 'path') {
      return this._evaluatePath(model, rawNodes, rawEdges);
    }

    return {
      success: false,
      kind: 'unsupported',
      matchedNodeIds: new Set(),
      matchedEdgeKeys: new Set(),
      matchedNodes: [],
      matchedEdges: [],
      count: 0
    };
  };

  /**
   * Evaluates filter conditions against graph.
   * @private
   */
  CTIQueryEvaluator.prototype._evaluateFilter = function(filters, nodes, edges) {
    var matchedNodes = [];
    var matchedNodeIds = new Set();

    for (var i = 0; i < nodes.length; i++) {
      var n = nodes[i];
      var matchAll = true;

      for (var f = 0; f < filters.length; f++) {
        var k = filters[f].key;
        var v = _normalize(filters[f].val);
        var normKey = _normalize(k);

        var valCandidate = '';
        if (normKey === 'type') {
          valCandidate = _normalize(n.type);
        } else if (normKey === 'id') {
          valCandidate = _normalize(n.id);
        } else if (normKey === 'severity') {
          valCandidate = _normalize(n.severity);
        } else if (normKey === 'label' || normKey === 'name' || normKey === 'title') {
          valCandidate = _normalize(n.label || n.name || n.title);
        } else {
          valCandidate = _normalize(_safeGet(n, k));
        }

        if (valCandidate.indexOf(v) === -1) {
          matchAll = false;
          break;
        }
      }

      if (matchAll) {
        matchedNodes.push(n);
        matchedNodeIds.add(n.id);
      }
    }

    // Find edges connecting matched nodes
    var matchedEdges = [];
    var matchedEdgeKeys = new Set();
    for (var j = 0; j < edges.length; j++) {
      var e = edges[j];
      if (matchedNodeIds.has(e.source) && matchedNodeIds.has(e.target)) {
        matchedEdges.push(e);
        matchedEdgeKeys.add(e.source + '->' + e.target);
      }
    }

    return {
      success: true,
      kind: 'filter',
      matchedNodeIds: matchedNodeIds,
      matchedEdgeKeys: matchedEdgeKeys,
      matchedNodes: matchedNodes,
      matchedEdges: matchedEdges,
      count: matchedNodes.length
    };
  };

  /**
   * Evaluates multi-step path query against graph.
   * @private
   */
  CTIQueryEvaluator.prototype._evaluatePath = function(model, nodes, edges) {
    var nodeMap = new Map();
    for (var i = 0; i < nodes.length; i++) {
      nodeMap.set(nodes[i].id, nodes[i]);
    }

    // Build fast adjacency map
    var adj = new Map(); // nodeId -> list of { edge, neighborId }
    for (var j = 0; j < edges.length; j++) {
      var edge = edges[j];
      var s = edge.source;
      var t = edge.target;
      if (!adj.has(s)) adj.set(s, []);
      if (!adj.has(t)) adj.set(t, []);
      adj.get(s).push({ edge: edge, neighborId: t, dir: 'out' });
      adj.get(t).push({ edge: edge, neighborId: s, dir: 'in' });
    }

    // Step 1: Find candidate start nodes
    var currentCandidates = []; // Array of { currentId: string, pathNodes: Set<string>, pathEdges: Set<Object> }
    for (var k = 0; k < nodes.length; k++) {
      var node = nodes[k];
      if (this._matchesNode(node, model.start)) {
        var nodeSet = new Set();
        nodeSet.add(node.id);
        currentCandidates.push({
          currentId: node.id,
          pathNodes: nodeSet,
          pathEdges: new Set()
        });
      }
    }

    // Step 2: Step-by-step traversal
    for (var sIdx = 0; sIdx < model.steps.length; sIdx++) {
      var step = model.steps[sIdx];
      var nextCandidates = [];

      for (var cIdx = 0; cIdx < currentCandidates.length; cIdx++) {
        var cand = currentCandidates[cIdx];
        var neighbors = adj.get(cand.currentId) || [];

        for (var nIdx = 0; nIdx < neighbors.length; nIdx++) {
          var item = neighbors[nIdx];
          var nextNode = nodeMap.get(item.neighborId);
          if (!nextNode) continue;

          // Check edge pattern
          if (!this._matchesEdge(item.edge, cand.currentId, item.neighborId, step.edge)) {
            continue;
          }

          // Check target node pattern
          if (!this._matchesNode(nextNode, step.node)) {
            continue;
          }

          var newNodes = new Set(cand.pathNodes);
          newNodes.add(item.neighborId);

          var newEdges = new Set(cand.pathEdges);
          newEdges.add(item.edge);

          nextCandidates.push({
            currentId: item.neighborId,
            pathNodes: newNodes,
            pathEdges: newEdges
          });
        }
      }
      currentCandidates = nextCandidates;
      if (currentCandidates.length === 0) break;
    }

    // Collect all matched nodes and edges
    var matchedNodeIds = new Set();
    var matchedNodes = [];
    var matchedEdgeKeys = new Set();
    var matchedEdges = [];

    for (var resIdx = 0; resIdx < currentCandidates.length; resIdx++) {
      var res = currentCandidates[resIdx];
      res.pathNodes.forEach(function(nid) {
        if (!matchedNodeIds.has(nid)) {
          matchedNodeIds.add(nid);
          var nObj = nodeMap.get(nid);
          if (nObj) matchedNodes.push(nObj);
        }
      });
      res.pathEdges.forEach(function(edgeObj) {
        var eKey = edgeObj.source + '->' + edgeObj.target;
        if (!matchedEdgeKeys.has(eKey)) {
          matchedEdgeKeys.add(eKey);
          matchedEdges.push(edgeObj);
        }
      });
    }

    return {
      success: true,
      kind: 'path',
      matchedNodeIds: matchedNodeIds,
      matchedEdgeKeys: matchedEdgeKeys,
      matchedNodes: matchedNodes,
      matchedEdges: matchedEdges,
      count: matchedNodes.length
    };
  };

  /**
   * Convenience method to parse and evaluate in one step.
   * @param {Object} parser CTIQueryParser instance
   * @param {string} queryString
   * @param {Array<Object>} nodes
   * @param {Array<Object>} edges
   * @returns {Object}
   */
  CTIQueryEvaluator.prototype.evaluateQuery = function(parser, queryString, nodes, edges) {
    if (!parser || typeof parser.parseWithDiagnostics !== 'function') {
      return {
        success: false,
        error: 'Invalid CTIQueryParser instance',
        matchedNodeIds: new Set(),
        matchedNodes: [],
        count: 0
      };
    }
    var diag = parser.parseWithDiagnostics(queryString);
    if (!diag.success) {
      return {
        success: false,
        diagnostics: diag.diagnostics,
        error: diag.diagnostics ? diag.diagnostics.errorMsg : 'Syntax Error',
        matchedNodeIds: new Set(),
        matchedNodes: [],
        count: 0
      };
    }
    var result = this.evaluate(diag.value, nodes, edges);
    result.diagnostics = null;
    return result;
  };

  // --- Module Exports ---
  if (typeof module !== 'undefined' && module.exports) {
    module.exports = { CTIQueryEvaluator: CTIQueryEvaluator };
  }
  if (typeof window !== 'undefined') {
    window.CTIQueryEvaluator = CTIQueryEvaluator;
    window.Application = window.Application || {};
    window.Application.frameworks = window.Application.frameworks || {};
    window.Application.frameworks.CTIQueryEvaluator = CTIQueryEvaluator;
  }
})(typeof window !== 'undefined' ? window : (typeof global !== 'undefined' ? global : this));
