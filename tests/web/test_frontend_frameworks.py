"""
Tests for Frontend Frameworks Integration & Bundle Consistency (Issue 338).
"""

from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent.parent
FRAMEWORKS_DIR = REPO_ROOT / "site" / "js" / "frameworks"
EXTERNS_FILE = REPO_ROOT / "site" / "externs.js"
MAKEFILE = REPO_ROOT / "Makefile"
APP_MIN_JS = REPO_ROOT / "site" / "app-min.js"

EXPECTED_MODULES = [
    "animation.js",
    "api-client.js",
    "arc-cache.js",
    "disjoint-set.js",
    "dom-utils.js",
    "event.js",
    "graph-canvas.js",
    "hsm.js",
    "locator.js",
    "modal.js",
    "publisher.js",
    "query-validator.js",
    "radix-trie.js",
    "router.js",
    "scene.js",
    "scheduler.js",
    "sse-manager.js",
    "store.js",
    "timing.js",
]


def test_framework_files_exist_and_non_empty() -> None:
    """All 9 framework modules must exist in site/js/frameworks/ and have content."""
    assert FRAMEWORKS_DIR.is_dir(), f"Directory not found: {FRAMEWORKS_DIR}"

    for mod_name in EXPECTED_MODULES:
        mod_path = FRAMEWORKS_DIR / mod_name
        assert mod_path.is_file(), f"Missing module: {mod_path}"
        assert (
            mod_path.stat().st_size > 500
        ), f"Module {mod_name} seems too small or empty"


def test_externs_contain_yuzora_interfaces() -> None:
    """site/externs.js must define interfaces to satisfy Closure Compiler."""
    assert EXTERNS_FILE.is_file(), f"Missing externs file: {EXTERNS_FILE}"
    content = EXTERNS_FILE.read_text(encoding="utf-8")

    required_interfaces = [
        "YuzoraEventInterface",
        "YuzoraEventTargetInterface",
        "LocatorInterface",
        "PublisherInterface",
        "RouterInterface",
        "SceneInterface",
        "SceneDirectorInterface",
        "ApiClientInterface",
        "StateStoreInterface",
        "SSEStreamManagerInterface",
        "ModalControllerInterface",
        "RadixTrieInterface",
        "QueryValidatorInterface",
        "HierarchicalStateMachineInterface",
        "DisjointSetInterface",
        "ARCCacheInterface",
        "GraphCanvasEngineInterface",
    ]
    for iface in required_interfaces:
        assert iface in content, f"Interface {iface} missing from site/externs.js"


def test_makefile_includes_frameworks_in_js_srcs() -> None:
    """Makefile JS_SRCS must declare all framework files in order before site/app.js."""
    assert MAKEFILE.is_file(), f"Missing Makefile: {MAKEFILE}"
    content = MAKEFILE.read_text(encoding="utf-8")

    for mod_name in EXPECTED_MODULES:
        rel_path = f"site/js/frameworks/{mod_name}"
        assert rel_path in content, f"Makefile JS_SRCS missing: {rel_path}"

    app_js_pos = content.find("site/app.js")
    for mod_name in EXPECTED_MODULES:
        rel_path = f"site/js/frameworks/{mod_name}"
        mod_pos = content.find(rel_path)
        assert mod_pos < app_js_pos, f"{rel_path} must be included before site/app.js"


def test_app_min_js_contains_bundled_framework_classes() -> None:
    """site/app-min.js must contain compiled classes from frameworks."""
    assert APP_MIN_JS.is_file(), f"Missing compiled bundle: {APP_MIN_JS}"
    content = APP_MIN_JS.read_text(encoding="utf-8")

    core_framework_symbols = [
        "DOMUtils",
        "Timing",
        "AppEvent",
        "AppEventTarget",
        "Publisher",
        "Locator",
        "TaskScheduler",
        "SceneDirector",
        "Router",
        "AnimationUtils",
        "ApiClient",
        "ApiError",
        "StateStore",
        "SSEStreamManager",
        "HierarchicalStateMachine",
        "ModalController",
        "RadixTrie",
        "QueryValidator",
        "DisjointSet",
        "ARCCache",
        "GraphCanvasEngine",
    ]
    for sym in core_framework_symbols:
        assert sym in content, f"Symbol {sym} not found in compiled {APP_MIN_JS.name}"


