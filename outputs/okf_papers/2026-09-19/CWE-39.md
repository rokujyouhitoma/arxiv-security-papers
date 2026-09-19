---
type: "weakness"
title: "[CWE-39] Path Traversal: 'C:dirname'"
description: "The product accepts input that contains a drive letter or Windows volume letter ('C:dirname') that potentially redirects"
resource: "https://cwe.mitre.org/data/definitions/39.html"
tags: ["weakness", "mitre-cwe", "cwe-39"]
timestamp: "2026-09-19T03:07:16.488867+00:00"
provenance:
  origin: "cwe.mitre.org"
  clean_id: "CWE-39"
  published: "2026-09-19"
  authors: ["MITRE CWE"]
trust:
  attestation_status: "verified"
  digital_signature: "antigravity-spider-v1"
---

# [CWE-39] Path Traversal: 'C:dirname'

## 1. 弱点概要 (Overview)
The product accepts input that contains a drive letter or Windows volume letter ('C:dirname') that potentially redirects access to an unintended location or arbitrary file.

## 2. 対策・緩和策 (Mitigations)
- 公式リファレンスおよび CWE 推奨の防御策を適用してください。

## 3. 一次ソースリンク
- [https://cwe.mitre.org/data/definitions/39.html](https://cwe.mitre.org/data/definitions/39.html)
