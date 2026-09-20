---
type: "weakness"
title: "[CWE-37] Path Traversal: '/absolute/pathname/here'"
description: "The product accepts input in the form of a slash absolute path ('/absolute/pathname/here') without appropriate validatio"
resource: "https://cwe.mitre.org/data/definitions/37.html"
tags: ["weakness", "mitre-cwe", "cwe-37"]
timestamp: "2026-09-19T07:17:14.062869+00:00"
provenance:
  origin: "cwe.mitre.org"
  clean_id: "CWE-37"
  published: "2026-09-19"
  authors: ["MITRE CWE"]
trust:
  attestation_status: "verified"
  digital_signature: "antigravity-spider-v1"
---

# [CWE-37] Path Traversal: '/absolute/pathname/here'

## 1. 弱点概要 (Overview)
The product accepts input in the form of a slash absolute path ('/absolute/pathname/here') without appropriate validation, which can allow an attacker to traverse the file system to unintended locations or access arbitrary files.

## 2. 対策・緩和策 (Mitigations)
- 公式リファレンスおよび CWE 推奨の防御策を適用してください。

## 3. 一次ソースリンク
- [https://cwe.mitre.org/data/definitions/37.html](https://cwe.mitre.org/data/definitions/37.html)
