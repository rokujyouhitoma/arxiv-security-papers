# ILISP (Intelligence LISP)

> **Next-Generation AI-Native Lisp Dialect adhering to R7RS-small Scheme with 3-Pillar Architecture (Python-Interop AST, Native C99-AOT, and Standalone Rust-VM Backends).**

ILISP (Intelligence LISP) は、知性・脅威インテリジェンス（Intelligence）、創設者の哲学（IKE）、そして人工知能（AI）を象徴するモダンな Lisp 方言です。

世界標準規格 **R7RS-small Scheme** を中核仕様として採用し、Python の広大な AI/NLP エコシステムとゼロコピーで双方向連携できる **Python AST モード**、外部依存ゼロでミリ秒起動・単一バイナリ配布を可能にする **Native C99-AOT モード (Clang/LLVM 最適化)**、および将来の No-GIL マルチコア並列処理を担う **Rust Standalone VM** の「3本柱」を備えています。

---

## 主な特徴 (Key Highlights)

1. **R7RS-small Scheme 世界標準準拠**:
   - `define-library` によるモジュール管理、**Scope Sets アルゴリズム** による数学的に安全な衛生的マクロ (`syntax-rules`)、**ハイブリッド TCO**（自己末尾ループ化＋相互呼出トランポリン）、階層的継続 (`call/cc`) を完備。
2. **摩擦ゼロ・ゼロコピー Python 相互運用 (Zero-Copy Interop)**:
   - **Lazy View / Opaque Wrapper**: Python の動的配列やジェネレータを $O(N)$ コピーせず $O(1)$ で直接走査。
   - ILISP から PyPI の全ライブラリ（`torch`, `transformers`, `arxiv` 等）を透過的に直接インポート・呼び出し可能。
   - Python からも通常通り `import my_ilisp_module` として ILISP コードをシームレスに利用可能。
3. **3本柱の柔軟な実行バックエンド**:
   - **Backend A (Python AST)**: 開発 DX と対話型 REPL、Python ライブラリ直接結合。
   - **Backend B (Native C99 AOT)**: 外部依存ゼロの C99 を生成し、`clang -O3` で LLVM 最適化。自己完結型 ARC メモリ管理。
   - **Backend C (Rust Standalone VM)**: 64bit NaN-Boxing 値表現、No-GIL マルチコア並列処理、PyO3 ネイティブ拡張。
4. **現場復帰型コンディションシステム (Conditions & Restarts)**:
   - スタックを巻き戻さずに例外発生現場で回復手段（リトライ、RSSフォールバック等）を上位から注入可能。
   - `boundary-guard` により、Python 側の例外発生時にも再試行 Thunk を保持して回復可能。
5. **完全セルフホスティング（Bootstrap Chain）対応**:
   - **Kernel ILISP（6大基本式核）** を先行定義し、Stage-0 (Python host) から Stage-2 への自己完結ブートストラップ連鎖と不動点検証をビルトイン。
6. **chibi-scheme 公式 R7RS 適合性テストスイート 100% 完全合格**:
   - Alex Shinn 氏によるリファレンス実装 chibi-scheme のテスト全 1,233 項目において **100.0% PASS（0 FAIL / 0 ERROR）** を達成。独自テストハーネス（MIT License）と上流テスト（3-Clause BSD）を物理的に完全分離管理。

---

## クイックスタート (Quickstart Preview)

### 基本的な式と Python Interop
```scheme
;; (scheme base) と Python 相互運用ライブラリの利用
(import (scheme base)
        (scheme write)
        (ilisp python))

;; Python モジュールのインポート
(import-python (math sqrt)
               (pathlib Path))

;; 関数定義とスレッディングマクロ
(define (analyze-numbers lst)
  (|>> lst
       (filter (lambda (x) (> x 0)))
       (map (lambda (x) (py-call sqrt x)))))

(display (analyze-numbers '(-4 9 -1 16 25)))
;; => (3.0 4.0 5.0)
```

---

## 適合性テスト・品質検証の実行

ILISP は以下のコマンドで、chibi-scheme 公式 R7RS テストスイート（1,233 項目）およびプロジェクト内回帰テスト（372 項目）を自律実行・機械検証できます：

```bash
# 1. chibi-scheme 公式 R7RS 適合性テスト (1,233 項目 100% PASS 検証)
PYTHONPATH=. .venv/bin/pytest tests/ilisp/test_chibi_r7rs_compliance.py -s

# 2. ILISP 全回帰テストスイート (372 項目 100% PASS 検証)
PYTHONPATH=. .venv/bin/pytest tests/ilisp -q

# 3. 静的解析・型検査・コードフォーマット品質ゲート
flake8 ilisp tests/ilisp
mypy --strict ilisp
make check_format
```

---

## 自己完結ドキュメント体系

ILISP サブシステムの包括的な仕様・アーキテクチャ・利用ガイドは以下のドキュメント群にまとめられています：

- **[SPEC_R7RS.md](SPEC_R7RS.md)**: R7RS-small 全203機能の仕様準拠マトリクス & chibi-scheme 公式テスト 100% 適合検証レポート
- **[PYTHON_INTEROP.md](PYTHON_INTEROP.md)**: Python 双方向ゼロコピー相互運用プロトコル (`SequenceView`, `import-python`, `py-call`)
- **[MACROS_AND_CONDITIONS.md](MACROS_AND_CONDITIONS.md)**: Scope Sets 衛生的マクロ (`syntax-rules`) & 現場復帰型コンディション & テストハーネス仕様
- **[BOOTSTRAP.md](BOOTSTRAP.md)**: Kernel ILISP 最小核仕様 & 3段階セルフホスティング連鎖 & 不動点検証
- **[DSN-31 包括設計仕様書](../../docs/designs/DSN-31-ilisp_r7rs_intelligence_lisp_architecture_specification.md)**: ILISP R7RS コアアーキテクチャ包括設計仕様書（リポジトリ公式 DSN）
