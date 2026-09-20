---
type: "weakness"
title: "[CWE-41] Improper Resolution of Path Equivalence"
description: "The product is vulnerable to file system contents disclosure through path equivalence. Path equivalence involves the use"
resource: "https://cwe.mitre.org/data/definitions/41.html"
tags: ["weakness", "mitre-cwe", "cwe-41"]
timestamp: "2026-09-19T07:17:20.789436+00:00"
provenance:
  origin: "cwe.mitre.org"
  clean_id: "CWE-41"
  published: "2026-09-19"
  authors: ["MITRE CWE"]
trust:
  attestation_status: "verified"
  digital_signature: "antigravity-spider-v1"
---

# [CWE-41] Improper Resolution of Path Equivalence

## 1. 弱点概要 (Overview)
The product is vulnerable to file system contents disclosure through path equivalence. Path equivalence involves the use of special characters in file and directory names. The associated manipulations are intended to generate multiple names for the same object.

## 2. 対策・緩和策 (Mitigations)
- 公式リファレンスおよび CWE 推奨の防御策を適用してください。

## 3. 一次ソースリンク
- [https://cwe.mitre.org/data/definitions/41.html](https://cwe.mitre.org/data/definitions/41.html)
