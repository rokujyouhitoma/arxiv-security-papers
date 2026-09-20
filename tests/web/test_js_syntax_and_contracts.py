"""
tests/web/test_js_syntax_and_contracts.py

Issue #359 (Pillar 4): Pure Python (pytest / unittest) headless test suite
for frontend JavaScript syntax, strict mode compliance, global namespace
hygiene, Closure Compiler externs contracts, and build manifest integrity.

Zero external dependencies: runs completely in pure Python without Node.js,
npm packages, or headless browser drivers.
"""

from __future__ import annotations

import re
import unittest
from pathlib import Path
from typing import Dict, List, Set

_ROOT = Path(__file__).resolve().parent.parent.parent
_SITE = _ROOT / "site"
_FRAMEWORKS = _SITE / "js" / "frameworks"
_JS_DIR = _SITE / "js"


def _strip_comments_and_strings(code: str) -> str:
    """Accurately removes comments, strings, template literals, and regex literals from JS."""
    out: List[str] = []
    i = 0
    n = len(code)
    last_non_ws = ""

    while i < n:
        c = code[i]

        # Check single-line comment
        if code[i : i + 2] == "//":
            i += 2
            while i < n and code[i] != "\n":
                i += 1
            continue

        # Check multi-line comment
        if code[i : i + 2] == "/*":
            i += 2
            while i < n and code[i : i + 2] != "*/":
                if code[i] == "\n":
                    out.append("\n")
                i += 1
            i += 2
            continue

        # Check regex literal vs division
        if c == "/" and (last_non_ws in "(=:[{;,!&|?~+*-" or last_non_ws == ""):
            i += 1
            in_class = False
            while i < n:
                if code[i] == "\\":
                    i += 2
                    continue
                if code[i] == "[":
                    in_class = True
                elif code[i] == "]":
                    in_class = False
                elif code[i] == "/" and not in_class:
                    i += 1
                    while i < n and code[i] in "gimsuvy":
                        i += 1
                    break
                if code[i] == "\n":
                    out.append("\n")
                i += 1
            last_non_ws = ")"
            continue

        # Check string / template literals
        if c in ("'", '"', "`"):
            quote = c
            i += 1
            while i < n:
                if code[i] == "\\":
                    i += 2
                    continue
                if code[i] == quote:
                    i += 1
                    break
                if code[i] == "\n":
                    out.append("\n")
                i += 1
            last_non_ws = quote
            continue

        out.append(c)
        if not c.isspace():
            last_non_ws = c
        i += 1

    return "".join(out)


