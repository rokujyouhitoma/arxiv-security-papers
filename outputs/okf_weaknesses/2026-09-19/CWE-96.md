---
type: "weakness"
title: "[CWE-96] Improper Neutralization of Directives in Statically Saved Code ('Static Code Injection')"
description: "The product receives input from an upstream component, but it does not neutralize or incorrectly neutralizes code syntax"
resource: "https://cwe.mitre.org/data/definitions/96.html"
tags: ["weakness", "mitre-cwe", "cwe-96"]
timestamp: "2026-09-19T07:19:08.869743+00:00"
provenance:
  origin: "cwe.mitre.org"
  clean_id: "CWE-96"
  published: "2026-09-19"
  authors: ["MITRE CWE"]
trust:
  attestation_status: "verified"
  digital_signature: "antigravity-spider-v1"
---

# [CWE-96] Improper Neutralization of Directives in Statically Saved Code ('Static Code Injection')

## 1. 弱点概要 (Overview)
The product receives input from an upstream component, but it does not neutralize or incorrectly neutralizes code syntax before inserting the input into an executable resource, such as a library, configuration file, or template.

## 2. 対策・緩和策 (Mitigations)
- 公式リファレンスおよび CWE 推奨の防御策を適用してください。

## 3. 一次ソースリンク
- [https://cwe.mitre.org/data/definitions/96.html](https://cwe.mitre.org/data/definitions/96.html)
