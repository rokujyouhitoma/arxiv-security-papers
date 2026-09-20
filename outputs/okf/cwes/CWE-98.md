---
type: "weakness"
title: "[CWE-98] Improper Control of Filename for Include/Require Statement in PHP Program ('PHP Remote File Inclusion')"
description: "The PHP application receives input from an upstream component, but it does not restrict or incorrectly restricts the inp"
resource: "https://cwe.mitre.org/data/definitions/98.html"
tags: ["weakness", "mitre-cwe", "cwe-98"]
timestamp: "2026-09-17T22:25:14.837770+00:00"
provenance:
  origin: "cwe.mitre.org"
  clean_id: "CWE-98"
  published: "2026-09-17"
  authors: ["MITRE CWE"]
trust:
  attestation_status: "verified"
  digital_signature: "antigravity-spider-v1"
---

# [CWE-98] Improper Control of Filename for Include/Require Statement in PHP Program ('PHP Remote File Inclusion')

## 1. 弱点概要 (Overview)
The PHP application receives input from an upstream component, but it does not restrict or incorrectly restricts the input before its usage in require, include, or similar functions.

## 2. 対策・緩和策 (Mitigations)
- 公式リファレンスおよび CWE 推奨の防御策を適用してください。

## 3. 一次ソースリンク
- [https://cwe.mitre.org/data/definitions/98.html](https://cwe.mitre.org/data/definitions/98.html)
