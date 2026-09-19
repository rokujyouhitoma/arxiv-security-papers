---
type: "weakness"
title: "[CWE-59] Improper Link Resolution Before File Access ('Link Following')"
description: "The product attempts to access a file based on the filename, but it does not properly prevent that filename from identif"
resource: "https://cwe.mitre.org/data/definitions/59.html"
tags: ["weakness", "mitre-cwe", "cwe-59"]
timestamp: "2026-09-17T22:25:14.834515+00:00"
provenance:
  origin: "cwe.mitre.org"
  clean_id: "CWE-59"
  published: "2026-09-17"
  authors: ["MITRE CWE"]
trust:
  attestation_status: "verified"
  digital_signature: "antigravity-spider-v1"
---

# [CWE-59] Improper Link Resolution Before File Access ('Link Following')

## 1. 弱点概要 (Overview)
The product attempts to access a file based on the filename, but it does not properly prevent that filename from identifying a link or shortcut that resolves to an unintended resource.

## 2. 対策・緩和策 (Mitigations)
- 公式リファレンスおよび CWE 推奨の防御策を適用してください。

## 3. 一次ソースリンク
- [https://cwe.mitre.org/data/definitions/59.html](https://cwe.mitre.org/data/definitions/59.html)
