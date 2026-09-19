---
type: "weakness"
title: "[CWE-22] Improper Limitation of a Pathname to a Restricted Directory ('Path Traversal')"
description: "The product uses external input to construct a pathname that is intended to identify a file or directory that is located"
resource: "https://cwe.mitre.org/data/definitions/22.html"
tags: ["weakness", "mitre-cwe", "cwe-22"]
timestamp: "2026-09-17T22:25:14.829759+00:00"
provenance:
  origin: "cwe.mitre.org"
  clean_id: "CWE-22"
  published: "2026-09-17"
  authors: ["MITRE CWE"]
trust:
  attestation_status: "verified"
  digital_signature: "antigravity-spider-v1"
---

# [CWE-22] Improper Limitation of a Pathname to a Restricted Directory ('Path Traversal')

## 1. 弱点概要 (Overview)
The product uses external input to construct a pathname that is intended to identify a file or directory that is located underneath a restricted parent directory, but the product does not properly neutralize special elements within the pathname that can cause the pathname to resolve to a location that is outside of the restricted directory.

## 2. 対策・緩和策 (Mitigations)
- 公式リファレンスおよび CWE 推奨の防御策を適用してください。

## 3. 一次ソースリンク
- [https://cwe.mitre.org/data/definitions/22.html](https://cwe.mitre.org/data/definitions/22.html)
