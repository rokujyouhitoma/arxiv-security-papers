---
type: "weakness"
title: "[CWE-77] Improper Neutralization of Special Elements used in a Command ('Command Injection')"
description: "The product constructs all or part of a command using externally-influenced input from an upstream component, but it doe"
resource: "https://cwe.mitre.org/data/definitions/77.html"
tags: ["weakness", "mitre-cwe", "cwe-77"]
timestamp: "2026-09-17T22:25:14.835684+00:00"
provenance:
  origin: "cwe.mitre.org"
  clean_id: "CWE-77"
  published: "2026-09-17"
  authors: ["MITRE CWE"]
trust:
  attestation_status: "verified"
  digital_signature: "antigravity-spider-v1"
---

# [CWE-77] Improper Neutralization of Special Elements used in a Command ('Command Injection')

## 1. 弱点概要 (Overview)
The product constructs all or part of a command using externally-influenced input from an upstream component, but it does not neutralize or incorrectly neutralizes special elements that could modify the intended command when it is sent to a downstream component.

## 2. 対策・緩和策 (Mitigations)
- 公式リファレンスおよび CWE 推奨の防御策を適用してください。

## 3. 一次ソースリンク
- [https://cwe.mitre.org/data/definitions/77.html](https://cwe.mitre.org/data/definitions/77.html)
