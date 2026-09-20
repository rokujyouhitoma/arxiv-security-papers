---
type: "weakness"
title: "[CWE-55] Path Equivalence: '/./' (Single Dot Directory)"
description: "The product accepts path input in the form of single dot directory exploit ('/./') without appropriate validation, which"
resource: "https://cwe.mitre.org/data/definitions/55.html"
tags: ["weakness", "mitre-cwe", "cwe-55"]
timestamp: "2026-09-19T07:17:49.003399+00:00"
provenance:
  origin: "cwe.mitre.org"
  clean_id: "CWE-55"
  published: "2026-09-19"
  authors: ["MITRE CWE"]
trust:
  attestation_status: "verified"
  digital_signature: "antigravity-spider-v1"
---

# [CWE-55] Path Equivalence: '/./' (Single Dot Directory)

## 1. 弱点概要 (Overview)
The product accepts path input in the form of single dot directory exploit ('/./') without appropriate validation, which can lead to ambiguous path resolution and allow an attacker to traverse the file system to unintended locations or access arbitrary files.

## 2. 対策・緩和策 (Mitigations)
- 公式リファレンスおよび CWE 推奨の防御策を適用してください。

## 3. 一次ソースリンク
- [https://cwe.mitre.org/data/definitions/55.html](https://cwe.mitre.org/data/definitions/55.html)
