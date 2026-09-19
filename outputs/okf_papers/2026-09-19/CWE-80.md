---
type: "weakness"
title: "[CWE-80] Improper Neutralization of Script-Related HTML Tags in a Web Page (Basic XSS)"
description: "The product receives input from an upstream component, but it does not neutralize or incorrectly neutralizes special cha"
resource: "https://cwe.mitre.org/data/definitions/80.html"
tags: ["weakness", "mitre-cwe", "cwe-80"]
timestamp: "2026-09-19T03:08:41.374460+00:00"
provenance:
  origin: "cwe.mitre.org"
  clean_id: "CWE-80"
  published: "2026-09-19"
  authors: ["MITRE CWE"]
trust:
  attestation_status: "verified"
  digital_signature: "antigravity-spider-v1"
---

# [CWE-80] Improper Neutralization of Script-Related HTML Tags in a Web Page (Basic XSS)

## 1. 弱点概要 (Overview)
The product receives input from an upstream component, but it does not neutralize or incorrectly neutralizes special characters such as <, >, and & that could be interpreted as web-scripting elements when they are sent to a downstream component that processes web pages.

## 2. 対策・緩和策 (Mitigations)
- 公式リファレンスおよび CWE 推奨の防御策を適用してください。

## 3. 一次ソースリンク
- [https://cwe.mitre.org/data/definitions/80.html](https://cwe.mitre.org/data/definitions/80.html)
