---
type: "weakness"
title: "[CWE-90] Improper Neutralization of Special Elements used in an LDAP Query ('LDAP Injection')"
description: "The product constructs all or part of an LDAP query using externally-influenced input from an upstream component, but it"
resource: "https://cwe.mitre.org/data/definitions/90.html"
tags: ["weakness", "mitre-cwe", "cwe-90"]
timestamp: "2026-09-19T03:09:04.482281+00:00"
provenance:
  origin: "cwe.mitre.org"
  clean_id: "CWE-90"
  published: "2026-09-19"
  authors: ["MITRE CWE"]
trust:
  attestation_status: "verified"
  digital_signature: "antigravity-spider-v1"
---

# [CWE-90] Improper Neutralization of Special Elements used in an LDAP Query ('LDAP Injection')

## 1. 弱点概要 (Overview)
The product constructs all or part of an LDAP query using externally-influenced input from an upstream component, but it does not neutralize or incorrectly neutralizes special elements that could modify the intended LDAP query when it is sent to a downstream component.

## 2. 対策・緩和策 (Mitigations)
- 公式リファレンスおよび CWE 推奨の防御策を適用してください。

## 3. 一次ソースリンク
- [https://cwe.mitre.org/data/definitions/90.html](https://cwe.mitre.org/data/definitions/90.html)
