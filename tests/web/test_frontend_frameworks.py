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
    "dom-utils.js",
    "event.js",
    "locator.js",
    "publisher.js",
    "router.js",
    "scene.js",
    "scheduler.js",
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
    """site/app-min.js must contain definitions for the compiled framework classes."""
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
    ]
    for sym in core_framework_symbols:
        assert sym in content, f"Symbol {sym} not found in compiled {APP_MIN_JS.name}"
