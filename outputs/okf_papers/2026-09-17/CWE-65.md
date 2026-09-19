---
type: "weakness"
title: "[CWE-65] Windows Hard Link"
description: "The product, when opening a file or directory, does not sufficiently handle when the name is associated with a hard link"
resource: "https://cwe.mitre.org/data/definitions/65.html"
tags: ["weakness", "mitre-cwe", "cwe-65"]
timestamp: "2026-09-17T22:25:14.834858+00:00"
provenance:
  origin: "cwe.mitre.org"
  clean_id: "CWE-65"
  published: "2026-09-17"
  authors: ["MITRE CWE"]
trust:
  attestation_status: "verified"
  digital_signature: "antigravity-spider-v1"
---

# [CWE-65] Windows Hard Link

## 1. 弱点概要 (Overview)
The product, when opening a file or directory, does not sufficiently handle when the name is associated with a hard link to a target that is outside of the intended control sphere. This could allow an attacker to cause the product to operate on unauthorized files.

## 2. 対策・緩和策 (Mitigations)
- 公式リファレンスおよび CWE 推奨の防御策を適用してください。

## 3. 一次ソースリンク
- [https://cwe.mitre.org/data/definitions/65.html](https://cwe.mitre.org/data/definitions/65.html)
