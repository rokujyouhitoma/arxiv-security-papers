---
type: "weakness"
title: "[CWE-88] Improper Neutralization of Argument Delimiters in a Command ('Argument Injection')"
description: "The product constructs a string for a command to be executed by a separate component in another control sphere, but it d"
resource: "https://cwe.mitre.org/data/definitions/88.html"
tags: ["weakness", "mitre-cwe", "cwe-88"]
timestamp: "2026-09-19T07:18:51.325865+00:00"
provenance:
  origin: "cwe.mitre.org"
  clean_id: "CWE-88"
  published: "2026-09-19"
  authors: ["MITRE CWE"]
trust:
  attestation_status: "verified"
  digital_signature: "antigravity-spider-v1"
---

# [CWE-88] Improper Neutralization of Argument Delimiters in a Command ('Argument Injection')

## 1. 弱点概要 (Overview)
The product constructs a string for a command to be executed by a separate component in another control sphere, but it does not properly delimit the intended arguments, options, or switches within that command string.

## 2. 対策・緩和策 (Mitigations)
- 公式リファレンスおよび CWE 推奨の防御策を適用してください。

## 3. 一次ソースリンク
- [https://cwe.mitre.org/data/definitions/88.html](https://cwe.mitre.org/data/definitions/88.html)
