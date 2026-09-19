---
type: "weakness"
title: "[CWE-50] Path Equivalence: '//multiple/leading/slash'"
description: "The product accepts path input in the form of multiple leading slash ('//multiple/leading/slash') without appropriate va"
resource: "https://cwe.mitre.org/data/definitions/50.html"
tags: ["weakness", "mitre-cwe", "cwe-50"]
timestamp: "2026-09-17T22:25:14.833671+00:00"
provenance:
  origin: "cwe.mitre.org"
  clean_id: "CWE-50"
  published: "2026-09-17"
  authors: ["MITRE CWE"]
trust:
  attestation_status: "verified"
  digital_signature: "antigravity-spider-v1"
---

# [CWE-50] Path Equivalence: '//multiple/leading/slash'

## 1. 弱点概要 (Overview)
The product accepts path input in the form of multiple leading slash ('//multiple/leading/slash') without appropriate validation, which can lead to ambiguous path resolution and allow an attacker to traverse the file system to unintended locations or access arbitrary files.

## 2. 対策・緩和策 (Mitigations)
- 公式リファレンスおよび CWE 推奨の防御策を適用してください。

## 3. 一次ソースリンク
- [https://cwe.mitre.org/data/definitions/50.html](https://cwe.mitre.org/data/definitions/50.html)