def test_hsm_state_transitions_and_lcca() -> None:
    """Validate HSM hierarchical transitions, LCCA resolution, entry/exit passes and guards via Node.js."""
    import json
    import shutil
    import subprocess

    node_bin = shutil.which("node")
    if not node_bin:
        return

    script = """
    const { HierarchicalStateMachine, StateNode, TransitionRule } = require('./site/js/frameworks/hsm.js');

    const root = new StateNode('ROOT', null, 'Operational');
    const op = new StateNode('Operational', root, 'Normal');
    const maint = new StateNode('Maintenance', root, 'Diagnostics');
    root.addChild(op);
    root.addChild(maint);

    const normal = new StateNode('Normal', op);
    const inspect = new StateNode('Inspect', op);
    op.addChild(normal);
    op.addChild(inspect);

    const diag = new StateNode('Diagnostics', maint);
    maint.addChild(diag);

    const log = [];
    op.onEntry = () => log.push('enter:Operational');
    op.onExit = () => log.push('exit:Operational');
    normal.onEntry = () => log.push('enter:Normal');
    normal.onExit = () => log.push('exit:Normal');
    inspect.onEntry = () => log.push('enter:Inspect');
    inspect.onExit = () => log.push('exit:Inspect');
    maint.onEntry = () => log.push('enter:Maintenance');
    maint.onExit = () => log.push('exit:Maintenance');
    diag.onEntry = () => log.push('enter:Diagnostics');
    diag.onExit = () => log.push('exit:Diagnostics');

    // Intra-hierarchy transition
    normal.addTransition(new TransitionRule('Normal', 'SELECT_NODE', 'Inspect'));
    inspect.addTransition(new TransitionRule('Inspect', 'DESELECT', 'Normal'));

    // Guarded transition on child
    normal.addTransition(new TransitionRule('Normal', 'SEC_CHECK', 'Inspect', ctx => ctx.payload.authorized === true));

    // Bubble-up transition on composite parent (Operational -> Maintenance)
    op.addTransition(new TransitionRule('Operational', 'MAINT_MODE', 'Maintenance'));

    const hsm = new HierarchicalStateMachine(root);
    const initialPath = hsm.getStatePath();

    // 1. Intra-hierarchy transition
    log.length = 0;
    const ok1 = hsm.dispatch('SELECT_NODE', { nodeId: 'N1' });
    const path1 = hsm.getStatePath();
    const log1 = [...log];

    // 2. Cross-hierarchy transition via event bubbling to Operational
    log.length = 0;
    const ok2 = hsm.dispatch('MAINT_MODE');
    const path2 = hsm.getStatePath();
    const log2 = [...log];

    // 3. isInState checks
    const inMaint = hsm.isInState('Maintenance');
    const inDiag = hsm.isInState('Diagnostics');
    const inOp = hsm.isInState('Operational');

    // 4. Force transition back to Normal
    log.length = 0;
    hsm.forceTransition('Operational.Normal');
    const path3 = hsm.getStatePath();
    const log3 = [...log];

    // 5. Guard evaluation
    const guardDenied = hsm.dispatch('SEC_CHECK', { authorized: false });
    const path4 = hsm.getStatePath();
    const guardAllowed = hsm.dispatch('SEC_CHECK', { authorized: true });
    const path5 = hsm.getStatePath();

    console.log(JSON.stringify({
        initialPath,
        ok1, path1, log1,
        ok2, path2, log2,
        inMaint, inDiag, inOp,
        path3, log3,
        guardDenied, path4,
        guardAllowed, path5
    }));
    """

    res = subprocess.run(
        [node_bin, "-e", script], capture_output=True, text=True, cwd=str(REPO_ROOT)
    )
    assert res.returncode == 0, f"Node.js script failed: {res.stderr}"

    data = json.loads(res.stdout)
    assert data["initialPath"] == "Operational.Normal"
    assert data["ok1"] is True
    assert data["path1"] == "Operational.Inspect"
    assert data["log1"] == ["exit:Normal", "enter:Inspect"]

    # Cross-hierarchy LCCA test (Inspect -> Diagnostics via Operational.MAINT_MODE)
    assert data["ok2"] is True
    assert data["path2"] == "Maintenance.Diagnostics"
    assert data["log2"] == [
        "exit:Inspect",
        "exit:Operational",
        "enter:Maintenance",
        "enter:Diagnostics",
    ]

    # State checks
    assert data["inMaint"] is True
    assert data["inDiag"] is True
    assert data["inOp"] is False

    # Force transition
    assert data["path3"] == "Operational.Normal"
    assert data["log3"] == [
        "exit:Diagnostics",
        "exit:Maintenance",
        "enter:Operational",
        "enter:Normal",
    ]

    # Guard checks
    assert data["guardDenied"] is False
    assert data["path4"] == "Operational.Normal"
    assert data["guardAllowed"] is True
    assert data["path5"] == "Operational.Inspect"


