---
type: "weakness"
title: "[CWE-57] Path Equivalence: 'fakedir/../realdir/filename'"
description: "The product contains protection mechanisms to restrict access to 'realdir/filename', but it constructs pathnames using e"
resource: "https://cwe.mitre.org/data/definitions/57.html"
tags: ["weakness", "mitre-cwe", "cwe-57"]
timestamp: "2026-09-19T07:17:52.782362+00:00"
provenance:
  origin: "cwe.mitre.org"
  clean_id: "CWE-57"
  published: "2026-09-19"
  authors: ["MITRE CWE"]
trust:
  attestation_status: "verified"
  digital_signature: "antigravity-spider-v1"
---

# [CWE-57] Path Equivalence: 'fakedir/../realdir/filename'

## 1. 弱点概要 (Overview)
The product contains protection mechanisms to restrict access to 'realdir/filename', but it constructs pathnames using external input in the form of 'fakedir/../realdir/filename' that are not handled by those mechanisms. This allows attackers to perform unauthorized actions against the targeted file.

## 2. 対策・緩和策 (Mitigations)
- 公式リファレンスおよび CWE 推奨の防御策を適用してください。

## 3. 一次ソースリンク
- [https://cwe.mitre.org/data/definitions/57.html](https://cwe.mitre.org/data/definitions/57.html)
