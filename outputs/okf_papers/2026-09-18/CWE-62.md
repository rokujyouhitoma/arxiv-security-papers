---
type: "weakness"
title: "[CWE-62] UNIX Hard Link"
description: "The product, when opening a file or directory, does not sufficiently account for when the name is associated with a hard"
resource: "https://cwe.mitre.org/data/definitions/62.html"
tags: ["weakness", "mitre-cwe", "cwe-62"]
timestamp: "2026-09-18T23:50:45.839261+00:00"
provenance:
  origin: "cwe.mitre.org"
  clean_id: "CWE-62"
  published: "2026-09-18"
  authors: ["MITRE CWE"]
trust:
  attestation_status: "verified"
  digital_signature: "antigravity-spider-v1"
---

# [CWE-62] UNIX Hard Link

## 1. 弱点概要 (Overview)
The product, when opening a file or directory, does not sufficiently account for when the name is associated with a hard link to a target that is outside of the intended control sphere. This could allow an attacker to cause the product to operate on unauthorized files.

## 2. 対策・緩和策 (Mitigations)
- 公式リファレンスおよび CWE 推奨の防御策を適用してください。

## 3. 一次ソースリンク
- [https://cwe.mitre.org/data/definitions/62.html](https://cwe.mitre.org/data/definitions/62.html)
