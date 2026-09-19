/**
 * @fileoverview GraphCanvasEngine: High-Performance Canvas 2D Force-Directed Graph Engine.
 * Encapsulates force-directed physics simulation (Coulomb repulsion, Hooke springs, center gravity),
 * spatial transformation matrix (pan, zoom, scale-aware bounds), 2D rendering pipeline,
 * and interaction state machine.
 * Part of yuzora-frameworks integration (DSN-27 / Issue 348).
 */

(function() {
  'use strict';

  /**
   * @typedef {{
   *   id: (string|number),
   *   label: (string|undefined),
   *   x: number,
   *   y: number,
   *   vx: number,
   *   vy: number,
   *   fx: (number|undefined),
   *   fy: (number|undefined),
   *   fx_force: number,
   *   fy_force: number,
   *   degree: number
   * }}
   */
  var GraphNode;

  /**
   * @typedef {{
   *   source: (string|number),
   *   target: (string|number),
   *   relation: (string|undefined),
   *   weight: (number|undefined)
   * }}
   */
  var GraphEdge;

  /**
   * Default physics configuration constants.
   * @const {!Object<string, number>}
   */
  var DEFAULT_PHYSICS_CONFIG = {
    K_REPULSION: 4500,
    K_SPRING: 0.045,
    K_CENTER: 0.015,
    DAMPING: 0.88,
    SPRING_LENGTH: 90,
    MAX_VELOCITY: 35.0,
    STOP_ENERGY_THRESHOLD: 0.008
  };

  /**
   * GraphCanvasEngine Constructor.
   *
   * @constructor
   * @param {?HTMLCanvasElement} canvas Target HTML5 Canvas element (optional for headless/Node.js testing)
   * @param {!Object<string, *>=} opt_options Optional configuration parameters
   */
  function GraphCanvasEngine(canvas, opt_options) {
    var opts = opt_options || {};

    /** @type {?HTMLCanvasElement} */
    this.canvas = canvas || null;
    /** @type {?CanvasRenderingContext2D} */
    this.ctx = (this.canvas && typeof this.canvas.getContext === 'function')
      ? /** @type {?CanvasRenderingContext2D} */ (this.canvas.getContext('2d'))
      : null;

    /** @type {number} */
    this.width = opts['width'] ? Number(opts['width']) : (this.canvas ? this.canvas.width : 800);
    /** @type {number} */
    this.height = opts['height'] ? Number(opts['height']) : (this.canvas ? this.canvas.height : 600);
    /** @type {number} */
    this.dpr = (typeof window !== 'undefined' && window.devicePixelRatio) ? window.devicePixelRatio : 1.0;

    /**
     * Viewport transform matrix (screen to world mapping).
     * @type {{x: number, y: number, scale: number}}
     */
    this.viewTransform = { x: 0, y: 0, scale: 1.0 };

    /**
     * Physics constants.
     * @type {!Object<string, number>}
     */
    this.physics = Object.assign({}, DEFAULT_PHYSICS_CONFIG, opts['physics'] || {});

    /** @type {!Array<!GraphNode>} */
    this.nodes = [];
    /** @type {!Array<!GraphEdge>} */
    this.edges = [];
    /** @type {!Map<string, !GraphNode>} */
    this.nodeMap = new Map();

    /** @type {?string} */
    this.selectedNodeId = null;
    /** @type {?string} */
    this.hoveredNodeId = null;
    /** @type {?GraphNode} */
    this.draggedNode = null;

    /** @type {boolean} */
    this.isPanning = false;
    /** @type {{x: number, y: number}} */
    this.panStart = { x: 0, y: 0 };

    /** @type {boolean} */
    this.isRunning = false;
    /** @type {?number} */
    this.animFrameId_ = null;
    /** @type {number} */
    this.kineticEnergy = 100.0;

    /** @type {?Object} */
    this.publisher_ = opts['publisher'] || (typeof window !== 'undefined' && ((window.Application && window.Application.frameworks && window.Application.frameworks.Publisher) || (window.yuzora && window.yuzora.frameworks && window.yuzora.frameworks.Publisher)) ? new ((window.Application && window.Application.frameworks && window.Application.frameworks.Publisher) || window.yuzora.frameworks.Publisher)() : null);

    /** @type {boolean} */
    this.hideIsolated = false;
    /** @type {number} */
    this.minDegree = 0;

    this.initInteraction_();
  }

  /**
   * Initializes event listeners on the canvas.
   * @private
   */
  GraphCanvasEngine.prototype.initInteraction_ = function() {
    if (!this.canvas || typeof this.canvas.addEventListener !== 'function') {
      return;
    }

    var self = this;

    this.canvas.addEventListener('wheel', function(e) {
      e.preventDefault();
      var mouse = self.getNormalizedCanvasMouse(e);
      var zoomFactor = e.deltaY < 0 ? 1.12 : 0.89;
      self.zoomAt(mouse.x, mouse.y, zoomFactor);
    }, { passive: false });

    this.canvas.addEventListener('mousedown', function(e) {
      var mouse = self.getNormalizedCanvasMouse(e);
      var world = self.screenToWorld(mouse.x, mouse.y);
      var hit = self.findNodeAtWorld(world.x, world.y);

      if (e.button === 0 && hit) {
        self.draggedNode = hit;
        self.selectedNodeId = String(hit.id);
        hit.fx = hit.x;
        hit.fy = hit.y;
        self.notify_('graph:node_selected', { node: hit });
      } else {
        self.isPanning = true;
        self.panStart = { x: mouse.x - self.viewTransform.x, y: mouse.y - self.viewTransform.y };
      }
    });

    if (typeof window !== 'undefined') {
      window.addEventListener('mousemove', function(e) {
        if (!self.canvas) return;
        var mouse = self.getNormalizedCanvasMouse(e);

        if (self.draggedNode) {
          var world = self.screenToWorld(mouse.x, mouse.y);
          self.draggedNode.x = world.x;
          self.draggedNode.y = world.y;
          self.draggedNode.fx = world.x;
          self.draggedNode.fy = world.y;
          self.kineticEnergy = 50.0;
        } else if (self.isPanning) {
          self.viewTransform.x = mouse.x - self.panStart.x;
          self.viewTransform.y = mouse.y - self.panStart.y;
          self.notify_('graph:viewport_change', { transform: self.viewTransform });
        } else {
          var w = self.screenToWorld(mouse.x, mouse.y);
          var h = self.findNodeAtWorld(w.x, w.y);
          var prevHover = self.hoveredNodeId;
          self.hoveredNodeId = h ? String(h.id) : null;
          if (self.hoveredNodeId !== prevHover) {
            self.notify_('graph:node_hovered', { node: h });
          }
        }
      });

      window.addEventListener('mouseup', function(e) {
        if (self.draggedNode) {
          delete self.draggedNode.fx;
          delete self.draggedNode.fy;
          self.draggedNode = null;
        }
        self.isPanning = false;
      });
    }
  };

  /**
   * Helper to publish events.
   * @param {string} topic
   * @param {!Object<string, *>} data
   * @private
   */
  GraphCanvasEngine.prototype.notify_ = function(topic, data) {
    if (this.publisher_ && typeof this.publisher_.publish === 'function') {
      this.publisher_.publish(topic, data);
    }
  };

  /**
   * Normalizes client mouse coordinates relative to canvas bounding box.
   * @param {(!MouseEvent|!Event)} e
   * @return {{x: number, y: number}}
   */
  GraphCanvasEngine.prototype.getNormalizedCanvasMouse = function(e) {
    if (!this.canvas) return { x: 0, y: 0 };
    var rect = this.canvas.getBoundingClientRect();
    var mouseEvent = /** @type {!MouseEvent} */ (e);
    var scaleX = (rect.width > 0) ? (this.width / rect.width) : 1;
    var scaleY = (rect.height > 0) ? (this.height / rect.height) : 1;
    return {
      x: (mouseEvent.clientX - rect.left) * scaleX,
      y: (mouseEvent.clientY - rect.top) * scaleY
    };
  };

  /**
   * Converts screen coordinates to world coordinates.
   * @param {number} sx
   * @param {number} sy
   * @return {{x: number, y: number}}
   */
  GraphCanvasEngine.prototype.screenToWorld = function(sx, sy) {
    return {
      x: (sx - this.viewTransform.x) / this.viewTransform.scale,
      y: (sy - this.viewTransform.y) / this.viewTransform.scale
    };
  };

  /**
   * Converts world coordinates to screen coordinates.
   * @param {number} wx
   * @param {number} wy
   * @return {{x: number, y: number}}
   */
  GraphCanvasEngine.prototype.worldToScreen = function(wx, wy) {
    return {
      x: wx * this.viewTransform.scale + this.viewTransform.x,
      y: wy * this.viewTransform.scale + this.viewTransform.y
    };
  };

  /**
   * Loads nodes and edges into the engine.
   * @param {{nodes: !Array<!Object<string, *>>, edges: !Array<!Object<string, *>>}} data
   */
  GraphCanvasEngine.prototype.loadData = function(data) {
    var rawNodes = data.nodes || [];
    var rawEdges = data.edges || [];

    this.nodeMap.clear();
    this.nodes = [];
    this.edges = [];

    var cx = this.width / 2;
    var cy = this.height / 2;

    for (var i = 0; i < rawNodes.length; i++) {
      var raw = rawNodes[i];
      var idStr = String(raw['id']);
      var initX = (typeof raw['x'] === 'number') ? Number(raw['x']) : cx + Math.cos(i) * 120;
      var initY = (typeof raw['y'] === 'number') ? Number(raw['y']) : cy + Math.sin(i) * 120;

      /** @type {!GraphNode} */
      var n = {
        id: idStr,
        label: raw['label'] ? String(raw['label']) : idStr,
        x: initX,
        y: initY,
        vx: 0,
        vy: 0,
        fx_force: 0,
        fy_force: 0,
        degree: 0
      };
      this.nodeMap.set(idStr, n);
      this.nodes.push(n);
    }

    for (var j = 0; j < rawEdges.length; j++) {
      var rawEdge = rawEdges[j];
      var sId = String(rawEdge['source']);
      var tId = String(rawEdge['target']);
      if (this.nodeMap.has(sId) && this.nodeMap.has(tId)) {
        var srcNode = this.nodeMap.get(sId);
        var tgtNode = this.nodeMap.get(tId);
        srcNode.degree++;
        tgtNode.degree++;

        /** @type {!GraphEdge} */
        var e = {
          source: sId,
          target: tId,
          relation: rawEdge['relation'] ? String(rawEdge['relation']) : undefined,
          weight: (typeof rawEdge['weight'] === 'number') ? Number(rawEdge['weight']) : 1.0
        };
        this.edges.push(e);
      }
    }

    this.kineticEnergy = 100.0;
  };

  /**
   * Finds node at given world coordinates.
   * @param {number} wx
   * @param {number} wy
   * @param {number=} opt_radius
   * @return {?GraphNode}
   */
  GraphCanvasEngine.prototype.findNodeAtWorld = function(wx, wy, opt_radius) {
    var r = (opt_radius !== undefined) ? opt_radius : 20.0;
    var rSq = r * r;
    for (var i = this.nodes.length - 1; i >= 0; i--) {
      var n = this.nodes[i];
      var dx = n.x - wx;
      var dy = n.y - wy;
      if (dx * dx + dy * dy <= rSq) {
        return n;
      }
    }
    return null;
  };

  /**
   * Executes one step of the force-directed physics simulation.
   * @param {number=} opt_dt Time delta (defaults to 1.0)
   */
  GraphCanvasEngine.prototype.stepPhysics = function(opt_dt) {
    var dt = (opt_dt !== undefined) ? opt_dt : 1.0;
    var numNodes = this.nodes.length;
    if (numNodes === 0) return;

    var kRep = this.physics.K_REPULSION;
    var kSpr = this.physics.K_SPRING;
    var kCenter = this.physics.K_CENTER;
    var damping = this.physics.DAMPING;
    var springLen = this.physics.SPRING_LENGTH;
    var maxVel = this.physics.MAX_VELOCITY;

    var curScale = this.viewTransform.scale || 1.0;
    var width = this.width;
    var height = this.height;

    // Scale-aware world span calculation
    var worldSpanX = width / Math.min(1.0, curScale);
    var worldSpanY = height / Math.min(1.0, curScale);
    var effectiveKCenter = kCenter * Math.min(1.0, curScale);

    var cx = width / 2;
    var cy = height / 2;
    var halfSpanX = worldSpanX * 0.48;
    var halfSpanY = worldSpanY * 0.48;
    var padY = Math.min(24, Math.max(10, height * 0.05));

    // Reset forces
    for (var i = 0; i < numNodes; i++) {
      var ni = this.nodes[i];
      ni.fx_force = 0;
      ni.fy_force = 0;
    }

    // 1. Coulomb Repulsion
    for (var i = 0; i < numNodes; i++) {
      var nodeA = this.nodes[i];
      for (var j = i + 1; j < numNodes; j++) {
        var nodeB = this.nodes[j];
        var dx = nodeB.x - nodeA.x;
        var dy = nodeB.y - nodeA.y;
        var distSq = dx * dx + dy * dy + 100.0;
        var dist = Math.sqrt(distSq);
        var force = kRep / distSq;
        var fx = (dx / dist) * force;
        var fy = (dy / dist) * force;

        nodeA.fx_force -= fx;
        nodeA.fy_force -= fy;
        nodeB.fx_force += fx;
        nodeB.fy_force += fy;
      }
    }

    // 2. Hooke Spring Attraction
    for (var e = 0; e < this.edges.length; e++) {
      var edge = this.edges[e];
      var s = this.nodeMap.get(String(edge.source));
      var t = this.nodeMap.get(String(edge.target));
      if (!s || !t) continue;

      var dx = t.x - s.x;
      var dy = t.y - s.y;
      var dist = Math.sqrt(dx * dx + dy * dy) || 1.0;
      var displacement = dist - springLen;
      var springForce = kSpr * displacement;
      var fx = (dx / dist) * springForce;
      var fy = (dy / dist) * springForce;

      s.fx_force += fx;
      s.fy_force += fy;
      t.fx_force -= fx;
      t.fy_force -= fy;
    }

    // 3. Center Gravity & Integration with bounds
    var totalEnergy = 0.0;
    for (var i = 0; i < numNodes; i++) {
      var n = this.nodes[i];
      if (n.fx !== undefined && n.fy !== undefined) {
        continue;
      }

      // Center gravity
      n.fx_force += (cx - n.x) * effectiveKCenter;
      n.fy_force += (cy - n.y) * effectiveKCenter;

      n.vx = (n.vx + n.fx_force * dt) * damping;
      n.vy = (n.vy + n.fy_force * dt) * damping;

      var vel = Math.sqrt(n.vx * n.vx + n.vy * n.vy);
      if (vel > maxVel) {
        n.vx = (n.vx / vel) * maxVel;
        n.vy = (n.vy / vel) * maxVel;
      }

      n.x += n.vx * dt;
      n.y += n.vy * dt;

      // Dynamic bounds clamping
      n.x = Math.max(cx - halfSpanX, Math.min(cx + halfSpanX, n.x));
      n.y = Math.max(cy - halfSpanY, Math.min(cy + halfSpanY, n.y));
      n.y = Math.max(padY, Math.min(height - padY, n.y));

      totalEnergy += vel * vel;
    }

    this.kineticEnergy = totalEnergy;
  };

  /**
   * Renders the current graph frame to the 2D canvas.
   */
  GraphCanvasEngine.prototype.render = function() {
    if (!this.ctx || !this.canvas) return;
    var ctx = this.ctx;

    ctx.save();
    ctx.clearRect(0, 0, this.width, this.height);

    ctx.translate(this.viewTransform.x, this.viewTransform.y);
    ctx.scale(this.viewTransform.scale, this.viewTransform.scale);

    // Draw edges
    ctx.lineWidth = 1.2;
    for (var i = 0; i < this.edges.length; i++) {
      var e = this.edges[i];
      var s = this.nodeMap.get(String(e.source));
      var t = this.nodeMap.get(String(e.target));
      if (!s || !t) continue;

      ctx.beginPath();
      ctx.moveTo(s.x, s.y);
      ctx.lineTo(t.x, t.y);
      ctx.strokeStyle = '#a8a29e';
      ctx.stroke();
    }

    // Draw nodes
    for (var j = 0; j < this.nodes.length; j++) {
      var n = this.nodes[j];
      var idStr = String(n.id);
      var isSelected = (idStr === this.selectedNodeId);
      var isHovered = (idStr === this.hoveredNodeId);
      var radius = isSelected ? 12 : (isHovered ? 10 : 8);

      ctx.beginPath();
      ctx.arc(n.x, n.y, radius, 0, 2 * Math.PI);
      ctx.fillStyle = isSelected ? '#e0533c' : (isHovered ? '#3d5a80' : '#2b2b2b');
      ctx.fill();

      // Node label
      if (this.viewTransform.scale > 0.6 || isSelected || isHovered) {
        ctx.font = '10px monospace';
        ctx.fillStyle = '#2b2b2b';
        ctx.fillText(String(n.label || idStr), n.x + radius + 3, n.y + 3);
      }
    }

    ctx.restore();
  };

  /**
   * Starts the continuous simulation and render loop.
   */
  GraphCanvasEngine.prototype.start = function() {
    if (this.isRunning) return;
    this.isRunning = true;

    var self = this;
    function loop() {
      if (!self.isRunning) return;
      if (self.kineticEnergy > self.physics.STOP_ENERGY_THRESHOLD) {
        self.stepPhysics(1.0);
      }
      self.render();
      if (typeof window !== 'undefined' && typeof window.requestAnimationFrame === 'function') {
        self.animFrameId_ = window.requestAnimationFrame(loop);
      }
    }
    loop();
  };

  /**
   * Stops the simulation and render loop.
   */
  GraphCanvasEngine.prototype.stop = function() {
    this.isRunning = false;
    if (this.animFrameId_ && typeof window !== 'undefined' && typeof window.cancelAnimationFrame === 'function') {
      window.cancelAnimationFrame(this.animFrameId_);
      this.animFrameId_ = null;
    }
  };

  /**
   * Zooms in by given factor (default 1.25).
   * @param {number=} opt_factor
   */
  GraphCanvasEngine.prototype.zoomIn = function(opt_factor) {
    var f = opt_factor || 1.25;
    this.zoomAt(this.width / 2, this.height / 2, f);
  };

  /**
   * Zooms out by given factor (default 0.8).
   * @param {number=} opt_factor
   */
  GraphCanvasEngine.prototype.zoomOut = function(opt_factor) {
    var f = opt_factor || 0.8;
    this.zoomAt(this.width / 2, this.height / 2, f);
  };

  /**
   * Zooms around a specific pivot point.
   * @param {number} px
   * @param {number} py
   * @param {number} factor
   */
  GraphCanvasEngine.prototype.zoomAt = function(px, py, factor) {
    var oldScale = this.viewTransform.scale;
    var newScale = Math.min(5.0, Math.max(0.1, oldScale * factor));
    var ratio = newScale / oldScale;

    this.viewTransform.x = px - (px - this.viewTransform.x) * ratio;
    this.viewTransform.y = py - (py - this.viewTransform.y) * ratio;
    this.viewTransform.scale = newScale;

    this.notify_('graph:viewport_change', { transform: this.viewTransform });
    this.render();
  };

  /**
   * Resets viewport transform to initial identity.
   */
  GraphCanvasEngine.prototype.resetView = function() {
    this.viewTransform = { x: 0, y: 0, scale: 1.0 };
    this.notify_('graph:viewport_change', { transform: this.viewTransform });
    this.render();
  };

  /**
   * Resizes internal viewport dimensions.
   * @param {number} width
   * @param {number} height
   */
  GraphCanvasEngine.prototype.resize = function(width, height) {
    var prevWidth = this.width || width;
    var prevHeight = this.height || height;
    this.width = width;
    this.height = height;

    if (this.canvas) {
      this.canvas.width = width;
      this.canvas.height = height;
      this.canvas.style.width = width + 'px';
      this.canvas.style.height = height + 'px';
    }

    if (prevWidth > 0 && prevHeight > 0 && (prevWidth !== width || prevHeight !== height)) {
      var scaleX = width / prevWidth;
      var scaleY = height / prevHeight;
      for (var i = 0; i < this.nodes.length; i++) {
        var n = this.nodes[i];
        n.x *= scaleX;
        n.y *= scaleY;
      }
      this.kineticEnergy = 30.0;
    }
  };

  /**
   * Computes Largest Connected Component using DisjointSet.
   * @param {!Array<!Object<string, *>>} nodes
   * @param {!Array<!Object<string, *>>} edges
   * @return {!Array<!Object<string, *>>}
   */
  GraphCanvasEngine.prototype.computeLargestConnectedComponent = function(nodes, edges) {
    if (!nodes || nodes.length === 0) return [];
    if (!edges || edges.length === 0) return [nodes[0]];

    var ds = (typeof window !== 'undefined' && window.DisjointSet)
      ? new window.DisjointSet()
      : null;

    if (ds) {
      for (var i = 0; i < nodes.length; i++) {
        ds.add(String(nodes[i]['id']));
      }
      for (var j = 0; j < edges.length; j++) {
        ds.union(String(edges[j]['source']), String(edges[j]['target']));
      }
      var lccIds = new Set(ds.getLargestComponent());
      return nodes.filter(function(n) {
        return lccIds.has(String(n['id']));
      });
    }

    // BFS Fallback if DisjointSet not available
    var adj = new Map();
    for (var i = 0; i < nodes.length; i++) {
      adj.set(String(nodes[i]['id']), []);
    }
    for (var j = 0; j < edges.length; j++) {
      var s = String(edges[j]['source']);
      var t = String(edges[j]['target']);
      if (adj.has(s) && adj.has(t)) {
        adj.get(s).push(t);
        adj.get(t).push(s);
      }
    }

    var visited = new Set();
    var largestComponent = [];

    for (var k = 0; k < nodes.length; k++) {
      var rootId = String(nodes[k]['id']);
      if (visited.has(rootId)) continue;

      var component = [];
      var queue = [rootId];
      visited.add(rootId);

      while (queue.length > 0) {
        var curr = queue.shift();
        component.push(curr);
        var neighbors = adj.get(curr) || [];
        for (var nIdx = 0; nIdx < neighbors.length; nIdx++) {
          var nbr = neighbors[nIdx];
          if (!visited.has(nbr)) {
            visited.add(nbr);
            queue.push(nbr);
          }
        }
      }

      if (component.length > largestComponent.length) {
        largestComponent = component;
      }
    }

    var largestSet = new Set(largestComponent);
    return nodes.filter(function(n) {
      return largestSet.has(String(n['id']));
    });
  };

  /**
   * Destroys the engine instance and releases event listeners.
   */
  GraphCanvasEngine.prototype.destroy = function() {
    this.stop();
    this.nodes = [];
    this.edges = [];
    this.nodeMap.clear();
    this.canvas = null;
    this.ctx = null;
  };

  // Export to global scope & Application frameworks namespace
  if (typeof window !== 'undefined') {
    window.GraphCanvasEngine = GraphCanvasEngine;

    window.Application = window.Application || {};
    window.Application.frameworks = window.Application.frameworks || {};
    window.Application.frameworks.GraphCanvasEngine = GraphCanvasEngine;
    window.App = window.Application;
    window.yuzora = window.Application;
  }

  // Export for Node.js / CommonJS testing
  if (typeof module !== 'undefined' && module.exports) {
    module.exports = {
      GraphCanvasEngine: GraphCanvasEngine
    };
  }
})();
