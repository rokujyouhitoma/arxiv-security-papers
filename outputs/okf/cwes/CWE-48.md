---
type: "weakness"
title: "[CWE-48] Path Equivalence: 'file name' (Internal Whitespace)"
description: "The product accepts path input in the form of internal space ('file(SPACE)name') without appropriate validation, which c"
resource: "https://cwe.mitre.org/data/definitions/48.html"
tags: ["weakness", "mitre-cwe", "cwe-48"]
timestamp: "2026-09-17T22:25:14.833429+00:00"
provenance:
  origin: "cwe.mitre.org"
  clean_id: "CWE-48"
  published: "2026-09-17"
  authors: ["MITRE CWE"]
trust:
  attestation_status: "verified"
  digital_signature: "antigravity-spider-v1"
---

# [CWE-48] Path Equivalence: 'file name' (Internal Whitespace)

## 1. 弱点概要 (Overview)
The product accepts path input in the form of internal space ('file(SPACE)name') without appropriate validation, which can lead to ambiguous path resolution and allow an attacker to traverse the file system to unintended locations or access arbitrary files.

## 2. 対策・緩和策 (Mitigations)
- 公式リファレンスおよび CWE 推奨の防御策を適用してください。

## 3. 一次ソースリンク
- [https://cwe.mitre.org/data/definitions/48.html](https://cwe.mitre.org/data/definitions/48.html)
