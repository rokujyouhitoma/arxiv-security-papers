#!/usr/bin/env python3
"""
Zero-Dependency Deterministic Text Embedding & Vector Normalization Helper.
Projects natural language text (abstracts, titles, queries) into fixed D-dimensional
Float32 unit vectors using character n-grams and hashing without external ML models.
"""

import hashlib
import math
import re
from typing import List, Sequence, Tuple


class DeterministicEmbedding:
    """
    Zero-dependency deterministic text embedder and vector normalizer.
    Generates normalized Float32 unit vectors for ANN vector indexing.
    """

    def __init__(self, dim: int = 128) -> None:
        self.dim = dim

    def normalize(self, vector: Sequence[float]) -> Tuple[float, ...]:
        """L2 normalizes a vector into a unit vector (norm = 1.0)."""
        norm_sq = sum(x * x for x in vector)
        if norm_sq <= 0.0:
            return tuple(0.0 for _ in range(len(vector)))
        norm = math.sqrt(norm_sq)
        return tuple(x / norm for x in vector)

    def embed_text(self, text: str) -> Tuple[float, ...]:
        """
        Embeds a text string into a normalized D-dimensional float vector.
        Uses multi-scale feature hashing (tokens + character 3-grams).
        """
        if not text:
            return tuple(0.0 for _ in range(self.dim))

        vec = [0.0] * self.dim
        clean = text.lower().strip()
        tokens = re.findall(r"[a-z0-9_\-\.\u3040-\u30ff\u4e00-\u9faf]+", clean)

        for token in tokens:
            h = int(hashlib.sha256(token.encode("utf-8")).hexdigest()[:16], 16)
            idx = h % self.dim
            sign = 1.0 if ((h >> 8) & 1) == 0 else -1.0
            vec[idx] += sign * (1.0 + math.log(1.0 + len(token)))

        for i in range(len(clean) - 2):
            trigram = clean[i : i + 3]
            h = int(hashlib.sha256(trigram.encode("utf-8")).hexdigest()[:8], 16)
            idx = h % self.dim
            sign = 1.0 if ((h >> 4) & 1) == 0 else -1.0
            vec[idx] += sign * 0.5

        return self.normalize(vec)

    def batch_embed(self, texts: Sequence[str]) -> List[Tuple[float, ...]]:
        """Embeds a list of texts in batch."""
        return [self.embed_text(t) for t in texts]
