---
type: "weakness"
title: "[CWE-54] Path Equivalence: 'filedir' (Trailing Backslash)"
description: "The product accepts path input in the form of trailing backslash ('filedir') without appropriate validation, which can l"
resource: "https://cwe.mitre.org/data/definitions/54.html"
tags: ["weakness", "mitre-cwe", "cwe-54"]
timestamp: "2026-09-19T07:17:46.892935+00:00"
provenance:
  origin: "cwe.mitre.org"
  clean_id: "CWE-54"
  published: "2026-09-19"
  authors: ["MITRE CWE"]
trust:
  attestation_status: "verified"
  digital_signature: "antigravity-spider-v1"
---

# [CWE-54] Path Equivalence: 'filedir' (Trailing Backslash)

## 1. 弱点概要 (Overview)
The product accepts path input in the form of trailing backslash ('filedir') without appropriate validation, which can lead to ambiguous path resolution and allow an attacker to traverse the file system to unintended locations or access arbitrary files.

## 2. 対策・緩和策 (Mitigations)
- 公式リファレンスおよび CWE 推奨の防御策を適用してください。

## 3. 一次ソースリンク
- [https://cwe.mitre.org/data/definitions/54.html](https://cwe.mitre.org/data/definitions/54.html)
