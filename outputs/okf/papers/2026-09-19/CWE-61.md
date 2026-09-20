---
type: "weakness"
title: "[CWE-61] UNIX Symbolic Link (Symlink) Following"
description: "The product, when opening a file or directory, does not sufficiently account for when the file is a symbolic link that r"
resource: "https://cwe.mitre.org/data/definitions/61.html"
tags: ["weakness", "mitre-cwe", "cwe-61"]
timestamp: "2026-09-19T03:08:03.802084+00:00"
provenance:
  origin: "cwe.mitre.org"
  clean_id: "CWE-61"
  published: "2026-09-19"
  authors: ["MITRE CWE"]
trust:
  attestation_status: "verified"
  digital_signature: "antigravity-spider-v1"
---

# [CWE-61] UNIX Symbolic Link (Symlink) Following

## 1. 弱点概要 (Overview)
The product, when opening a file or directory, does not sufficiently account for when the file is a symbolic link that resolves to a target outside of the intended control sphere. This could allow an attacker to cause the product to operate on unauthorized files.

## 2. 対策・緩和策 (Mitigations)
- 公式リファレンスおよび CWE 推奨の防御策を適用してください。

## 3. 一次ソースリンク
- [https://cwe.mitre.org/data/definitions/61.html](https://cwe.mitre.org/data/definitions/61.html)
