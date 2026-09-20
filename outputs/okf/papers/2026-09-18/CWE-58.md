---
type: "weakness"
title: "[CWE-58] Path Equivalence: Windows 8.3 Filename"
description: "The product contains a protection mechanism that restricts access to a long filename on a Windows operating system, but"
resource: "https://cwe.mitre.org/data/definitions/58.html"
tags: ["weakness", "mitre-cwe", "cwe-58"]
timestamp: "2026-09-18T23:50:45.838549+00:00"
provenance:
  origin: "cwe.mitre.org"
  clean_id: "CWE-58"
  published: "2026-09-18"
  authors: ["MITRE CWE"]
trust:
  attestation_status: "verified"
  digital_signature: "antigravity-spider-v1"
---

# [CWE-58] Path Equivalence: Windows 8.3 Filename

## 1. 弱点概要 (Overview)
The product contains a protection mechanism that restricts access to a long filename on a Windows operating system, but it does not properly restrict access to the equivalent short 8.3 filename.

## 2. 対策・緩和策 (Mitigations)
- 公式リファレンスおよび CWE 推奨の防御策を適用してください。

## 3. 一次ソースリンク
- [https://cwe.mitre.org/data/definitions/58.html](https://cwe.mitre.org/data/definitions/58.html)
