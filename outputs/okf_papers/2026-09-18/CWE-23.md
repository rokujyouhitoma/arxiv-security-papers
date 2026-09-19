---
type: "weakness"
title: "[CWE-23] Relative Path Traversal"
description: "The product uses external input to construct a pathname that should be within a restricted directory, but it does not pr"
resource: "https://cwe.mitre.org/data/definitions/23.html"
tags: ["weakness", "mitre-cwe", "cwe-23"]
timestamp: "2026-09-18T23:50:45.825353+00:00"
provenance:
  origin: "cwe.mitre.org"
  clean_id: "CWE-23"
  published: "2026-09-18"
  authors: ["MITRE CWE"]
trust:
  attestation_status: "verified"
  digital_signature: "antigravity-spider-v1"
---

# [CWE-23] Relative Path Traversal

## 1. 弱点概要 (Overview)
The product uses external input to construct a pathname that should be within a restricted directory, but it does not properly neutralize sequences such as .. that can resolve to a location that is outside of that directory.

## 2. 対策・緩和策 (Mitigations)
- 公式リファレンスおよび CWE 推奨の防御策を適用してください。

## 3. 一次ソースリンク
- [https://cwe.mitre.org/data/definitions/23.html](https://cwe.mitre.org/data/definitions/23.html)
