---
type: "weakness"
title: "[CWE-78] Improper Neutralization of Special Elements used in an OS Command ('OS Command Injection')"
description: "The product constructs all or part of an OS command using externally-influenced input from an upstream component, but it"
resource: "https://cwe.mitre.org/data/definitions/78.html"
tags: ["weakness", "mitre-cwe", "cwe-78"]
timestamp: "2026-09-19T03:08:34.074555+00:00"
provenance:
  origin: "cwe.mitre.org"
  clean_id: "CWE-78"
  published: "2026-09-19"
  authors: ["MITRE CWE"]
trust:
  attestation_status: "verified"
  digital_signature: "antigravity-spider-v1"
---

# [CWE-78] Improper Neutralization of Special Elements used in an OS Command ('OS Command Injection')

## 1. 弱点概要 (Overview)
The product constructs all or part of an OS command using externally-influenced input from an upstream component, but it does not neutralize or incorrectly neutralizes special elements that could modify the intended OS command when it is sent to a downstream component.

## 2. 対策・緩和策 (Mitigations)
- 公式リファレンスおよび CWE 推奨の防御策を適用してください。

## 3. 一次ソースリンク
- [https://cwe.mitre.org/data/definitions/78.html](https://cwe.mitre.org/data/definitions/78.html)
