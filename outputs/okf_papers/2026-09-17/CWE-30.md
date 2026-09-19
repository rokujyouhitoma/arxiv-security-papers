---
type: "weakness"
title: "[CWE-30] Path Traversal: 'dir..filename'"
description: "The product uses external input to construct a pathname that should be within a restricted directory, but it does not pr"
resource: "https://cwe.mitre.org/data/definitions/30.html"
tags: ["weakness", "mitre-cwe", "cwe-30"]
timestamp: "2026-09-17T22:25:14.830950+00:00"
provenance:
  origin: "cwe.mitre.org"
  clean_id: "CWE-30"
  published: "2026-09-17"
  authors: ["MITRE CWE"]
trust:
  attestation_status: "verified"
  digital_signature: "antigravity-spider-v1"
---

# [CWE-30] Path Traversal: 'dir..filename'

## 1. 弱点概要 (Overview)
The product uses external input to construct a pathname that should be within a restricted directory, but it does not properly neutralize 'dir..filename' (leading backslash dot dot) sequences that can resolve to a location that is outside of that directory.

## 2. 対策・緩和策 (Mitigations)
- 公式リファレンスおよび CWE 推奨の防御策を適用してください。

## 3. 一次ソースリンク
- [https://cwe.mitre.org/data/definitions/30.html](https://cwe.mitre.org/data/definitions/30.html)
