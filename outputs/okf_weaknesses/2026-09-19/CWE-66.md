---
type: "weakness"
title: "[CWE-66] Improper Handling of File Names that Identify Virtual Resources"
description: "The product does not handle or incorrectly handles a file name that identifies a virtual resource that is not directly s"
resource: "https://cwe.mitre.org/data/definitions/66.html"
tags: ["weakness", "mitre-cwe", "cwe-66"]
timestamp: "2026-09-19T07:18:06.640076+00:00"
provenance:
  origin: "cwe.mitre.org"
  clean_id: "CWE-66"
  published: "2026-09-19"
  authors: ["MITRE CWE"]
trust:
  attestation_status: "verified"
  digital_signature: "antigravity-spider-v1"
---

# [CWE-66] Improper Handling of File Names that Identify Virtual Resources

## 1. 弱点概要 (Overview)
The product does not handle or incorrectly handles a file name that identifies a virtual resource that is not directly specified within the directory that is associated with the file name, causing the product to perform file-based operations on a resource that is not a file.

## 2. 対策・緩和策 (Mitigations)
- 公式リファレンスおよび CWE 推奨の防御策を適用してください。

## 3. 一次ソースリンク
- [https://cwe.mitre.org/data/definitions/66.html](https://cwe.mitre.org/data/definitions/66.html)
