"""
Pre-Aggregated Analytics Engine and High-Speed Storage Subsystem.
Provides batch pre-calculation for strategic KPIs, threat trends, and O(1) serving.
"""

from .aggregator import AnalyticsAggregator
from .storage import AnalyticsStorage

__all__ = ["AnalyticsAggregator", "AnalyticsStorage"]
