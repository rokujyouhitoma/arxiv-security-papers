#!/usr/bin/env python3
"""
CISA Known Exploited Vulnerabilities (KEV) Catalog Registry & Dynamic Correlator.
Provides ingestion, local catalog storage, memory caching, and offline fallback
for active in-the-wild exploitation evidence.
Zero External Dependencies, Pure Python.
"""

from __future__ import annotations

import json
import re
import urllib.parse
import urllib.request
from dataclasses import asdict, dataclass
from typing import Any, Dict, List, Optional

from .storage import CTICatalogStorage

# Official CISA KEV Catalog JSON Feed URL
CISA_KEV_FEED_URL = "https://www.cisa.gov/sites/default/files/feeds/known_exploited_vulnerabilities.json"

# SSRF Protection: Allowed hosts for external KEV feed acquisition
ALLOWED_FEED_HOSTS = frozenset(
    {"www.cisa.gov", "cisa.gov", "raw.githubusercontent.com", "github.com"}
)

# Deterministic CVE regex pattern
CVE_PATTERN = re.compile(r"\bCVE-(?:1999|20\d{2})-\d{4,7}\b", re.IGNORECASE)


@dataclass(frozen=True)
class KEVEntry:
    """Represents a single CISA Known Exploited Vulnerability record."""

    cve_id: str
    vendor_project: str
    product: str
    vulnerability_name: str
    date_added: str
    short_description: str = ""
    required_action: str = ""
    due_date: str = ""
    known_ransomware_campaign_use: str = "Unknown"
    notes: str = ""

    @property
    def is_ransomware_related(self) -> bool:
        """Returns True if confirmed use in ransomware campaigns."""
        return self.known_ransomware_campaign_use.strip().lower() == "known"

    def to_dict(self) -> Dict[str, Any]:
        """Converts entry into a serializable dictionary."""
        return asdict(self)


# Built-in offline fallback dataset for core high-profile CVEs
BUILTIN_KEV_FALLBACK: Dict[str, Dict[str, Any]] = {
    "CVE-2021-44228": {
        "cve_id": "CVE-2021-44228",
        "vendor_project": "Apache",
        "product": "Log4j",
        "vulnerability_name": "Apache Log4j Remote Code Execution Vulnerability",
        "date_added": "2021-12-10",
        "short_description": "Apache Log4j2 contains an uncontrolled JNDI lookup vulnerability.",
        "required_action": "Apply updates per vendor instructions.",
        "due_date": "2021-12-24",
        "known_ransomware_campaign_use": "Known",
        "notes": "https://nvd.nist.gov/vuln/detail/CVE-2021-44228",
    },
    "CVE-2017-0144": {
        "cve_id": "CVE-2017-0144",
        "vendor_project": "Microsoft",
        "product": "Windows SMBv1",
        "vulnerability_name": "Microsoft SMBv1 Remote Code Execution (EternalBlue)",
        "date_added": "2022-02-15",
        "short_description": "Remote code execution in SMBv1 (exploited in WannaCry / NotPetya).",
        "required_action": "Apply Microsoft patch MS17-010 or disable SMBv1.",
        "due_date": "2022-03-01",
        "known_ransomware_campaign_use": "Known",
        "notes": "https://www.cisa.gov/news-events/alerts/2017/05/12/wannacry-ransomware",
    },
    "CVE-2021-27101": {
        "cve_id": "CVE-2021-27101",
        "vendor_project": "Accellion",
        "product": "FTA",
        "vulnerability_name": "Accellion FTA SQL Injection Vulnerability",
        "date_added": "2021-11-03",
        "short_description": "Accellion FTA SQL Injection leading to remote code execution.",
        "required_action": "Retire legacy FTA systems or upgrade to supported platforms.",
        "due_date": "2021-11-17",
        "known_ransomware_campaign_use": "Known",
        "notes": "Accellion File Transfer Appliance (FTA) compromise.",
    },
    "CVE-2020-1472": {
        "cve_id": "CVE-2020-1472",
        "vendor_project": "Microsoft",
        "product": "Netlogon",
        "vulnerability_name": "Microsoft Netlogon Privilege Escalation (ZeroLogon)",
        "date_added": "2021-11-03",
        "short_description": "Elevation of privilege vulnerability when using Netlogon Remote Protocol.",
        "required_action": "Apply security updates per Microsoft guidance.",
        "due_date": "2020-09-21",
        "known_ransomware_campaign_use": "Known",
        "notes": "https://msrc.microsoft.com/update-guide/vulnerability/CVE-2020-1472",
    },
    "CVE-2021-34527": {
        "cve_id": "CVE-2021-34527",
        "vendor_project": "Microsoft",
        "product": "Windows Print Spooler",
        "vulnerability_name": "Microsoft Windows Print Spooler Remote Code Execution (PrintNightmare)",
        "date_added": "2021-11-03",
        "short_description": (
            "Remote code execution when Windows Print Spooler improperly performs privileged file operations."
        ),
        "required_action": "Apply vendor patches or stop Print Spooler service.",
        "due_date": "2021-07-20",
        "known_ransomware_campaign_use": "Known",
        "notes": "https://msrc.microsoft.com/update-guide/vulnerability/CVE-2021-34527",
    },
    "CVE-2022-22965": {
        "cve_id": "CVE-2022-22965",
        "vendor_project": "VMware",
        "product": "Spring Framework",
        "vulnerability_name": "Spring Framework Remote Code Execution (Spring4Shell)",
        "date_added": "2022-04-04",
        "short_description": (
            "A Spring MVC or Spring WebFlux application running on JDK 9+ may be vulnerable to RCE via data binding."
        ),
        "required_action": "Apply updates per vendor instructions.",
        "due_date": "2022-04-25",
        "known_ransomware_campaign_use": "Known",
        "notes": "https://spring.io/blog/2022/03/31/spring-framework-rce-early-announcement",
    },
}


