---
type: "weakness"
title: "[CWE-64] Windows Shortcut Following (.LNK)"
description: "The product, when opening a file or directory, does not sufficiently handle when the file is a Windows shortcut (.LNK) w"
resource: "https://cwe.mitre.org/data/definitions/64.html"
tags: ["weakness", "mitre-cwe", "cwe-64"]
timestamp: "2026-09-18T23:50:45.839577+00:00"
provenance:
  origin: "cwe.mitre.org"
  clean_id: "CWE-64"
  published: "2026-09-18"
  authors: ["MITRE CWE"]
trust:
  attestation_status: "verified"
  digital_signature: "antigravity-spider-v1"
---

# [CWE-64] Windows Shortcut Following (.LNK)

## 1. 弱点概要 (Overview)
The product, when opening a file or directory, does not sufficiently handle when the file is a Windows shortcut (.LNK) whose target is outside of the intended control sphere. This could allow an attacker to cause the product to operate on unauthorized files.

## 2. 対策・緩和策 (Mitigations)
- 公式リファレンスおよび CWE 推奨の防御策を適用してください。

## 3. 一次ソースリンク
- [https://cwe.mitre.org/data/definitions/64.html](https://cwe.mitre.org/data/definitions/64.html)
