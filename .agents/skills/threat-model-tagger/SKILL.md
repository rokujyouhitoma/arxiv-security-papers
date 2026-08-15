---
name: threat-model-tagger
description: arXiv論文のAbstractおよび本文から MITRE ATT&CK テクニックID、STRIDE脅威モデルカテゴリ、CWE/CVE分類、およびセキュリティ防御タグを自動抽出し、OKF YAMLフロントマターを高度化する標準スキル。
---

# threat-model-tagger

本スキルは、**「arXiv セキュリティ論文の原本 Abstract および全文テキストから MITRE ATT&CK テクニック ID、STRIDE 脅威分類、CWE/CVE キーワード、およびセキュリティ対策カテゴリ（Zero Trust, EDR, PKI, ZKP等）を特定し、Google OKF v0.2 ドキュメントの YAML フロントマター `tags` および `description` をセキュリティ専門家レベルに自動強化する」** ための標準プロシージャスキルです。

情報セキュリティスペシャリスト（SC）、エンベデッドシステム（EP）、およびシステム監査人（AU）の連携により、正確かつ検索性の高いセキュリティ分類タグを提供します。

---

## 🛡️ 脅威モデル 4 大分析マッピング

```
[1. 論文本文 & Abstract テキスト解析]
       ↓
[2. MITRE ATT&CK / STRIDE マッピング]
       ├── ATT&CK: Initial Access (T1190), Execution (T1059), Privilege Escalation (T1068), Defense Evasion (T1211)
       └── STRIDE: Spoofing, Tampering, Repudiation, Information Disclosure, Denial of Service, Elevation of Privilege
       ↓
[3. セキュリティアーキテクチャ・分類タグ生成]
       ├── タグ例: cryptography, zero-trust, edr-xdr, firmware-security, memory-safety, llm-jailbreak
       ↓
[4. OKF YAML フロントマター (tags) への反映]
```

---

## 📋 実行手順 (Instructions)

### Step 1: 解析対象 OKF ドキュメントの特定
1. 強化対象の OKF Markdown ドキュメント (`outputs/okf_papers/YYYY-MM-DD/<clean_id>.md`) を開く。

### Step 2: 脅威・セキュリティタグの判定基準
以下の分類マトリクスに基づき、論文の主テーマに対応するタグを選定：

| ドメイン | 判定キーワード例 | 付与される OKF タグ |
|---|---|---|
| **Web & API** | XSS, CSRF, SQLi, SSRF, OAuth, REST, GraphQL | `web-security`, `api-security` |
| **暗号 & PQC** | RSA, ECC, Lattice, ZKP, FHE, Post-Quantum | `cryptography`, `post-quantum` |
| **AI & LLM** | LLM, Jailbreak, Prompt Injection, RAG, Adversarial | `ai-security`, `llm-safety` |
| **カーネル & メモリ** | Buffer Overflow, Use-After-Free, eBPF, ROP, SGX | `memory-safety`, `kernel-security` |
| **組込み & IoT** | Firmware, Side-Channel, JTAG, CAN Bus, PLC | `hardware-security`, `iot-security` |
| **ネットワーク** | Zero Trust, BGP, DNSSEC, TLS 1.3, DDoS, VPN | `network-security`, `zero-trust` |

### Step 3: OKF フロントマター `tags` の更新
1. OKF Markdown ファイルの YAML フロントマター内 `tags` 配下に抽出されたタグを追加：

```yaml
tags:
  - "cs.CR"
  - "ai-security"
  - "llm-safety"
  - "mitre-t1059"
```

### Step 4: 品質ゲート検証 (`verify-quality-gates`)
1. YAML フロントマターのインデント崩れがないこと、および `verify-quality-gates` スキルを呼出しエラーゼロをアサート。