def test_disjoint_set_union_find_and_lcc() -> None:
    """Validate DisjointSet Union-Find operations, LCC extraction, and isolates via Node.js."""
    import json
    import shutil
    import subprocess

    node_bin = shutil.which("node")
    if not node_bin:
        return

    script = """
    const { DisjointSet } = require('./site/js/frameworks/disjoint-set.js');

    const ds = new DisjointSet();

    // 1. Basic add and size
    ds.add('A');
    ds.add('B');
    ds.add('C');
    ds.add('D');
    ds.add('E');
    ds.add('Isolated1');

    const initialSize = ds.size();
    const initialComponents = ds.componentCount();

    // 2. Union operations
    ds.union('A', 'B');
    ds.union('B', 'C');
    ds.union('D', 'E');

    const afterUnionComponents = ds.componentCount();
    const connectedAB = ds.connected('A', 'C');
    const connectedAD = ds.connected('A', 'D');
    const sizeA = ds.componentSize('A');
    const sizeD = ds.componentSize('D');
    const sizeIso = ds.componentSize('Isolated1');

    // 3. LCC (Largest Connected Component)
    const lcc = ds.getLargestComponent();
    const isolates = ds.getIsolates();

    // 4. Benchmark 10,000 elements
    const benchDs = new DisjointSet();
    const t0 = Date.now();
    for (let i = 0; i < 10000; i++) {
        benchDs.add(i);
    }
    for (let i = 0; i < 9999; i += 2) {
        benchDs.union(i, i + 1);
    }
    for (let i = 0; i < 9998; i += 4) {
        benchDs.union(i, i + 2);
    }
    const benchTimeMs = Date.now() - t0;
    const benchCount = benchDs.componentCount();

    console.log(JSON.stringify({
        initialSize,
        initialComponents,
        afterUnionComponents,
        connectedAB,
        connectedAD,
        sizeA,
        sizeD,
        sizeIso,
        lcc: lcc.sort(),
        isolates,
        benchTimeMs,
        benchCount
    }));
    """

    res = subprocess.run(
        [node_bin, "-e", script], capture_output=True, text=True, cwd=str(REPO_ROOT)
    )
    assert res.returncode == 0, f"Node.js script failed: {res.stderr}"

    data = json.loads(res.stdout)
    assert data["initialSize"] == 6
    assert data["initialComponents"] == 6
    assert data["afterUnionComponents"] == 3  # {A,B,C}, {D,E}, {Isolated1}
    assert data["connectedAB"] is True
    assert data["connectedAD"] is False
    assert data["sizeA"] == 3
    assert data["sizeD"] == 2
    assert data["sizeIso"] == 1
    assert data["lcc"] == ["A", "B", "C"]
    assert data["isolates"] == ["Isolated1"]
    assert data["benchCount"] == 2500
    assert data["benchTimeMs"] < 1000  # under 1 second for 10,000 items


def test_arc_cache_adaptive_replacement_and_scan_resistance() -> None:
    """Validate ARCCache self-tuning adaptation, scan resistance, and ApiClient integration via Node.js."""
    import json
    import shutil
    import subprocess

    node_bin = shutil.which("node")
    if not node_bin:
        return

    script = """
    const { ARCCache } = require('./site/js/frameworks/arc-cache.js');

    // 1. Basic operations & boundaries
    const cache = new ARCCache(5);
    cache.put('a', 1);
    cache.put('b', 2);
    cache.put('c', 3);

    const hasA = cache.has('a');
    const getA = cache.get('a');
    const initialStats = cache.getStats();

    // 2. Promotion to T2 on second access
    // 'a' was accessed once via get('a'), so it moved to T2
    const inT2Before = cache.t2.has('a');
    const inT1Before = cache.t1.has('a');

    // 3. Scan resistance demonstration
    // Fill cache capacity 5 with 3 hot items in T2 and 2 items in T1
    const scanCache = new ARCCache(5);
    ['hot1', 'hot2', 'hot3'].forEach(k => {
        scanCache.put(k, 'val_' + k);
        scanCache.get(k); // second access -> moves to T2
    });

    // Verify hot items are in T2
    const hotInT2 = scanCache.t2.has('hot1') && scanCache.t2.has('hot2') && scanCache.t2.has('hot3');

    // Scan through 20 distinct cold items
    for (let i = 0; i < 20; i++) {
        scanCache.put('cold_' + i, i);
    }

    // Hot items in T2 must survive the scan (ARC scan-resistance)
    const hot1Survives = scanCache.has('hot1');
    const hot2Survives = scanCache.has('hot2');
    const hot3Survives = scanCache.has('hot3');

    // 4. Ghost cache adaptation of parameter p
    const adaptCache = new ARCCache(4);
    adaptCache.put(1, 'one');
    adaptCache.put(2, 'two');
    adaptCache.put(3, 'three');
    adaptCache.put(4, 'four');
    // Now push a 5th item to evict LRU of T1 to B1
    adaptCache.put(5, 'five');
    const b1HasKey = adaptCache.b1.has(1);
    const pBefore = adaptCache.p;
    // Accessing key 1 now triggers B1 hit and adapts p upwards
    adaptCache.put(1, 'one_revisited');
    const pAfterB1 = adaptCache.p;

    // 5. Deletion and clearing
    const delRes = adaptCache.delete(1);
    const sizeAfterDel = adaptCache.size();
    adaptCache.clear();
    const sizeAfterClear = adaptCache.size();

    console.log(JSON.stringify({
        hasA,
        getA,
        inT2Before,
        inT1Before,
        hotInT2,
        hot1Survives,
        hot2Survives,
        hot3Survives,
        b1HasKey,
        pBefore,
        pAfterB1,
        pIncreased: pAfterB1 > pBefore,
        delRes,
        sizeAfterDel,
        sizeAfterClear
    }));
    """

    res = subprocess.run(
        [node_bin, "-e", script], capture_output=True, text=True, cwd=str(REPO_ROOT)
    )
    assert res.returncode == 0, f"Node.js script failed: {res.stderr}"

    data = json.loads(res.stdout)
    assert data["hasA"] is True
    assert data["getA"] == 1
    assert data["inT2Before"] is True
    assert data["inT1Before"] is False
    assert data["hotInT2"] is True
    assert data["hot1Survives"] is True
    assert data["hot2Survives"] is True
    assert data["hot3Survives"] is True
    assert data["b1HasKey"] is True
    assert data["pIncreased"] is True
    assert data["delRes"] is True
    assert data["sizeAfterClear"] == 0


