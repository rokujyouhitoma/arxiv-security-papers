---
type: "weakness"
title: "[CWE-34] Path Traversal: '....//'"
description: "The product uses external input to construct a pathname that should be within a restricted directory, but it does not pr"
resource: "https://cwe.mitre.org/data/definitions/34.html"
tags: ["weakness", "mitre-cwe", "cwe-34"]
timestamp: "2026-09-19T07:17:08.583574+00:00"
provenance:
  origin: "cwe.mitre.org"
  clean_id: "CWE-34"
  published: "2026-09-19"
  authors: ["MITRE CWE"]
trust:
  attestation_status: "verified"
  digital_signature: "antigravity-spider-v1"
---

# [CWE-34] Path Traversal: '....//'

## 1. 弱点概要 (Overview)
The product uses external input to construct a pathname that should be within a restricted directory, but it does not properly neutralize '....//' (doubled dot dot slash) sequences that can resolve to a location that is outside of that directory.

## 2. 対策・緩和策 (Mitigations)
- 公式リファレンスおよび CWE 推奨の防御策を適用してください。

## 3. 一次ソースリンク
- [https://cwe.mitre.org/data/definitions/34.html](https://cwe.mitre.org/data/definitions/34.html)
