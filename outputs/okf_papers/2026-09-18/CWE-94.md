---
type: "weakness"
title: "[CWE-94] Improper Control of Generation of Code ('Code Injection')"
description: "The product constructs all or part of a code segment using externally-influenced input from an upstream component, but i"
resource: "https://cwe.mitre.org/data/definitions/94.html"
tags: ["weakness", "mitre-cwe", "cwe-94"]
timestamp: "2026-09-18T23:50:45.863361+00:00"
provenance:
  origin: "cwe.mitre.org"
  clean_id: "CWE-94"
  published: "2026-09-18"
  authors: ["MITRE CWE"]
trust:
  attestation_status: "verified"
  digital_signature: "antigravity-spider-v1"
---

# [CWE-94] Improper Control of Generation of Code ('Code Injection')

## 1. 弱点概要 (Overview)
The product constructs all or part of a code segment using externally-influenced input from an upstream component, but it does not neutralize or incorrectly neutralizes special elements that could modify the syntax or behavior of the intended code segment.

## 2. 対策・緩和策 (Mitigations)
- 公式リファレンスおよび CWE 推奨の防御策を適用してください。

## 3. 一次ソースリンク
- [https://cwe.mitre.org/data/definitions/94.html](https://cwe.mitre.org/data/definitions/94.html)
