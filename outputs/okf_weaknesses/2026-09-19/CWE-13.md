---
type: "weakness"
title: "[CWE-13] ASP.NET Misconfiguration: Password in Configuration File"
description: "Storing a plaintext password in a configuration file allows anyone who can read the file access to the password-protecte"
resource: "https://cwe.mitre.org/data/definitions/13.html"
tags: ["weakness", "mitre-cwe", "cwe-13"]
timestamp: "2026-09-19T07:16:38.529250+00:00"
provenance:
  origin: "cwe.mitre.org"
  clean_id: "CWE-13"
  published: "2026-09-19"
  authors: ["MITRE CWE"]
trust:
  attestation_status: "verified"
  digital_signature: "antigravity-spider-v1"
---

# [CWE-13] ASP.NET Misconfiguration: Password in Configuration File

## 1. 弱点概要 (Overview)
Storing a plaintext password in a configuration file allows anyone who can read the file access to the password-protected resource making them an easy target for attackers.

## 2. 対策・緩和策 (Mitigations)
- 公式リファレンスおよび CWE 推奨の防御策を適用してください。

## 3. 一次ソースリンク
- [https://cwe.mitre.org/data/definitions/13.html](https://cwe.mitre.org/data/definitions/13.html)
