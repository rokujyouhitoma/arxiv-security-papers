---
type: "weakness"
title: "[CWE-67] Improper Handling of Windows Device Names"
description: "The product constructs pathnames from user input, but it does not handle or incorrectly handles a pathname containing a"
resource: "https://cwe.mitre.org/data/definitions/67.html"
tags: ["weakness", "mitre-cwe", "cwe-67"]
timestamp: "2026-09-18T23:50:45.840481+00:00"
provenance:
  origin: "cwe.mitre.org"
  clean_id: "CWE-67"
  published: "2026-09-18"
  authors: ["MITRE CWE"]
trust:
  attestation_status: "verified"
  digital_signature: "antigravity-spider-v1"
---

# [CWE-67] Improper Handling of Windows Device Names

## 1. 弱点概要 (Overview)
The product constructs pathnames from user input, but it does not handle or incorrectly handles a pathname containing a Windows device name such as AUX or CON. This typically leads to denial of service or an information exposure when the application attempts to process the pathname as a regular file.

## 2. 対策・緩和策 (Mitigations)
- 公式リファレンスおよび CWE 推奨の防御策を適用してください。

## 3. 一次ソースリンク
- [https://cwe.mitre.org/data/definitions/67.html](https://cwe.mitre.org/data/definitions/67.html)