class CISAKEVRegistry:
    """
    Unified query interface and synchronization coordinator for CISA KEV catalog.
    Features:
    - Multi-tiered lookup: In-memory cache -> SQLite storage -> Built-in offline fallback.
    - SSRF-protected streaming acquisition with zero external dependencies.
    """

    def __init__(
        self,
        storage: Optional[CTICatalogStorage] = None,
        auto_seed: bool = True,
    ) -> None:
        self.storage = storage or CTICatalogStorage()
        self._cache: Dict[str, Optional[KEVEntry]] = {}
        if auto_seed and self.storage.get_cisa_kev_count() == 0:
            self._seed_builtin_records()

    def _seed_builtin_records(self) -> None:
        """Seeds the local SQLite storage with core built-in records."""
        items = list(BUILTIN_KEV_FALLBACK.values())
        self.storage.upsert_cisa_kev_vulnerabilities(items)

    @staticmethod
    def validate_feed_url(url: str) -> bool:
        """Validates that feed URL uses HTTPS and belongs to allowed whitelist domains."""
        parsed = urllib.parse.urlparse(url)
        if parsed.scheme != "https":
            return False
        hostname = (parsed.hostname or "").lower()
        return hostname in ALLOWED_FEED_HOSTS

    def _map_raw_vulnerabilities(
        self, raw_vulns: List[Dict[str, Any]]
    ) -> List[Dict[str, Any]]:
        """Maps raw CISA JSON vulnerability dictionaries into standardized schema."""
        mapped: List[Dict[str, Any]] = []
        for v in raw_vulns:
            cve_id = v.get("cveID", "").strip().upper()
            if not cve_id:
                continue
            mapped.append(
                {
                    "cve_id": cve_id,
                    "vendor_project": v.get("vendorProject", ""),
                    "product": v.get("product", ""),
                    "vulnerability_name": v.get("vulnerabilityName", ""),
                    "date_added": v.get("dateAdded", ""),
                    "short_description": v.get("shortDescription", ""),
                    "required_action": v.get("requiredAction", ""),
                    "due_date": v.get("dueDate", ""),
                    "known_ransomware_campaign_use": v.get(
                        "knownRansomwareCampaignUse", "Unknown"
                    ),
                    "notes": v.get("notes", ""),
                }
            )
        return mapped

    def sync_from_feed(
        self,
        feed_url: Optional[str] = None,
        timeout: float = 15.0,
    ) -> int:
        """
        Fetches and synchronizes KEV vulnerabilities from external CISA feed.
        Returns the number of ingested vulnerability entries.
        """
        target_url = feed_url or CISA_KEV_FEED_URL
        if not self.validate_feed_url(target_url):
            raise ValueError(
                f"SSRF violation: Host not allowed for KEV feed: {target_url}"
            )

        req = urllib.request.Request(
            target_url,
            headers={"User-Agent": "arxiv-security-papers-kev-sync/1.0"},
        )
        with urllib.request.urlopen(req, timeout=timeout) as response:
            payload = json.loads(response.read().decode("utf-8"))

        raw_vulns = payload.get("vulnerabilities", [])
        if not isinstance(raw_vulns, list):
            return 0

        mapped_entries = self._map_raw_vulnerabilities(raw_vulns)
        count = self.storage.upsert_cisa_kev_vulnerabilities(mapped_entries)
        self._cache.clear()
        return count

    def lookup(self, cve_id: str) -> Optional[KEVEntry]:
        """
        Multi-tier lookup for a CVE ID.
        Checks in-memory cache, then SQLite storage, then built-in fallback dictionary.
        """
        clean_cve = cve_id.strip().upper()
        if not clean_cve:
            return None

        if clean_cve in self._cache:
            return self._cache[clean_cve]

        # 1. SQLite storage lookup
        stored = self.storage.get_cisa_kev_vulnerability(clean_cve)
        if stored:
            entry = self._dict_to_entry(stored)
            self._cache[clean_cve] = entry
            return entry

        # 2. Builtin fallback
        if clean_cve in BUILTIN_KEV_FALLBACK:
            entry = self._dict_to_entry(BUILTIN_KEV_FALLBACK[clean_cve])
            self._cache[clean_cve] = entry
            return entry

        self._cache[clean_cve] = None
        return None

    def _fallback_entries(self, limit: int) -> List[KEVEntry]:
        """Provides builtin fallback entries when storage is empty."""
        return [self._dict_to_entry(v) for v in BUILTIN_KEV_FALLBACK.values()][:limit]

    def search(
        self,
        query: str = "",
        ransomware_only: bool = False,
        limit: int = 50,
    ) -> List[KEVEntry]:
        """Searches KEV catalog by query term and/or ransomware flag."""
        records = self.storage.search_cisa_kev_vulnerabilities(
            query=query, ransomware_only=ransomware_only, limit=limit
        )
        if records:
            return [self._dict_to_entry(r) for r in records]
        if not (query or ransomware_only):
            return self._fallback_entries(limit)
        return []

    def get_known_ransomware_cves(self) -> List[str]:
        """Returns list of CVE IDs confirmed in ransomware campaigns."""
        entries = self.search(ransomware_only=True, limit=5000)
        return [e.cve_id for e in entries]

    def get_stats(self) -> Dict[str, Any]:
        """Returns statistical metrics of local KEV catalog."""
        total = self.storage.get_cisa_kev_count()
        ransomware = len(self.get_known_ransomware_cves())
        return {
            "total_kev_vulnerabilities": total,
            "ransomware_associated_count": ransomware,
            "offline_builtin_count": len(BUILTIN_KEV_FALLBACK),
        }

    @staticmethod
    def _dict_to_entry(data: Dict[str, Any]) -> KEVEntry:
        """Converts raw dictionary to typed KEVEntry."""
        return KEVEntry(
            cve_id=data["cve_id"],
            vendor_project=data.get("vendor_project", ""),
            product=data.get("product", ""),
            vulnerability_name=data.get("vulnerability_name", ""),
            date_added=data.get("date_added", ""),
            short_description=data.get("short_description", ""),
            required_action=data.get("required_action", ""),
            due_date=data.get("due_date", ""),
            known_ransomware_campaign_use=data.get(
                "known_ransomware_campaign_use", "Unknown"
            ),
            notes=data.get("notes", ""),
        )
