---
type: "weakness"
title: "[CWE-53] Path Equivalence: 'multipleinternalbackslash'"
description: "The product accepts path input in the form of multiple internal backslash ('multipletrailingslash') without appropriate"
resource: "https://cwe.mitre.org/data/definitions/53.html"
tags: ["weakness", "mitre-cwe", "cwe-53"]
timestamp: "2026-09-19T07:17:44.830384+00:00"
provenance:
  origin: "cwe.mitre.org"
  clean_id: "CWE-53"
  published: "2026-09-19"
  authors: ["MITRE CWE"]
trust:
  attestation_status: "verified"
  digital_signature: "antigravity-spider-v1"
---

# [CWE-53] Path Equivalence: 'multipleinternalbackslash'

## 1. 弱点概要 (Overview)
The product accepts path input in the form of multiple internal backslash ('multipletrailingslash') without appropriate validation, which can lead to ambiguous path resolution and allow an attacker to traverse the file system to unintended locations or access arbitrary files.

## 2. 対策・緩和策 (Mitigations)
- 公式リファレンスおよび CWE 推奨の防御策を適用してください。

## 3. 一次ソースリンク
- [https://cwe.mitre.org/data/definitions/53.html](https://cwe.mitre.org/data/definitions/53.html)
