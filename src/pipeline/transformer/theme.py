#!/usr/bin/env python3
"""
Theme and Taxonomy Configuration Engine.
Manages multi-domain intelligence themes, query rules, and taxonomy bindings.
"""

import json
import os
from dataclasses import dataclass, field
from typing import Any, Dict, List, Optional


@dataclass
class SourceConfig:
    """Configuration for a single data source within a theme."""

    adapter: str
    query: str = ""
    category: str = ""
    feed_url: str = ""
    max_results: int = 100
    extra_params: Dict[str, Any] = field(default_factory=dict)


@dataclass
class ThemeConfig:
    """Definition of an intelligence theme / analysis domain."""

    theme_id: str
    name: str
    description: str
    sources: List[SourceConfig] = field(default_factory=list)
    keywords: List[str] = field(default_factory=list)
    taxonomies: List[str] = field(default_factory=list)
    output_dir: Optional[str] = None
    default_audience: str = "all"

    def get_output_root(self, base_outputs_dir: str = "outputs") -> str:
        """Determines the output directory for this theme."""
        if self.theme_id == "security":
            # Maintain 100% backward compatibility for default security theme
            return base_outputs_dir
        if self.output_dir:
            return self.output_dir
        return os.path.join(base_outputs_dir, "themes", self.theme_id)


class ThemeManager:
    """Manager for loading, validating, and retrieving intelligence themes."""

    def __init__(self) -> None:
        self._themes: Dict[str, ThemeConfig] = {}
        self._register_builtins()

    def _register_builtins(self) -> None:
        """Registers built-in default themes."""
        # 1. Security Theme (Default)
        self.register(
            ThemeConfig(
                theme_id="security",
                name="Cybersecurity & Information Security",
                description="Information security, cryptography, systems safety, network defenses.",
                sources=[
                    SourceConfig(
                        adapter="arxiv",
                        query="cat:cs.CR",
                        category="cs.CR",
                        max_results=100,
                    ),
                    SourceConfig(adapter="iacr_eprint", max_results=20),
                ],
                keywords=[
                    "vulnerability",
                    "exploit",
                    "cryptography",
                    "zero-trust",
                    "malware",
                    "ransomware",
                    "side-channel",
                    "fuzzing",
                    "authentication",
                ],
                taxonomies=["mitre_attack", "stride", "cwe"],
                output_dir="outputs",
            )
        )

        # 2. AI Safety & LLM Security Theme
        self.register(
            ThemeConfig(
                theme_id="ai_safety",
                name="AI Safety & Adversarial Machine Learning",
                description="Adversarial ML, prompt injection, jailbreaks, model alignment, LLM defenses.",
                sources=[
                    SourceConfig(
                        adapter="arxiv",
                        query="cat:cs.AI OR cat:cs.LG OR cat:stat.ML",
                        category="cs.AI",
                        max_results=50,
                    ),
                ],
                keywords=[
                    "jailbreak",
                    "prompt injection",
                    "adversarial attack",
                    "guardrail",
                    "backdoor",
                    "watermarking",
                    "unlearning",
                    "alignment",
                    "safety",
                ],
                taxonomies=["owasp_llm_top10", "mitre_atlas"],
            )
        )

        # 3. Software Engineering & Code Security Theme
        self.register(
            ThemeConfig(
                theme_id="software_engineering",
                name="Software Engineering & Static Analysis",
                description="Code security, vulnerability detection, automated program repair, verification.",
                sources=[
                    SourceConfig(
                        adapter="arxiv",
                        query="cat:cs.SE",
                        category="cs.SE",
                        max_results=50,
                    ),
                ],
                keywords=[
                    "static analysis",
                    "program repair",
                    "symbolic execution",
                    "vulnerability detection",
                    "code review",
                    "formal verification",
                    "fuzz testing",
                ],
                taxonomies=["cwe", "owasp_top10"],
            )
        )

    def register(self, theme: ThemeConfig) -> None:
        """Registers a theme configuration."""
        self._themes[theme.theme_id] = theme

    def get(self, theme_id: str) -> Optional[ThemeConfig]:
        """Retrieves a theme configuration by ID."""
        return self._themes.get(theme_id)

    def list_theme_ids(self) -> List[str]:
        """Lists all registered theme IDs."""
        return sorted(list(self._themes.keys()))

    def load_from_json_file(self, file_path: str) -> Optional[ThemeConfig]:
        """Loads and registers a custom theme from a JSON file."""
        if not os.path.exists(file_path):
            return None
        with open(file_path, "r", encoding="utf-8") as f:
            data = json.load(f)

        sources = [
            SourceConfig(
                adapter=s.get("adapter", "arxiv"),
                query=s.get("query", ""),
                category=s.get("category", ""),
                feed_url=s.get("feed_url", ""),
                max_results=s.get("max_results", 50),
                extra_params=s.get("extra_params", {}),
            )
            for s in data.get("sources", [])
        ]

        theme = ThemeConfig(
            theme_id=data.get("theme_id", "custom"),
            name=data.get("name", "Custom Theme"),
            description=data.get("description", ""),
            sources=sources,
            keywords=data.get("keywords", []),
            taxonomies=data.get("taxonomies", []),
            output_dir=data.get("output_dir"),
            default_audience=data.get("default_audience", "all"),
        )
        self.register(theme)
        return theme


# Default singleton
_GLOBAL_THEME_MANAGER: Optional[ThemeManager] = None


def get_theme_manager() -> ThemeManager:
    """Returns the global ThemeManager singleton."""
    global _GLOBAL_THEME_MANAGER
    if _GLOBAL_THEME_MANAGER is None:
        _GLOBAL_THEME_MANAGER = ThemeManager()
    return _GLOBAL_THEME_MANAGER
