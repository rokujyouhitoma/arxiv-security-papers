---
type: "weakness"
title: "[CWE-51] Path Equivalence: '/multiple//internal/slash'"
description: "The product accepts path input in the form of multiple internal slash ('/multiple//internal/slash/') without appropriate"
resource: "https://cwe.mitre.org/data/definitions/51.html"
tags: ["weakness", "mitre-cwe", "cwe-51"]
timestamp: "2026-09-19T03:07:45.233715+00:00"
provenance:
  origin: "cwe.mitre.org"
  clean_id: "CWE-51"
  published: "2026-09-19"
  authors: ["MITRE CWE"]
trust:
  attestation_status: "verified"
  digital_signature: "antigravity-spider-v1"
---

# [CWE-51] Path Equivalence: '/multiple//internal/slash'

## 1. 弱点概要 (Overview)
The product accepts path input in the form of multiple internal slash ('/multiple//internal/slash/') without appropriate validation, which can lead to ambiguous path resolution and allow an attacker to traverse the file system to unintended locations or access arbitrary files.

## 2. 対策・緩和策 (Mitigations)
- 公式リファレンスおよび CWE 推奨の防御策を適用してください。

## 3. 一次ソースリンク
- [https://cwe.mitre.org/data/definitions/51.html](https://cwe.mitre.org/data/definitions/51.html)