class TestJsSyntaxAndContracts(unittest.TestCase):
    """Headless pure-Python static verification suite for frontend JS integrity."""

    def setUp(self) -> None:
        self.all_framework_files: List[Path] = sorted(list(_FRAMEWORKS.glob("*.js")))
        self.modular_js_files: List[Path] = sorted(
            [f for f in _JS_DIR.glob("*.js") if f.is_file()]
        )
        self.app_js: Path = _SITE / "app.js"
        self.dashboard_js: Path = _JS_DIR / "dashboard.js"
        self.externs_file: Path = _SITE / "externs.js"
        self.compile_script: Path = _ROOT / "scripts" / "compile_frontend.py"

    # ----------------------------------------------------------------------
    # 1. Strict Mode Verification
    # ----------------------------------------------------------------------
    def test_all_js_files_declare_use_strict(self) -> None:
        """Every JS module, app.js, and dashboard.js must declare 'use strict';."""
        targets: List[Path] = (
            [self.app_js, self.dashboard_js]
            + self.modular_js_files
            + self.all_framework_files
        )
        # Exclude minified bundles
        targets = [
            f
            for f in targets
            if not f.name.endswith("-min.js") and f.name != "externs.js"
        ]

        missing_strict: List[str] = []
        for file_path in targets:
            content = file_path.read_text(encoding="utf-8")
            # Strict mode must be declared either as 'use strict'; or "use strict";
            if "'use strict'" not in content and '"use strict"' not in content:
                missing_strict.append(str(file_path.relative_to(_ROOT)))

        self.assertEqual(
            missing_strict,
            [],
            f"The following JavaScript files are missing strict mode declaration: {missing_strict}",
        )

    # ----------------------------------------------------------------------
    # 2. Namespace & Global Scope Encapsulation
    # ----------------------------------------------------------------------
    def test_framework_modules_are_iife_encapsulated(self) -> None:
        """All 19 framework modules must be wrapped in IIFE to prevent window pollution."""
        self.assertEqual(
            len(self.all_framework_files),
            19,
            f"Expected 19 framework modules in {_FRAMEWORKS}, found {len(self.all_framework_files)}",
        )

        unwrapped: List[str] = []
        for file_path in self.all_framework_files:
            content = file_path.read_text(encoding="utf-8")
            # Must start with IIFE pattern (e.g. (function() { or (function(global) {)
            has_iife_start = bool(
                re.search(r"^\s*\(\s*function\s*\(", content, re.MULTILINE)
            )
            has_iife_end = bool(
                re.search(r"\)\s*\(\s*(?:window)?\s*\)\s*;?\s*$", content.strip())
            )
            if not (has_iife_start and has_iife_end):
                unwrapped.append(str(file_path.relative_to(_ROOT)))

        self.assertEqual(
            unwrapped,
            [],
            f"Framework modules must be wrapped in IIFEs: {unwrapped}",
        )

    def test_framework_modules_export_to_application_namespace(self) -> None:
        """Every framework module must export its symbol(s) to window.Application / Application.frameworks."""
        non_compliant: List[str] = []
        for file_path in self.all_framework_files:
            content = file_path.read_text(encoding="utf-8")
            has_app_export = "Application" in content and (
                "Application.frameworks" in content
                or "Application['frameworks']" in content
            )
            if not has_app_export:
                non_compliant.append(str(file_path.relative_to(_ROOT)))

        self.assertEqual(
            non_compliant,
            [],
            f"Framework modules must export to Application.frameworks: {non_compliant}",
        )

    # ----------------------------------------------------------------------
    # 3. Structural Syntax Hygiene & Forbidden Tokens
    # ----------------------------------------------------------------------
    def test_js_structural_syntax_hygiene_and_bracket_balance(self) -> None:
        """Verify bracket nesting balance and absence of forbidden syntax."""
        targets: List[Path] = (
            [self.app_js, self.dashboard_js]
            + self.modular_js_files
            + self.all_framework_files
        )
        targets = [
            f
            for f in targets
            if not f.name.endswith("-min.js") and f.name != "externs.js"
        ]

        forbidden_keywords = ["debugger;", "alert("]
        forbidden_esm = [
            "export default",
            "export const",
            "export function",
            "export class",
        ]

        for file_path in targets:
            rel_name = str(file_path.relative_to(_ROOT))
            raw_content = file_path.read_text(encoding="utf-8")
            sanitized = _strip_comments_and_strings(raw_content)

            # 1. Balanced braces {}
            open_braces = sanitized.count("{")
            close_braces = sanitized.count("}")
            self.assertEqual(
                open_braces,
                close_braces,
                f"Mismatched curly braces in {rel_name}: open={open_braces}, close={close_braces}",
            )

            # 2. Balanced parentheses ()
            open_parens = sanitized.count("(")
            close_parens = sanitized.count(")")
            self.assertEqual(
                open_parens,
                close_parens,
                f"Mismatched parentheses in {rel_name}: open={open_parens}, close={close_parens}",
            )

            # 3. Balanced brackets []
            open_brackets = sanitized.count("[")
            close_brackets = sanitized.count("]")
            self.assertEqual(
                open_brackets,
                close_brackets,
                f"Mismatched square brackets in {rel_name}: open={open_brackets}, close={close_brackets}",
            )

            # 4. Check forbidden keywords
            for kw in forbidden_keywords:
                self.assertNotIn(
                    kw,
                    sanitized,
                    f"Forbidden keyword '{kw}' found in {rel_name}",
                )

            # 5. Check forbidden ESM export keywords that break raw bundle concatenation
            for esm_kw in forbidden_esm:
                self.assertNotIn(
                    esm_kw,
                    sanitized,
                    f"Forbidden ESM syntax '{esm_kw}' found in {rel_name} (must use CommonJS / window export)",
                )

    # ----------------------------------------------------------------------
    # 4. Closure Externs and Implementation Contracts
    # ----------------------------------------------------------------------
    def test_externs_and_implementation_contracts(self) -> None:
        """Public methods declared in site/externs.js must exist in framework implementations."""
        self.assertTrue(self.externs_file.is_file(), "site/externs.js is missing")
        externs_content = self.externs_file.read_text(encoding="utf-8")

        # Map interface names to their implementation file names
        interface_to_file: Dict[str, str] = {
            "YuzoraEventTargetInterface": "event.js",
            "LocatorInterface": "locator.js",
            "PublisherInterface": "publisher.js",
            "RouterInterface": "router.js",
            "SceneInterface": "scene.js",
            "SceneDirectorInterface": "scene.js",
            "ApiClientInterface": "api-client.js",
            "StateStoreInterface": "store.js",
            "SSEStreamManagerInterface": "sse-manager.js",
            "ModalControllerInterface": "modal.js",
            "RadixTrieInterface": "radix-trie.js",
            "QueryValidatorInterface": "query-validator.js",
            "HierarchicalStateMachineInterface": "hsm.js",
            "DisjointSetInterface": "disjoint-set.js",
            "ARCCacheInterface": "arc-cache.js",
            "GraphCanvasEngineInterface": "graph-canvas.js",
        }

        # Extract interface methods from externs.js
        # Pattern: InterfaceName.prototype.methodName = function
        method_pattern = re.compile(r"([A-Za-z0-9_]+)\.prototype\.([A-Za-z0-9_]+)\s*=")
        interface_methods: Dict[str, Set[str]] = {}
        for match in method_pattern.finditer(externs_content):
            iface, method = match.group(1), match.group(2)
            if iface in interface_to_file:
                interface_methods.setdefault(iface, set()).add(method)

        self.assertGreater(
            len(interface_methods),
            10,
            "Expected at least 10 interfaces with methods in site/externs.js",
        )

        # For each interface, verify its implementation file defines the methods
        missing_contracts: Dict[str, List[str]] = {}
        for iface, methods in interface_methods.items():
            mod_file = _FRAMEWORKS / interface_to_file[iface]
            self.assertTrue(
                mod_file.is_file(),
                f"Implementation file {mod_file} for {iface} does not exist",
            )
            mod_content = mod_file.read_text(encoding="utf-8")

            missing: List[str] = []
            for method in sorted(list(methods)):
                # Match method declaration in class or prototype
                # e.g.: methodName( ... ) {  OR  .methodName = function  OR  .prototype['methodName']
                pattern = rf"(?:(?:(?:async\s+)?{method}\s*\()|(?:\.{method}\s*=)|(?:\['{method}'\]\s*=))"
                if not re.search(pattern, mod_content):
                    missing.append(method)

            if missing:
                missing_contracts[f"{iface} ({interface_to_file[iface]})"] = missing

        self.assertEqual(
            missing_contracts,
            {},
            f"Interface methods declared in externs.js but missing in implementation: {missing_contracts}",
        )

    # ----------------------------------------------------------------------
    # 5. Build Manifest File Existence
    # ----------------------------------------------------------------------
    def test_build_manifest_file_existence(self) -> None:
        """Every file referenced in scripts/compile_frontend.py manifests must exist and be non-empty."""
        self.assertTrue(
            self.compile_script.is_file(),
            f"Compile script not found: {self.compile_script}",
        )
        content = self.compile_script.read_text(encoding="utf-8")

        # Extract file paths from FRAMEWORK_SRCS, APP_SRCS, and DASHBOARD_SRCS
        src_pattern = re.compile(r'"(site/[^"]+\.js)"')
        referenced_sources = set(src_pattern.findall(content))

        self.assertGreater(
            len(referenced_sources),
            20,
            "Build manifest in compile_frontend.py should declare over 20 source files",
        )

        missing_or_empty: List[str] = []
        for rel_path in sorted(list(referenced_sources)):
            full_path = _ROOT / rel_path
            if not full_path.is_file():
                missing_or_empty.append(f"{rel_path} (missing)")
            elif full_path.stat().st_size < 100:
                missing_or_empty.append(
                    f"{rel_path} (too small: {full_path.stat().st_size} bytes)"
                )

        self.assertEqual(
            missing_or_empty,
            [],
            f"Build manifest sources have issues: {missing_or_empty}",
        )


if __name__ == "__main__":
    unittest.main()
