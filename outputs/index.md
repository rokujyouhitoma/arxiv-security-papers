---
type: "catalog-index"
title: "arXiv セキュリティ論文 OKF ナレッジカタログ"
description: "arXiv cs.CR から取得したセキュリティ論文Rawデータ（JSON/PDF/TXT）、OKFドキュメント、および各階層の日本語エグゼクティブサマリー一覧"
timestamp: "2026-09-20T02:55:03Z"
---

# 🛡️ arXiv セキュリティ論文 ナレッジカタログ (Google OKF v0.2)

> [!INFO]
> 本カタログは、arXiv (`cs.CR`) から取得したサイバーセキュリティ論文について、**原データ保持 (raw_data: JSON / PDF / TXT)**、**OKF変換ドキュメント (okf_papers)**、および**日本語表形式エグゼクティブサマリー (01_per_run 〜 05_annual)** を全成果物集約ディレクトリ `outputs/` の下で独立管理・提供するナビゲーションポータルです。

---

## 🔍 全件検索・データアクセス基盤 (Decoupled Catalog Views)

全収集論文（数千件）の高速検索・フィルタリング、および構造化生データへのアクセスは以下の基盤をご利用ください：

| アクセス種別 | リンク (相対パス) | 提供機能・用途 |
|---|---|---|
| 🌐 **Web コンソール** | [Web Console](../site/index.html) | キーワード検索、ドメイン・タグ絞り込み、高速グラフ・統計可視化 |
| 🗄️ **全件カタログ台帳** | [papers_catalog.json](database/papers_catalog.json) | 全収集論文のメタデータ・要約・OKF/Rawリンクを完全網羅した構造化JSON |
| 📄 **OKF ドキュメント** | [okf_papers/](okf/papers) | 日付別 OKF v0.2 Markdown ドキュメント群 |
| 📦 **原本生データ** | [raw_data/](raw_data) | arXiv 公式 JSON / PDF / pdftotext 抽出 TXT 原本 |

---

## 📊 ソート済みエグゼクティブサマリー層 (日本語サマリー)

| 項番 & 区分 | ディレクトリ名 | 対象範囲 | 最新サマリーファイル (相対リンク) |
|---|---|---|---|
| ⏱️ **01_per_run** | `01_per_run/` | 取得時ごと (1日4回) | [run_0712.md](executive_summaries/01_per_run/2026-09-07/run_0712.md) |
| 📅 **02_daily** | `02_daily/` | 最新日 (2026-09-20) | [2026-09-07.md](executive_summaries/02_daily/2026-09-07.md) |
| 📊 **03_monthly** | `03_monthly/` | 過去30日間 | [monthly_2026-09-07.md](executive_summaries/03_monthly/monthly_2026-09-07.md) |
| 🏢 **04_quarterly** | `04_quarterly/` | 過去90日間 | [quarterly_2026-09-07.md](executive_summaries/04_quarterly/quarterly_2026-09-07.md) |
| 🏆 **05_annual** | `05_annual/` | 過去365日間 | [annual_2026-09-07.md](executive_summaries/05_annual/annual_2026-09-07.md) |

---

## 📚 直近登録論文ハイライト (最新 50 件)

> [!NOTE]
> 本ファイルでは直近最新の **50 件** をピックアップ掲載しています。
> 過去の全論文の検索・閲覧・分析は [Web コンソール](../site/index.html) または [papers_catalog.json](database/papers_catalog.json) をご参照ください。

