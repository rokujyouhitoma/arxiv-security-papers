#!/usr/bin/env python3
"""
Security Papers Domain Plugin Implementation.
Integrates Security Ontology, Intelligence Requirements (PIR), Threat Models, and Crawlers.
"""

from __future__ import annotations

import logging
from typing import Any, Dict, List, Optional

from domain.registry import BaseDomainPlugin
from spider.registry import get_spider_registry

logger = logging.getLogger(__name__)


class SecurityPapersDomainPlugin(BaseDomainPlugin):
    """
    Domain plugin for arXiv & IACR Security and Cryptography Papers.
    """

    @property
    def domain_id(self) -> str:
        return "security"

    @property
    def display_name(self) -> str:
        return "Cybersecurity & Information Security"

    @property
    def description(self) -> str:
        return "arXiv cs.CR, IACR Cryptology, and Cybersecurity Vulnerability Intelligence Domain."

    def get_supported_categories(self) -> List[str]:
        return ["cs.CR", "cs.SE", "cs.NI", "cs.AI", "cs.CY"]

    def get_spiders(self) -> Dict[str, Any]:
        from domain.security.spiders.advisory_spider import AdvisorySpider
        from domain.security.spiders.arxiv_spider import ArxivSpider
        from domain.security.spiders.cisa_kev_spider import CisaKevSpider
        from domain.security.spiders.cwe_spider import CweSpider
        from domain.security.spiders.iacr_spider import IacrSpider
        from domain.security.spiders.nvd_cve_spider import NvdCveSpider

        return {
            "arxiv_spider": ArxivSpider,
            "iacr_spider": IacrSpider,
            "advisory_spider": AdvisorySpider,
            "cisa_kev_spider": CisaKevSpider,
            "nvd_cve_spider": NvdCveSpider,
            "cwe_spider": CweSpider,
        }

    def get_pipelines(self) -> Dict[str, Any]:
        from domain.security.pipeline.okf_pipeline import SecurityOkfItemPipeline

        return {
            "okf": SecurityOkfItemPipeline,
            "security_okf": SecurityOkfItemPipeline,
        }

    def get_ontology_schema(self) -> Optional[Any]:
        try:
            from ontology.schema import SecurityOntologySchema

            return SecurityOntologySchema
        except Exception:
            return None

    def get_cti_registry(self) -> Any:
        """Returns MITRE ATT&CK CTI Registry instance for this domain."""
        from domain.security.cti.registry import MITRECTIRegistry

        return MITRECTIRegistry.get_instance()

    def initialize(self, workspace_dir: str) -> None:
        """Registers domain spiders and pipelines into global registries."""
        spider_reg = get_spider_registry()
        for name, spider_cls in self.get_spiders().items():
            spider_reg.register(name, spider_cls=spider_cls)

        try:
            from spider.pipeline.base import get_pipeline_registry

            pipe_reg = get_pipeline_registry()
            for name, pipe_cls in self.get_pipelines().items():
                pipe_reg.register(name, pipeline_cls=pipe_cls)
        except Exception as exc:
            logger.debug("Pipeline registration deferred: %s", exc)

        logger.info(
            "Initialized SecurityPapersDomainPlugin in workspace: %s", workspace_dir
        )


def create_security_plugin() -> SecurityPapersDomainPlugin:
    """Factory function for SecurityPapersDomainPlugin."""
    return SecurityPapersDomainPlugin()
