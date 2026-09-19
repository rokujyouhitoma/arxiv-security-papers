---
type: "weakness"
title: "[CWE-47] Path Equivalence: ' filename' (Leading Space)"
description: "The product accepts path input in the form of leading space (' filedir') without appropriate validation, which can lead"
resource: "https://cwe.mitre.org/data/definitions/47.html"
tags: ["weakness", "mitre-cwe", "cwe-47"]
timestamp: "2026-09-17T22:25:14.833252+00:00"
provenance:
  origin: "cwe.mitre.org"
  clean_id: "CWE-47"
  published: "2026-09-17"
  authors: ["MITRE CWE"]
trust:
  attestation_status: "verified"
  digital_signature: "antigravity-spider-v1"
---

# [CWE-47] Path Equivalence: ' filename' (Leading Space)

## 1. 弱点概要 (Overview)
The product accepts path input in the form of leading space (' filedir') without appropriate validation, which can lead to ambiguous path resolution and allow an attacker to traverse the file system to unintended locations or access arbitrary files.

## 2. 対策・緩和策 (Mitigations)
- 公式リファレンスおよび CWE 推奨の防御策を適用してください。

## 3. 一次ソースリンク
- [https://cwe.mitre.org/data/definitions/47.html](https://cwe.mitre.org/data/definitions/47.html)
