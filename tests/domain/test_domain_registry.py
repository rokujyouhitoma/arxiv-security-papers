"""
Unit tests for Domain Registry and Domain Plugin SPI architecture (Issue 105).
"""

from domain.registry import BaseDomainPlugin, DomainRegistry, get_domain_registry
from domain.security.plugin import SecurityPapersDomainPlugin


class CustomMockDomainPlugin(BaseDomainPlugin):
    @property
    def domain_id(self) -> str:
        return "mock_domain"

    @property
    def display_name(self) -> str:
        return "Mock Domain"

    def get_supported_categories(self) -> list[str]:
        return ["mock.CAT"]


def test_domain_registry_lifecycle():
    registry = DomainRegistry()
    assert len(registry.list_domains()) == 0

    plugin = CustomMockDomainPlugin()
    registry.register(plugin)

    assert registry.list_domains() == ["mock_domain"]
    assert registry.get("mock_domain") == plugin
    assert len(registry.get_all()) == 1
    assert plugin.get_supported_categories() == ["mock.CAT"]

    registry.unregister("mock_domain")
    assert registry.get("mock_domain") is None
    assert len(registry.list_domains()) == 0


def test_builtin_security_domain_plugin():
    reg = get_domain_registry()
    security_plugin = reg.get("security")
    assert security_plugin is not None
    assert isinstance(security_plugin, SecurityPapersDomainPlugin)
    assert security_plugin.domain_id == "security"
    assert "cs.CR" in security_plugin.get_supported_categories()
    spiders = security_plugin.get_spiders()
    assert "arxiv_spider" in spiders
    assert "iacr_spider" in spiders
