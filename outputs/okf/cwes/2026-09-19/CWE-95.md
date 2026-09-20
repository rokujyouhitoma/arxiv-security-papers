---
type: "weakness"
title: "[CWE-95] Improper Neutralization of Directives in Dynamically Evaluated Code ('Eval Injection')"
description: "The product receives input from an upstream component, but it does not neutralize or incorrectly neutralizes code syntax"
resource: "https://cwe.mitre.org/data/definitions/95.html"
tags: ["weakness", "mitre-cwe", "cwe-95"]
timestamp: "2026-09-19T07:19:07.003962+00:00"
provenance:
  origin: "cwe.mitre.org"
  clean_id: "CWE-95"
  published: "2026-09-19"
  authors: ["MITRE CWE"]
trust:
  attestation_status: "verified"
  digital_signature: "antigravity-spider-v1"
---

# [CWE-95] Improper Neutralization of Directives in Dynamically Evaluated Code ('Eval Injection')

## 1. 弱点概要 (Overview)
The product receives input from an upstream component, but it does not neutralize or incorrectly neutralizes code syntax before using the input in a dynamic evaluation call (e.g. eval).

## 2. 対策・緩和策 (Mitigations)
- 公式リファレンスおよび CWE 推奨の防御策を適用してください。

## 3. 一次ソースリンク
- [https://cwe.mitre.org/data/definitions/95.html](https://cwe.mitre.org/data/definitions/95.html)
