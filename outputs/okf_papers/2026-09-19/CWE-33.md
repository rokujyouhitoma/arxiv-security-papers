---
type: "weakness"
title: "[CWE-33] Path Traversal: '....' (Multiple Dot)"
description: "The product uses external input to construct a pathname that should be within a restricted directory, but it does not pr"
resource: "https://cwe.mitre.org/data/definitions/33.html"
tags: ["weakness", "mitre-cwe", "cwe-33"]
timestamp: "2026-09-19T03:07:04.746898+00:00"
provenance:
  origin: "cwe.mitre.org"
  clean_id: "CWE-33"
  published: "2026-09-19"
  authors: ["MITRE CWE"]
trust:
  attestation_status: "verified"
  digital_signature: "antigravity-spider-v1"
---

# [CWE-33] Path Traversal: '....' (Multiple Dot)

## 1. 弱点概要 (Overview)
The product uses external input to construct a pathname that should be within a restricted directory, but it does not properly neutralize '....' (multiple dot) sequences that can resolve to a location that is outside of that directory.

## 2. 対策・緩和策 (Mitigations)
- 公式リファレンスおよび CWE 推奨の防御策を適用してください。

## 3. 一次ソースリンク
- [https://cwe.mitre.org/data/definitions/33.html](https://cwe.mitre.org/data/definitions/33.html)
