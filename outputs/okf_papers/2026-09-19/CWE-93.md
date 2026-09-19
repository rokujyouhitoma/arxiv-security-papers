---
type: "weakness"
title: "[CWE-93] Improper Neutralization of CRLF Sequences ('CRLF Injection')"
description: "The product uses CRLF (carriage return line feeds) as a special element, e.g. to separate lines or records, but it does"
resource: "https://cwe.mitre.org/data/definitions/93.html"
tags: ["weakness", "mitre-cwe", "cwe-93"]
timestamp: "2026-09-19T03:09:08.408295+00:00"
provenance:
  origin: "cwe.mitre.org"
  clean_id: "CWE-93"
  published: "2026-09-19"
  authors: ["MITRE CWE"]
trust:
  attestation_status: "verified"
  digital_signature: "antigravity-spider-v1"
---

# [CWE-93] Improper Neutralization of CRLF Sequences ('CRLF Injection')

## 1. 弱点概要 (Overview)
The product uses CRLF (carriage return line feeds) as a special element, e.g. to separate lines or records, but it does not neutralize or incorrectly neutralizes CRLF sequences from inputs.

## 2. 対策・緩和策 (Mitigations)
- 公式リファレンスおよび CWE 推奨の防御策を適用してください。

## 3. 一次ソースリンク
- [https://cwe.mitre.org/data/definitions/93.html](https://cwe.mitre.org/data/definitions/93.html)
