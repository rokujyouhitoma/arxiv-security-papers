---
type: "weakness"
title: "[CWE-45] Path Equivalence: 'file...name' (Multiple Internal Dot)"
description: "The product accepts path input in the form of multiple internal dot ('file...dir') without appropriate validation, which"
resource: "https://cwe.mitre.org/data/definitions/45.html"
tags: ["weakness", "mitre-cwe", "cwe-45"]
timestamp: "2026-09-19T03:07:29.785647+00:00"
provenance:
  origin: "cwe.mitre.org"
  clean_id: "CWE-45"
  published: "2026-09-19"
  authors: ["MITRE CWE"]
trust:
  attestation_status: "verified"
  digital_signature: "antigravity-spider-v1"
---

# [CWE-45] Path Equivalence: 'file...name' (Multiple Internal Dot)

## 1. 弱点概要 (Overview)
The product accepts path input in the form of multiple internal dot ('file...dir') without appropriate validation, which can lead to ambiguous path resolution and allow an attacker to traverse the file system to unintended locations or access arbitrary files.

## 2. 対策・緩和策 (Mitigations)
- 公式リファレンスおよび CWE 推奨の防御策を適用してください。

## 3. 一次ソースリンク
- [https://cwe.mitre.org/data/definitions/45.html](https://cwe.mitre.org/data/definitions/45.html)