| 公開日 | arXiv ID | OKFドキュメント (原題 & リンク) | 論文タイトル (日本語訳) | 原本Rawデータ (JSON / PDF / TXT) | 主カテゴリ | 原本リンク |
|---|---|---|---|---|---|---|
| 2026-09-19 | `2609.18783` | [s-MDM: Generative Virtualization of Multi-Device Hardware Variations for Portable DL-SCATitle:](okf/papers/2026-09-19/2609.18783.md) | s-MDM: Generative Virtualization of Multi-Device Hardware Variations for Portable DL-SCATitle:（セキュリティ分析論文） | N/A | `cs.CR` | [arXiv](https://arxiv.org/abs/2609.18783) |
| 2026-09-19 | `2609.18811` | [Differential Trust: Dynamic Multi-Authority Anonymous Credentials with Epoch-Weighted UpdatesTitle:](okf/papers/2026-09-19/2609.18811.md) | Differential Trust: Dynamic Multi-Authority Anonymous Credentials with Epoch-Weighted UpdatesTitle:（セキュリティ分析論文） | N/A | `cs.CR` | [arXiv](https://arxiv.org/abs/2609.18811) |
| 2026-09-19 | `2609.18862` | [CASHEWS: Source Preprocessor for LLM-based Malicious Package DetectionTitle:](okf/papers/2026-09-19/2609.18862.md) | CASHEWS: Source Preprocessor for LLM-based Malicious Package DetectionTitle:（セキュリティ分析論文） | N/A | `cs.CR` | [arXiv](https://arxiv.org/abs/2609.18862) |
| 2026-09-19 | `2609.18864` | [ASLEval: Measuring Privacy Exposure Displacement in LLM Agent SessionsTitle:](okf/papers/2026-09-19/2609.18864.md) | ASLEval: Measuring Privacy Exposure Displacement in LLM Agent SessionsTitle:（セキュリティ分析論文） | N/A | `cs.CR` | [arXiv](https://arxiv.org/abs/2609.18864) |
| 2026-09-19 | `2609.18866` | [Hamming Ideals and Grobner Bases for ISD-like Syndrome DecodingTitle:](okf/papers/2026-09-19/2609.18866.md) | Hamming Ideals and Grobner Bases for ISD-like Syndrome DecodingTitle:（セキュリティ分析論文） | N/A | `cs.CR` | [arXiv](https://arxiv.org/abs/2609.18866) |
| 2026-09-19 | `2609.18965` | [BadQubits: An LLM-Based Framework for Static Pre-Execution Detection of Structurally Harmful Quantum CircuitsTitle:](okf/papers/2026-09-19/2609.18965.md) | BadQubits: An LLM-Based Framework for Static Pre-Execution Structurally Harmful Quantum CircuitsTitle:の検出 | N/A | `cs.CR` | [arXiv](https://arxiv.org/abs/2609.18965) |
| 2026-09-19 | `2609.19021` | [Context-Aware Operational Security for Autonomous DronesTitle:](okf/papers/2026-09-19/2609.19021.md) | Context-Aware Operational Security for Autonomous DronesTitle:（セキュリティ分析論文） | N/A | `cs.CR` | [arXiv](https://arxiv.org/abs/2609.19021) |
| 2026-09-19 | `2609.19036` | [Structural Decomposability of Encrypted Traffic Side-Channel LeakageTitle:](okf/papers/2026-09-19/2609.19036.md) | Structural Decomposability of Encrypted Traffic Side-Channel LeakageTitle:（セキュリティ分析論文） | N/A | `cs.CR` | [arXiv](https://arxiv.org/abs/2609.19036) |
| 2026-09-19 | `2609.19091` | [When Agents Look Like Beacons: NIDS Evasion by Model Context Protocol TrafficTitle:](okf/papers/2026-09-19/2609.19091.md) | When Agents Look Like Beacons: NIDS Evasion by Model Context Protocol TrafficTitle:（セキュリティ分析論文） | N/A | `cs.CR` | [arXiv](https://arxiv.org/abs/2609.19091) |
| 2026-09-19 | `2609.19100` | [Characterizing Network Centralization and Observability in the Remote MCP EcosystemTitle:](okf/papers/2026-09-19/2609.19100.md) | Characterizing Network Centralization and Observability in the Remote MCP EcosystemTitle:（セキュリティ分析論文） | N/A | `cs.CR` | [arXiv](https://arxiv.org/abs/2609.19100) |
| 2026-09-19 | `2609.19111` | [Analog Pin Directionality as an Exfiltration Attack Surface in Mixed-Signal ICsTitle:](okf/papers/2026-09-19/2609.19111.md) | Analog Pin Directionality as an Exfiltration Attack Surface in Mixed-Signal ICsTitle:（セキュリティ分析論文） | N/A | `cs.CR` | [arXiv](https://arxiv.org/abs/2609.19111) |
| 2026-09-19 | `2609.19140` | [AgentLSD: Evaluating AI Security Agents Under Adversarial Task ContaminationTitle:](okf/papers/2026-09-19/2609.19140.md) | AgentLSD: Evaluating AI Security Agents Under Adversarial Task ContaminationTitle:（セキュリティ分析論文） | N/A | `cs.CR` | [arXiv](https://arxiv.org/abs/2609.19140) |
| 2026-09-19 | `2609.19201` | [EvoSherlock: Towards Agentic Lifelong Evolution for Unseen Long-Tailed Security-Critical Events in VideosTitle:](okf/papers/2026-09-19/2609.19201.md) | EvoSherlock: Agentic Lifelong Evolution for Unseen Long-Tailed Security-Critical Events in VideosTitle:に向けて | N/A | `cs.CR` | [arXiv](https://arxiv.org/abs/2609.19201) |
| 2026-09-19 | `2609.19226` | [PAPC: Platform Mediation for Privacy-Propagation Externalities in AI-Mediated WorkflowsTitle:](okf/papers/2026-09-19/2609.19226.md) | PAPC: Platform Mediation for Privacy-Propagation Externalities in AI-Mediated WorkflowsTitle:（セキュリティ分析論文） | N/A | `cs.CR` | [arXiv](https://arxiv.org/abs/2609.19226) |
| 2026-09-19 | `2609.19241` | [Robust Conformal Intrusion Detection via Traffic-Aware Calibration and Attack-Orbit InvarianceTitle:](okf/papers/2026-09-19/2609.19241.md) | Robust Conformal Intrusion Detection via Traffic-Aware Calibration and Attack-Orbit InvarianceTitle:（セキュリティ分析論文） | N/A | `cs.CR` | [arXiv](https://arxiv.org/abs/2609.19241) |
| 2026-09-19 | `2609.19325` | [AUDITPLAN: Commit, Then Answer for Auditable Safety AlignmentTitle:](okf/papers/2026-09-19/2609.19325.md) | AUDITPLAN: Commit, Then Answer for Auditable Safety AlignmentTitle:（セキュリティ分析論文） | N/A | `cs.CR` | [arXiv](https://arxiv.org/abs/2609.19325) |
| 2026-09-19 | `2609.19353` | [Scaling Zero Knowledge UNSAT Verification via Normalized ChainingTitle:](okf/papers/2026-09-19/2609.19353.md) | Scaling Zero Knowledge UNSAT Verification via Normalized ChainingTitle:（セキュリティ分析論文） | N/A | `cs.CR` | [arXiv](https://arxiv.org/abs/2609.19353) |
| 2026-09-19 | `2609.19391` | [MAGS: Multi-agent Auto-formalization Guarantees Safety for Agentic OutputsTitle:](okf/papers/2026-09-19/2609.19391.md) | MAGS: Multi-agent Auto-formalization Guarantees Safety for Agentic OutputsTitle:（セキュリティ分析論文） | N/A | `cs.CR` | [arXiv](https://arxiv.org/abs/2609.19391) |
| 2026-09-19 | `2609.19425` | [Closed-World Resolution Against Tool Hallucination in LLM AgentsTitle:](okf/papers/2026-09-19/2609.19425.md) | Closed-World Resolution Against Tool Hallucination in LLMエージェントTitle: | N/A | `cs.CR` | [arXiv](https://arxiv.org/abs/2609.19425) |
| 2026-09-19 | `2609.19456` | [Beyond Private Training: The New Landscape of AI PrivacyTitle:](okf/papers/2026-09-19/2609.19456.md) | Beyond Private Training: The New Landscape of AI PrivacyTitle:（セキュリティ分析論文） | N/A | `cs.CR` | [arXiv](https://arxiv.org/abs/2609.19456) |
| 2026-09-19 | `2609.19472` | [Safety Beyond the Interface: Detecting Harm via Latent States in Large Language ModelsTitle:](okf/papers/2026-09-19/2609.19472.md) | Safety Beyond the Interface: Detecting Harm via Latent States in 大規模言語モデルTitle: | N/A | `cs.CR` | [arXiv](https://arxiv.org/abs/2609.19472) |
| 2026-09-19 | `2609.19556` | [Cyber Exodus: Burnout Symptoms, Exit Intention, and Peer Response in Online Cybersecurity CommunitiesTitle:](okf/papers/2026-09-19/2609.19556.md) | Cyber Exodus: Burnout Symptoms, Exit Intention, and Peer Response in Online サイバーセキュリティ CommunitiesTitle: | N/A | `cs.CR` | [arXiv](https://arxiv.org/abs/2609.19556) |
| 2026-09-19 | `2609.19587` | [Red-Teaming Auto Mode: Improving Blocking Classifiers Against Malign Coding AgentsTitle:](okf/papers/2026-09-19/2609.19587.md) | Red-Teaming Auto Mode: Improving Blocking Classifiers Against Malign Coding AgentsTitle:（セキュリティ分析論文） | N/A | `cs.CR` | [arXiv](https://arxiv.org/abs/2609.19587) |
| 2026-09-19 | `2609.19640` | [A Policy Profile for Croissant: Refusal as a Property of the DatasetTitle:](okf/papers/2026-09-19/2609.19640.md) | A Policy Profile for Croissant: Refusal as a Property of the DatasetTitle:（セキュリティ分析論文） | N/A | `cs.CR` | [arXiv](https://arxiv.org/abs/2609.19640) |
| 2026-09-19 | `2609.19705` | [SoK: Trading Agents or Market Crashers? Dissecting Robustness and Security Failures in Academic Financial LLM Trading SchemesTitle:](okf/papers/2026-09-19/2609.19705.md) | SoK: Trading Agents or Market Crashers? Dissecting Robustness and Security Failures in Academic Financial LLM Trading SchemesTitle:（セキュリティ分析論文） | N/A | `cs.CR` | [arXiv](https://arxiv.org/abs/2609.19705) |
| 2026-09-19 | `2609.19720` | [Reachability, Not Observation: Containing Systems Whose Wiring ChangesTitle:](okf/papers/2026-09-19/2609.19720.md) | Reachability, Not Observation: Containing Systems Whose Wiring ChangesTitle:（セキュリティ分析論文） | N/A | `cs.CR` | [arXiv](https://arxiv.org/abs/2609.19720) |
| 2026-09-19 | `2609.19722` | [ALIBI: Adversarial Legitimacy Injection in Binary Input against LLM Malware AnalyzersTitle:](okf/papers/2026-09-19/2609.19722.md) | ALIBI: Adversarial Legitimacy Injection in Binary Input against LLM Malware AnalyzersTitle:（セキュリティ分析論文） | N/A | `cs.CR` | [arXiv](https://arxiv.org/abs/2609.19722) |
| 2026-09-19 | `2609.19791` | [Sybil-TraceGuard: Traceability-enhanced Sybil Guardian for Connected and Autonomous Vehicles Using Dynamic Semi-supervised GNNTitle:](okf/papers/2026-09-19/2609.19791.md) | Sybil-TraceGuard: Traceability-enhanced Sybil Guardian for Connected and 自動運転車両 Using Dynamic Semi-supervised GNNTitle: | N/A | `cs.CR` | [arXiv](https://arxiv.org/abs/2609.19791) |
| 2026-09-19 | `2609.19844` | [Trust, but Validate the Instrument: Auditing AI-Generated RTL Verification Plans on Authored Security-Regression ProxiesTitle:](okf/papers/2026-09-19/2609.19844.md) | Trust, but Validate the Instrument: Auditing AI-Generated RTL Verification Plans on Authored Security-Regression ProxiesTitle:（セキュリティ分析論文） | N/A | `cs.CR` | [arXiv](https://arxiv.org/abs/2609.19844) |
| 2026-09-19 | `2609.19892` | [ClashBench: Conflicts Leading Agents to Seize and HarmTitle:](okf/papers/2026-09-19/2609.19892.md) | ClashBench: Conflicts Leading Agents to Seize and HarmTitle:（セキュリティ分析論文） | N/A | `cs.CR` | [arXiv](https://arxiv.org/abs/2609.19892) |
| 2026-09-19 | `2609.19893` | [Hopper: Bounded-Memory Collaborative Debiasing for Byzantine-Tolerant Peer SamplingTitle:](okf/papers/2026-09-19/2609.19893.md) | Hopper: Bounded-Memory Collaborative Debiasing for Byzantine-Tolerant Peer SamplingTitle:（セキュリティ分析論文） | N/A | `cs.CR` | [arXiv](https://arxiv.org/abs/2609.19893) |
| 2026-09-19 | `2609.19900` | [Delphi Scanner: efficient and interpretable static malware detection via API sequence modelingTitle:](okf/papers/2026-09-19/2609.19900.md) | Delphi Scanner: efficient and interpretable static マルウェア検出 via API sequence modelingTitle: | N/A | `cs.CR` | [arXiv](https://arxiv.org/abs/2609.19900) |
| 2026-09-19 | `2609.19920` | [Mind the Gap: How SBOM Specification Ambiguities Lead to Divergent Software Bills of Materials. An Empirical Tool StudyTitle:](okf/papers/2026-09-19/2609.19920.md) | Mind the Gap: How SBOM Specification Ambiguities Lead to Divergent Software Bills of Materials. An Empirical Tool StudyTitle:（セキュリティ分析論文） | N/A | `cs.CR` | [arXiv](https://arxiv.org/abs/2609.19920) |
| 2026-09-19 | `2609.19929` | [On the Leakage of Massey Secret Sharing Schemes under Linear ComputationsTitle:](okf/papers/2026-09-19/2609.19929.md) | On the Leakage of Massey Secret Sharing Schemes under Linear ComputationsTitle:（セキュリティ分析論文） | N/A | `cs.CR` | [arXiv](https://arxiv.org/abs/2609.19929) |
| 2026-09-19 | `2609.19977` | [JANUS: Denial-of-Service Attack Against Beam Hopping in LEO Satellite NetworksTitle:](okf/papers/2026-09-19/2609.19977.md) | JANUS: Denial-of-Service Attack Against Beam Hopping in LEO Satellite NetworksTitle:（セキュリティ分析論文） | N/A | `cs.CR` | [arXiv](https://arxiv.org/abs/2609.19977) |
| 2026-09-19 | `2609.20010` | [XIR: A Framework for Interoperability across Cross-Chain Protocols Based on a Verifiable Intermediate RepresentationTitle:](okf/papers/2026-09-19/2609.20010.md) | XIR: A Framework for Interoperability across Cross-Chain Protocols Based on a Verifiable Intermediate RepresentationTitle:（セキュリティ分析論文） | N/A | `cs.CR` | [arXiv](https://arxiv.org/abs/2609.20010) |
| 2026-09-19 | `2609.20069` | [Competition, Collusion, and Corruption: The Spectrum of MEV Attacks on DAG-Based BFT Consensus ProtocolsTitle:](okf/papers/2026-09-19/2609.20069.md) | Competition, Collusion, and Corruption: The Spectrum of MEV Attacks on DAG-Based BFT Consensus ProtocolsTitle:（セキュリティ分析論文） | N/A | `cs.CR` | [arXiv](https://arxiv.org/abs/2609.20069) |
| 2026-09-19 | `2609.20095` | [A Scalable Trust Discovery Architecture for the Internet of AgentsTitle:](okf/papers/2026-09-19/2609.20095.md) | A Scalable Trust Discovery Architecture for the Internet of AgentsTitle:（セキュリティ分析論文） | N/A | `cs.CR` | [arXiv](https://arxiv.org/abs/2609.20095) |
| 2026-09-19 | `2609.20188` | [ResumeShield: Channel Separation and an Open Benchmark for Indirect Prompt Injection in AI Resume ScreeningTitle:](okf/papers/2026-09-19/2609.20188.md) | ResumeShield: Channel Separation and an Open Benchmark for Indirect Prompt Injection in AI Resume ScreeningTitle:（セキュリティ分析論文） | N/A | `cs.CR` | [arXiv](https://arxiv.org/abs/2609.20188) |
| 2026-09-19 | `2609.20211` | [Silence Is Endorsement: Verification-Status Laundering in LLM Agent PipelinesTitle:](okf/papers/2026-09-19/2609.20211.md) | Silence Is Endorsement: Verification-Status Laundering in LLM Agent PipelinesTitle:（セキュリティ分析論文） | N/A | `cs.CR` | [arXiv](https://arxiv.org/abs/2609.20211) |
| 2026-09-19 | `2609.20314` | [DDQN-MLP: An Explainable and Adversarially Robust DRL-Guided Adaptive Learning Framework for Ransomware DetectionTitle:](okf/papers/2026-09-19/2609.20314.md) | DDQN-MLP: An Explainable and Adversarially Robust DRL-Guided Adaptive Learning Framework for Ransomware DetectionTitle:（セキュリティ分析論文） | N/A | `cs.CR` | [arXiv](https://arxiv.org/abs/2609.20314) |
| 2026-09-19 | `2609.20370` | [The More It Says, the More You Pay: A Black-Box Audit of Provider-Side Token Inflation in LLM ServicesTitle:](okf/papers/2026-09-19/2609.20370.md) | The More It Says, the More You Pay: A Black-Box Audit of Provider-Side Token Inflation in LLM ServicesTitle:（セキュリティ分析論文） | N/A | `cs.CR` | [arXiv](https://arxiv.org/abs/2609.20370) |
| 2026-09-19 | `2609.20386` | [Compact Vision Models for Iris Presentation Attack Detection under Presentation Attack Instrument Shift and Environmental DegradationTitle:](okf/papers/2026-09-19/2609.20386.md) | Compact Vision Models for Iris Presentation Attack Detection under Presentation Attack Instrument Shift and Environmental DegradationTitle:（セキュリティ分析論文） | N/A | `cs.CR` | [arXiv](https://arxiv.org/abs/2609.20386) |
| 2026-09-19 | `2609.20457` | [Fingerprinting Multimodal Large Language ModelsTitle:](okf/papers/2026-09-19/2609.20457.md) | Fingerprinting Multimodal 大規模言語モデルTitle: | N/A | `cs.CR` | [arXiv](https://arxiv.org/abs/2609.20457) |
| 2026-09-19 | `2609.20480` | [Worst-Case Hidden-Vehicle Trajectory Search in Spatiotemporal Occlusion RegionsTitle:](okf/papers/2026-09-19/2609.20480.md) | Worst-Case Hidden-Vehicle Trajectory Search in Spatiotemporal Occlusion RegionsTitle:（セキュリティ分析論文） | N/A | `cs.CR` | [arXiv](https://arxiv.org/abs/2609.20480) |
| 2026-09-19 | `2609.20532` | [Towards TEE-Certified DP: Verifiable Differentially Private Training on Legacy GPUsTitle:](okf/papers/2026-09-19/2609.20532.md) | TEE-Certified DP: Verifiable Differentially Private Training on Legacy GPUsTitle:に向けて | N/A | `cs.CR` | [arXiv](https://arxiv.org/abs/2609.20532) |
| 2026-09-19 | `2609.20561` | [Empirical Analysis of Randomness Quality in Differential Privacy MechanismsTitle:](okf/papers/2026-09-19/2609.20561.md) | Empirical Randomness Quality in Differential Privacy MechanismsTitle:の分析 | N/A | `cs.CR` | [arXiv](https://arxiv.org/abs/2609.20561) |
| 2026-09-19 | `2609.20601` | [Weather Data Spoofing Attacks on Rain-Adaptive Millimeter-Wave Frequency Selection in V2X Communication NetworksTitle:](okf/papers/2026-09-19/2609.20601.md) | Weather Data Spoofing Attacks on Rain-Adaptive Millimeter-Wave Frequency Selection in V2X Communication NetworksTitle:（セキュリティ分析論文） | N/A | `cs.CR` | [arXiv](https://arxiv.org/abs/2609.20601) |
| 2026-09-19 | `2609.20614` | [Inference-Engine Fingerprinting Attacks are Practical: Exploring Model-Driven Environmental Discovery, Exploitation, and EscapeTitle:](okf/papers/2026-09-19/2609.20614.md) | Inference-Engine Fingerprinting Attacks are Practical: Exploring Model-Driven Environmental Discovery, Exploitation, and EscapeTitle:（セキュリティ分析論文） | N/A | `cs.CR` | [arXiv](https://arxiv.org/abs/2609.20614) |
| 2026-09-19 | `2609.20650` | [Multi-center Medical Data Mining with FL-Net - A One-stop Shop for Federated LearningTitle:](okf/papers/2026-09-19/2609.20650.md) | Multi-center Medical Data Mining with FL-Net - A One-stop Shop for 連合学習Title: | N/A | `cs.CR` | [arXiv](https://arxiv.org/abs/2609.20650) |

---

> 💡 **全論文の検索・閲覧について**:
> 全件のインタラクティブ検索およびフィルタリングは [Web コンソール](../site/index.html)、
> 全件メタデータの一括処理には [papers_catalog.json](database/papers_catalog.json) をご利用いただけます。
