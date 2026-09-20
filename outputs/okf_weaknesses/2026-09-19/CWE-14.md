---
type: "weakness"
title: "[CWE-14] Compiler Removal of Code to Clear Buffers"
description: "Sensitive memory is cleared according to the source code, but compiler optimizations leave the memory untouched when it"
resource: "https://cwe.mitre.org/data/definitions/14.html"
tags: ["weakness", "mitre-cwe", "cwe-14"]
timestamp: "2026-09-19T07:16:39.987364+00:00"
provenance:
  origin: "cwe.mitre.org"
  clean_id: "CWE-14"
  published: "2026-09-19"
  authors: ["MITRE CWE"]
trust:
  attestation_status: "verified"
  digital_signature: "antigravity-spider-v1"
---

# [CWE-14] Compiler Removal of Code to Clear Buffers

## 1. 弱点概要 (Overview)
Sensitive memory is cleared according to the source code, but compiler optimizations leave the memory untouched when it is not read from again, aka dead store removal.

## 2. 対策・緩和策 (Mitigations)
- 公式リファレンスおよび CWE 推奨の防御策を適用してください。

## 3. 一次ソースリンク
- [https://cwe.mitre.org/data/definitions/14.html](https://cwe.mitre.org/data/definitions/14.html)