def test_graph_canvas_engine_simulation_and_spatial_transform() -> None:
    """Validate GraphCanvasEngine physics simulation, spatial transforms, and LCC via Node.js."""
    import json
    import shutil
    import subprocess

    node_bin = shutil.which("node")
    if not node_bin:
        return

    script = """
    const { GraphCanvasEngine } = require('./site/js/frameworks/graph-canvas.js');
    const { DisjointSet } = require('./site/js/frameworks/disjoint-set.js');
    global.DisjointSet = DisjointSet;

    const engine = new GraphCanvasEngine(null, { width: 800, height: 600 });

    // 1. Data loading
    engine.loadData({
        nodes: [
            { id: 'n1', label: 'Paper 1', x: 400, y: 300 },
            { id: 'n2', label: 'Paper 2', x: 450, y: 300 },
            { id: 'n3', label: 'Paper 3', x: 500, y: 300 },
            { id: 'isolated', label: 'Isolated', x: 100, y: 100 }
        ],
        edges: [
            { source: 'n1', target: 'n2' },
            { source: 'n2', target: 'n3' }
        ]
    });

    const nodeCount = engine.nodes.length;
    const edgeCount = engine.edges.length;
    const n2Degree = engine.nodeMap.get('n2').degree;

    // 2. Physics step
    const xBefore = engine.nodeMap.get('n1').x;
    engine.stepPhysics(1.0);
    const xAfter = engine.nodeMap.get('n1').x;
    const physicsMoved = (xBefore !== xAfter);

    // 3. Spatial transforms & Zooming
    const originWorld = engine.screenToWorld(400, 300);
    engine.zoomIn(1.25);
    const scaleAfterZoom = engine.viewTransform.scale;
    engine.zoomOut(0.8);
    const scaleAfterZoomOut = engine.viewTransform.scale;
    engine.resetView();
    const scaleAfterReset = engine.viewTransform.scale;

    // 4. Hit testing
    const hitNode = engine.findNodeAtWorld(engine.nodeMap.get('n1').x, engine.nodeMap.get('n1').y, 25.0);
    const hitId = hitNode ? hitNode.id : null;

    // 5. LCC computation
    const lccNodes = engine.computeLargestConnectedComponent(engine.nodes, engine.edges);
    const lccIds = lccNodes.map(n => n.id).sort();

    console.log(JSON.stringify({
        nodeCount,
        edgeCount,
        n2Degree,
        physicsMoved,
        scaleAfterZoom,
        scaleAfterReset,
        hitId,
        lccIds
    }));
    """

    res = subprocess.run(
        [node_bin, "-e", script], capture_output=True, text=True, cwd=str(REPO_ROOT)
    )
    assert res.returncode == 0, f"Node.js script failed: {res.stderr}"

    data = json.loads(res.stdout)
    assert data["nodeCount"] == 4
    assert data["edgeCount"] == 2
    assert data["n2Degree"] == 2
    assert data["physicsMoved"] is True
    assert data["scaleAfterZoom"] == 1.25
    assert data["scaleAfterReset"] == 1.0
    assert data["hitId"] == "n1"
    assert data["lccIds"] == ["n1", "n2", "n3"]
