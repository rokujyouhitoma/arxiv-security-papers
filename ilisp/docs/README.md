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

## ドキュメント体系

- [SPEC_R7RS.md](SPEC_R7RS.md): R7RS-small 仕様準拠マトリクス・Scope Sets・TCO 仕様
- [BOOTSTRAP.md](BOOTSTRAP.md): Kernel ILISP 仕様 & 3段階セルフホスティング連鎖仕様
- [DSN-31 包括設計仕様書](../../docs/designs/DSN-31-ilisp_r7rs_intelligence_lisp_architecture_specification.md): 包括アーキテクチャ設計書
