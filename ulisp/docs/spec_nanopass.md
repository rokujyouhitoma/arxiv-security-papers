[ULisp トップ](../README.md) > [ドキュメント一覧](README.md) > **Nanopass Framework 言語仕様書**

---

# ULisp Nanopass Framework 言語仕様書 (Language Specifications)

本書は `ulisp/tools/generate_nanopass_docs.scm` (`make -C ulisp docs_nanopass`) により、登録済みの中間言語メタ情報（Scheme Frontend / StagePoly / C99 AST / Core & Managed LIR / Backend ISA）から自動生成された仕様ドキュメントです。

- **関連仕様書**:
  - [パイプライン・Nanopass 詳細仕様書](spec_pipeline.md)
  - [低レベル IR (LIR) 正典仕様書](spec_lir.md)
  - [バックエンド & コード生成仕様書](spec_backend.md)
  - [テスト実行ガイド](guide_testing.md)

---

## 1. 言語継承・構文遷移図 (Language Derivation Graph)

```mermaid
graph TD
    L_cst["L_cst"]
    L_src["L_src"]
    L_cst --> L_src
    L_core["L_core"]
    L_src --> L_core
    L_anf["L_anf"]
    L_core --> L_anf
    L_lifted["L_lifted"]
    L_anf --> L_lifted
    L-StagePoly["L-StagePoly"]
    L-Residual-ANF["L-Residual-ANF"]
    L-StagePoly --> L-Residual-ANF
    L_lir_core["L_lir_core"]
    L_lir_managed["L_lir_managed"]
    L_lir_core --> L_lir_managed
    L_lir_raw["L_lir_raw"]
    L_lir_canonical["L_lir_canonical"]
    L_lir_raw --> L_lir_canonical
    L_asm_x86["L_asm_x86"]
    L_asm_aarch64["L_asm_aarch64"]
    L_c_ast["L_c_ast"]
    L_c_typed["L_c_typed"]
    L_c_ast --> L_c_typed
```

## 2. 各言語の詳細定義 (Language Definitions)

### 言語: `L_cst`

- **親言語 (Parent)**: (ルート言語)
- **エントリ非終端記号 (Entry)**: `Program`
- **Nongenerative ID**: `#f`

#### 終端記号 (Terminals)

| 述語 (Predicate) | メタ変数パターン (Meta-Variables) |
| :--- | :--- |
| `symbol` | `(x lbl var)` |
| `constant` | `(c)` |

#### 非終端記号とプロダクション規則 (Nonterminals & Productions)

##### `Def` (d)

```scheme
  (define-library (x ...) d ...)
  (import d ...)
  (export x ...)
  (include c)
  (include-ci c)
  (define-syntax x e)
  (define-language x d ...)
  (define-pass x d ...)
  (define-picopass x d ...)
  (define-femtopass x d ...)
  (define-attopass x d ...)
  (define x e)
  (define (x x1 ...) e ...)
  e
```

##### `Expr` (e)

```scheme
  x
  c
  'datum
  `datum
  (let-syntax ((x e1) ...) e ...)
  (letrec-syntax ((x e1) ...) e ...)
  (syntax-rules (x ...) (e1 e2) ...)
  (if e1 e2 e3)
  (if e1 e2)
  (begin e ...)
  (lambda (x ...) e ...)
  (set! x e)
  (let ((x e1) ...) e ...)
  (let x ((x1 e1) ...) e ...)
  (letrec ((x e1) ...) e ...)
  (letrec* ((x e1) ...) e ...)
  (let* ((x e1) ...) e ...)
  (do ((x e1 e2) ...) (e_test e_res ...) e_cmd ...)
  (cond (e1 e2) ... (else e_else))
  (cond-expand (e1 e2 ...) ...)
  (case key (dat e ...) ... (else e_else))
  (and e ...)
  (or e ...)
  (when e1 e2 ...)
  (unless e1 e2 ...)
  (delay e)
  (delay-force e)
  (list e ...)
  (vector e ...)
  (bytevector e ...)
  (vector-append e ...)
  (bytevector-append e ...)
  (string-append e ...)
  (guard (x c ...) e ...)
  (let-values (((x ...) e1) ...) e ...)
  (let*-values (((x ...) e1) ...) e ...)
  (parameterize ((x e1) ...) e ...)
  (define x e)
  (define (x x1 ...) e ...)
  (e0 e1 ...)
```

##### `Program` (p)

```scheme
  (%program (d ...) e)
  d
  e
```

---

### 言語: `L_src`

- **親言語 (Parent)**: `L_cst`
- **エントリ非終端記号 (Entry)**: `Program`
- **Nongenerative ID**: `L_cst->L_src`

#### 終端記号 (Terminals)

| 述語 (Predicate) | メタ変数パターン (Meta-Variables) |
| :--- | :--- |
| `symbol` | `(x lbl var)` |
| `constant` | `(c)` |

#### 非終端記号とプロダクション規則 (Nonterminals & Productions)

##### `Def` (d)

```scheme
  (define x e)
  (define (x x1 ...) e ...)
  e
```

##### `Expr` (e)

```scheme
  x
  c
  'datum
  `datum
  (if e1 e2 e3)
  (if e1 e2)
  (begin e ...)
  (lambda (x ...) e ...)
  (set! x e)
  (let ((x e1) ...) e ...)
  (let x ((x1 e1) ...) e ...)
  (letrec ((x e1) ...) e ...)
  (letrec* ((x e1) ...) e ...)
  (let* ((x e1) ...) e ...)
  (do ((x e1 e2) ...) (e_test e_res ...) e_cmd ...)
  (cond (e1 e2) ... (else e_else))
  (cond-expand (e1 e2 ...) ...)
  (case key (dat e ...) ... (else e_else))
  (and e ...)
  (or e ...)
  (when e1 e2 ...)
  (unless e1 e2 ...)
  (delay e)
  (delay-force e)
  (list e ...)
  (vector e ...)
  (bytevector e ...)
  (vector-append e ...)
  (bytevector-append e ...)
  (string-append e ...)
  (guard (x c ...) e ...)
  (let-values (((x ...) e1) ...) e ...)
  (let*-values (((x ...) e1) ...) e ...)
  (parameterize ((x e1) ...) e ...)
  (define x e)
  (define (x x1 ...) e ...)
  (e0 e1 ...)
```

##### `Program` (p)

```scheme
  (%program (d ...) e)
  d
  e
```

#### 削除・排除された不変条件 (Removed Invariants)

本言語では以下の構文が明示的に禁止・脱糖済みとして排除されています：

- `define-library`
- `import`
- `export`
- `include`
- `include-ci`
- `define-syntax`
- `define-language`
- `define-pass`
- `define-picopass`
- `define-femtopass`
- `define-attopass`
- `let-syntax`
- `letrec-syntax`
- `syntax-rules`

---

### 言語: `L_core`

- **親言語 (Parent)**: `L_src`
- **エントリ非終端記号 (Entry)**: `Program`
- **Nongenerative ID**: `L_src->L_core`

#### 終端記号 (Terminals)

| 述語 (Predicate) | メタ変数パターン (Meta-Variables) |
| :--- | :--- |
| `symbol` | `(x lbl var)` |
| `constant` | `(c)` |

#### 非終端記号とプロダクション規則 (Nonterminals & Productions)

##### `Def` (d)

```scheme
  (define x e)
  e
```

##### `Expr` (e)

```scheme
  x
  c
  'datum
  (if e1 e2 e3)
  (if e1 e2)
  (begin e ...)
  (lambda (x ...) e ...)
  (set! x e)
  (let ((x e1) ...) e ...)
  (letrec ((x e1) ...) e ...)
  (define x e)
  (e0 e1 ...)
```

##### `Program` (p)

```scheme
  (%program (d ...) e)
  d
  e
```

#### 削除・排除された不変条件 (Removed Invariants)

本言語では以下の構文が明示的に禁止・脱糖済みとして排除されています：

- `quasiquote`
- `letrec*`
- `let*`
- `do`
- `cond`
- `cond-expand`
- `case`
- `and`
- `or`
- `when`
- `unless`
- `delay`
- `delay-force`
- `list`
- `vector`
- `bytevector`
- `vector-append`
- `bytevector-append`
- `string-append`
- `guard`
- `let-values`
- `let*-values`
- `parameterize`
- `define-library`
- `import`
- `export`
- `include`
- `include-ci`
- `define-syntax`
- `define-language`
- `define-pass`
- `define-picopass`
- `define-femtopass`
- `define-attopass`
- `let-syntax`
- `letrec-syntax`
- `syntax-rules`

---

### 言語: `L_anf`

- **親言語 (Parent)**: `L_core`
- **エントリ非終端記号 (Entry)**: `Program`
- **Nongenerative ID**: `L_core->L_anf`

#### 終端記号 (Terminals)

| 述語 (Predicate) | メタ変数パターン (Meta-Variables) |
| :--- | :--- |
| `symbol` | `(x lbl var)` |
| `constant` | `(c)` |

#### 非終端記号とプロダクション規則 (Nonterminals & Productions)

##### `Def` (d)

```scheme
  (define x e)
  e
```

##### `Expr` (e)

```scheme
  (begin e ...)
  (lambda (x ...) e ...)
  (set! x e)
  (let ((x e1) ...) e ...)
  (letrec ((x e1) ...) e ...)
  a
  (if a e1 e2)
  (if a e1)
  (%make-closure a1 a ...)
  (%make-closure-env a1 a ...)
  (%closure-ref a c)
  (%closure-set! a1 c a2)
  (%cont-fun x (x ...) e1 e2)
  (%cont-call x a ...)
  (%with-handler a1 a2)
  (%raw-call/cc a)
  (%call-with-values a1 a2)
  (%values a ...)
  (%direct-call a1 a ...)
  (%global-ref x)
  (%global-set! x e)
  (a0 a ...)
```

##### `Program` (p)

```scheme
  (%program (d ...) e)
  e
```

##### `Atom` (a)

```scheme
  x
  lbl
  var
  c
  'datum
  (%closure-ref a c)
  (%global-ref x)
```

#### 削除・排除された不変条件 (Removed Invariants)

本言語では以下の構文が明示的に禁止・脱糖済みとして排除されています：

- `quasiquote`
- `letrec*`
- `let*`
- `do`
- `cond`
- `cond-expand`
- `case`
- `and`
- `or`
- `when`
- `unless`
- `delay`
- `delay-force`
- `list`
- `vector`
- `bytevector`
- `vector-append`
- `bytevector-append`
- `string-append`
- `guard`
- `let-values`
- `let*-values`
- `parameterize`
- `define-library`
- `import`
- `export`
- `include`
- `include-ci`
- `define-syntax`
- `define-language`
- `define-pass`
- `define-picopass`
- `define-femtopass`
- `define-attopass`
- `let-syntax`
- `letrec-syntax`
- `syntax-rules`

---

### 言語: `L_lifted`

- **親言語 (Parent)**: `L_anf`
- **エントリ非終端記号 (Entry)**: `Program`
- **Nongenerative ID**: `L_anf->L_lifted`

#### 終端記号 (Terminals)

| 述語 (Predicate) | メタ変数パターン (Meta-Variables) |
| :--- | :--- |
| `symbol` | `(x lbl var)` |
| `constant` | `(c)` |

#### 非終端記号とプロダクション規則 (Nonterminals & Productions)

##### `Def` (d)

```scheme
  (define x e)
  e
```

##### `Expr` (e)

```scheme
  (begin e ...)
  (set! x e)
  (let ((x e1) ...) e ...)
  (letrec ((x e1) ...) e ...)
  a
  (if a e1 e2)
  (if a e1)
  (%make-closure a1 a ...)
  (%make-closure-env a1 a ...)
  (%closure-ref a c)
  (%closure-set! a1 c a2)
  (%cont-fun x (x ...) e1 e2)
  (%cont-call x a ...)
  (%with-handler a1 a2)
  (%raw-call/cc a)
  (%call-with-values a1 a2)
  (%values a ...)
  (%direct-call a1 a ...)
  (%global-ref x)
  (%global-set! x e)
  (a0 a ...)
  (if e1 e2 e3)
  (if e1 e2)
  (%direct-call a1 e ...)
  (annotate x e)
  (%stack-cons a1 a2)
  (%box-fixnum e)
  (%unbox-fixnum e)
  (e0 e1 ...)
```

##### `Program` (p)

```scheme
  e
  (%program (fn ...) e)
```

##### `Atom` (a)

```scheme
  x
  lbl
  var
  c
  'datum
  (%closure-ref a c)
  (%global-ref x)
  (%unbox-fixnum a)
```

##### `FunctionDecl` (fn)

```scheme
  (%function x (x ...) e)
```

#### 削除・排除された不変条件 (Removed Invariants)

本言語では以下の構文が明示的に禁止・脱糖済みとして排除されています：

- `lambda`
- `quasiquote`
- `letrec*`
- `let*`
- `do`
- `cond`
- `cond-expand`
- `case`
- `and`
- `or`
- `when`
- `unless`
- `delay`
- `delay-force`
- `list`
- `vector`
- `bytevector`
- `vector-append`
- `bytevector-append`
- `string-append`
- `guard`
- `let-values`
- `let*-values`
- `parameterize`
- `define-library`
- `import`
- `export`
- `include`
- `include-ci`
- `define-syntax`
- `define-language`
- `define-pass`
- `define-picopass`
- `define-femtopass`
- `define-attopass`
- `let-syntax`
- `letrec-syntax`
- `syntax-rules`

---

### 言語: `L-StagePoly`

- **親言語 (Parent)**: (ルート言語)
- **エントリ非終端記号 (Entry)**: `Expr`
- **Nongenerative ID**: `#f`

#### 終端記号 (Terminals)

| 述語 (Predicate) | メタ変数パターン (Meta-Variables) |
| :--- | :--- |
| `symbol` | `(x var lbl call-target)` |
| `constant` | `(c)` |
| `primitive` | `(prim)` |

#### 非終端記号とプロダクション規則 (Nonterminals & Productions)

##### `Expr` (e body)

```scheme
  x
  c
  (if e0 e1 e2)
  (let ((x e)) body)
  (lambda (x ...) body)
  (prim e ...)
  (call e0 e1 ...)
  (stage-now e)
  (stage-later e)
  (stage-lift e)
  (stage-quasiquote e)
```

---

### 言語: `L-Residual-ANF`

- **親言語 (Parent)**: `L-StagePoly`
- **エントリ非終端記号 (Entry)**: `Expr`
- **Nongenerative ID**: `L-StagePoly->L-Residual-ANF`

#### 終端記号 (Terminals)

| 述語 (Predicate) | メタ変数パターン (Meta-Variables) |
| :--- | :--- |
| `symbol` | `(x var lbl call-target)` |
| `constant` | `(c)` |
| `primitive` | `(prim)` |

#### 非終端記号とプロダクション規則 (Nonterminals & Productions)

##### `Expr` (e body)

```scheme
  x
  c
  (if e0 e1 e2)
  (lambda (x ...) body)
  (prim e ...)
  (let-anf ((x (prim e-atom ...))) body)
  (let-call ((x (call-target e-atom ...))) body)
  (atom-value e-atom)
```

##### `Atom` (e-atom)

```scheme
  x
  c
```

#### 削除・排除された不変条件 (Removed Invariants)

本言語では以下の構文が明示的に禁止・脱糖済みとして排除されています：

- `stage-now`
- `stage-later`
- `stage-lift`
- `stage-quasiquote`
- `call`
- `let`

---

### 言語: `L_lir_core`

- **親言語 (Parent)**: (ルート言語)
- **エントリ非終端記号 (Entry)**: `Program`
- **Nongenerative ID**: `#f`

#### 終端記号 (Terminals)

| 述語 (Predicate) | メタ変数パターン (Meta-Variables) |
| :--- | :--- |
| `symbol` | `(x lbl var cond_op sp_lbl mty)` |
| `integer` | `(n offset shift frame_size tag si cnt bitmap line col al_val)` |
| `string` | `(str fn_name)` |
| `boolean` | `(bool_val)` |

#### 非終端記号とプロダクション規則 (Nonterminals & Productions)

##### `Register` (reg)

```scheme
  %rax
  %rbx
  %rcx
  %rdx
  %rsi
  %rdi
  %rbp
  %rsp
  %r8
  %r9
  %r10
  %r11
  %r12
  %r13
  %r14
  %r15
  %al
  %xmm0
  %xmm1
  %xmm2
  %xmm3
  %xmm4
  %xmm5
  %xmm6
  %xmm7
  %xmm8
  %xmm9
  %xmm10
  %xmm11
  %xmm12
  %xmm13
  %xmm14
  %xmm15
  (%reg x)
  (%reg mty x)
  (%freg x)
```

##### `StackSlot` (stk)

```scheme
  (%stack offset)
```

##### `MemRef` (mem)

```scheme
  (%mem reg offset)
  (%mem reg reg)
```

##### `LValue` (lval)

```scheme
  reg
  stk
  mem
```

##### `Operand` (opnd)

```scheme
  lval
  n
  lbl
```

##### `AsmOutSpec` (asm_out)

```scheme
  (lval str)
  (x str)
  (x str lval)
```

##### `AsmInSpec` (asm_in)

```scheme
  (opnd str)
  (x str opnd)
```

##### `AsmClobber` (asm_clob)

```scheme
  str
  x
```

##### `AsmClause` (asm_clause)

```scheme
  (:outputs (asm_out ...))
  (:inputs (asm_in ...))
  (:clobbers (asm_clob ...))
  (:volatile? bool_val)
```

##### `Inst` (inst)

```scheme
  (%loc n line col)
  (%label lbl)
  (%block lbl (x ...) inst ...)
  (%jump lbl)
  (%jump lbl (opnd ...))
  (%jump-if-false reg lbl)
  (%jump-if-false reg lbl (opnd ...))
  (%jump-if reg lbl1 (opnd1 ...) lbl2 (opnd2 ...))
  (%jump-cond cond_op lbl)
  (%jump-cond str lbl)
  (%jump-if-zero lbl)
  (%direct-jump lbl)
  (%switch opnd lbl (opnd ...) (sc ...))
  (%switch opnd lbl (sc ...))
  (%return)
  (%return opnd)
  (%c-call fn_name shift)
  (%c-call fn_name shift al_val)
  (%call-foreign fn_name shift)
  (%call-foreign fn_name shift al_val)
  (%call-indirect reg shift)
  (%call-indirect reg shift al_val)
  (%call-closure shift)
  (%call-closure shift sp_lbl)
  (%call-closure shift str)
  (%direct-call lbl shift)
  (%direct-call lbl shift sp_lbl)
  (%direct-call lbl shift str)
  (%dispatch-consumer si1 si2 shift)
  (%mov lval opnd)
  (%load reg1 reg2 offset)
  (%store reg1 offset opnd)
  (%load-byte-zx reg1 reg2 offset)
  (%store-byte reg1 offset opnd)
  (%push reg)
  (%pop reg)
  (%code-ref reg lbl)
  (%str-ref reg lbl)
  (%global-ref reg var)
  (%global-addr reg var)
  (%global-set! var reg)
  (%add opnd1 opnd2)
  (%raw-add opnd1 opnd2)
  (%sub opnd1 opnd2)
  (%raw-sub opnd1 opnd2)
  (%imul opnd1 opnd2)
  (%raw-mul opnd1 opnd2)
  (%neg opnd)
  (%inc opnd)
  (%cqo)
  (%idiv opnd)
  (%shl opnd shift)
  (%shl opnd %rcx)
  (%shr opnd shift)
  (%shr opnd %rcx)
  (%shr reg opnd shift)
  (%shr reg opnd %rcx)
  (%sar opnd shift)
  (%sar opnd %rcx)
  (%bit-and opnd1 opnd2)
  (%bit-or opnd1 opnd2)
  (%bit-xor opnd1 opnd2)
  (%cmp opnd1 opnd2)
  (%raw-cmp opnd1 opnd2)
  (%set-boolean opnd cond_op)
  (%add-overflow reg1 reg2 opnd1 opnd2)
  (%sub-overflow reg1 reg2 opnd1 opnd2)
  (%mul-overflow reg1 reg2 opnd1 opnd2)
  (%udiv opnd)
  (%udiv reg opnd1 opnd2)
  (%urem opnd)
  (%urem reg opnd1 opnd2)
  (%setb reg)
  (%setb reg opnd1 opnd2)
  (%setbe reg)
  (%setbe reg opnd1 opnd2)
  (%seta reg)
  (%seta reg opnd1 opnd2)
  (%setae reg)
  (%setae reg opnd1 opnd2)
  (%load-typed mty reg1 reg2 offset)
  (%store-typed mty reg1 offset opnd)
  (%fmov reg1 reg2)
  (%fadd opnd1 opnd2)
  (%fsub opnd1 opnd2)
  (%fmul opnd1 opnd2)
  (%fdiv opnd1 opnd2)
  (%fcmp opnd1 opnd2)
  (%fneg mty reg1 opnd2)
  (%fpext mty reg1 opnd2)
  (%fptrunc mty reg1 opnd2)
  (%sitofp reg1 opnd2)
  (%uitofp reg1 opnd2)
  (%fptosi reg1 opnd2)
  (%fptoui reg1 opnd2)
  (%fcmp-oeq reg1 opnd2 opnd3)
  (%fcmp-une reg1 opnd2 opnd3)
  (%fcmp-olt reg1 opnd2 opnd3)
  (%fcmp-ole reg1 opnd2 opnd3)
  (%fcmp-ogt reg1 opnd2 opnd3)
  (%fcmp-oge reg1 opnd2 opnd3)
  (%trunc mty reg1 opnd2)
  (%zext mty reg1 opnd2)
  (%sext mty reg1 opnd2)
  (%syscall)
  (%syscall si)
  (%memory-fence)
  (%safepoint-poll)
  (%atomic-cas! reg1 reg2 reg3)
  (%inline-asm str asm_clause ...)
```

##### `StringEntry` (se)

```scheme
  (lbl str)
  (lbl (bytes n ...))
  (str1 str2)
```

##### `DataChunk` (dc)

```scheme
  n
  (zero n)
  (reloc lbl offset)
```

##### `DataEntry` (de)

```scheme
  (bss lbl al_val n)
  (bytes lbl al_val dc ...)
```

##### `SafepointEntry` (sm)

```scheme
  (lbl frame_size bitmap)
  (str frame_size bitmap)
```

##### `SwitchCase` (sc)

```scheme
  (opnd lbl)
  (opnd lbl (opnd ...))
```

##### `AliasEntry` (ae)

```scheme
  (lbl1 lbl2 bool_val)
```

##### `MetaClause` (mc)

```scheme
  (weak-fns (lbl ...))
  (weak-data (lbl ...))
  (aliases (ae ...))
  (top-asm (str ...))
```

##### `FunctionDecl` (f)

```scheme
  (%lir-function lbl (params (x ...)) (frame-size frame_size) (body inst ...))
```

##### `MainDecl` (m)

```scheme
  (%lir-main (frame-size frame_size) (body inst ...))
```

##### `Program` (p)

```scheme
  (%lir-program (strings (se ...)) (stackmaps (sm ...)) (%lir-functions f ...) m mc ...)
  (%lir-program (strings (se ...)) (data (de ...)) (stackmaps (sm ...)) (%lir-functions f ...) m mc ...)
```

---

### 言語: `L_lir_managed`

- **親言語 (Parent)**: `L_lir_core`
- **エントリ非終端記号 (Entry)**: `Program`
- **Nongenerative ID**: `L_lir_core->L_lir_managed`

#### 終端記号 (Terminals)

| 述語 (Predicate) | メタ変数パターン (Meta-Variables) |
| :--- | :--- |
| `symbol` | `(x lbl var cond_op sp_lbl mty)` |
| `integer` | `(n offset shift frame_size tag si cnt bitmap line col al_val)` |
| `string` | `(str fn_name)` |
| `boolean` | `(bool_val)` |

#### 非終端記号とプロダクション規則 (Nonterminals & Productions)

##### `Register` (reg)

```scheme
  %rax
  %rbx
  %rcx
  %rdx
  %rsi
  %rdi
  %rbp
  %rsp
  %r8
  %r9
  %r10
  %r11
  %r12
  %r13
  %r14
  %r15
  %al
  %xmm0
  %xmm1
  %xmm2
  %xmm3
  %xmm4
  %xmm5
  %xmm6
  %xmm7
  %xmm8
  %xmm9
  %xmm10
  %xmm11
  %xmm12
  %xmm13
  %xmm14
  %xmm15
  (%reg x)
  (%reg mty x)
  (%freg x)
```

##### `StackSlot` (stk)

```scheme
  (%stack offset)
```

##### `MemRef` (mem)

```scheme
  (%mem reg offset)
  (%mem reg reg)
```

##### `LValue` (lval)

```scheme
  reg
  stk
  mem
```

##### `Operand` (opnd)

```scheme
  lval
  n
  lbl
```

##### `AsmOutSpec` (asm_out)

```scheme
  (lval str)
  (x str)
  (x str lval)
```

##### `AsmInSpec` (asm_in)

```scheme
  (opnd str)
  (x str opnd)
```

##### `AsmClobber` (asm_clob)

```scheme
  str
  x
```

##### `AsmClause` (asm_clause)

```scheme
  (:outputs (asm_out ...))
  (:inputs (asm_in ...))
  (:clobbers (asm_clob ...))
  (:volatile? bool_val)
```

##### `Inst` (inst)

```scheme
  (%loc n line col)
  (%label lbl)
  (%block lbl (x ...) inst ...)
  (%jump lbl)
  (%jump lbl (opnd ...))
  (%jump-if-false reg lbl)
  (%jump-if-false reg lbl (opnd ...))
  (%jump-if reg lbl1 (opnd1 ...) lbl2 (opnd2 ...))
  (%jump-cond cond_op lbl)
  (%jump-cond str lbl)
  (%jump-if-zero lbl)
  (%direct-jump lbl)
  (%switch opnd lbl (opnd ...) (sc ...))
  (%switch opnd lbl (sc ...))
  (%return)
  (%return opnd)
  (%c-call fn_name shift)
  (%c-call fn_name shift al_val)
  (%call-foreign fn_name shift)
  (%call-foreign fn_name shift al_val)
  (%call-indirect reg shift)
  (%call-indirect reg shift al_val)
  (%call-closure shift)
  (%call-closure shift sp_lbl)
  (%call-closure shift str)
  (%direct-call lbl shift)
  (%direct-call lbl shift sp_lbl)
  (%direct-call lbl shift str)
  (%dispatch-consumer si1 si2 shift)
  (%mov lval opnd)
  (%load reg1 reg2 offset)
  (%store reg1 offset opnd)
  (%load-byte-zx reg1 reg2 offset)
  (%store-byte reg1 offset opnd)
  (%push reg)
  (%pop reg)
  (%code-ref reg lbl)
  (%str-ref reg lbl)
  (%global-ref reg var)
  (%global-addr reg var)
  (%global-set! var reg)
  (%add opnd1 opnd2)
  (%raw-add opnd1 opnd2)
  (%sub opnd1 opnd2)
  (%raw-sub opnd1 opnd2)
  (%imul opnd1 opnd2)
  (%raw-mul opnd1 opnd2)
  (%neg opnd)
  (%inc opnd)
  (%cqo)
  (%idiv opnd)
  (%shl opnd shift)
  (%shl opnd %rcx)
  (%shr opnd shift)
  (%shr opnd %rcx)
  (%shr reg opnd shift)
  (%shr reg opnd %rcx)
  (%sar opnd shift)
  (%sar opnd %rcx)
  (%bit-and opnd1 opnd2)
  (%bit-or opnd1 opnd2)
  (%bit-xor opnd1 opnd2)
  (%cmp opnd1 opnd2)
  (%raw-cmp opnd1 opnd2)
  (%set-boolean opnd cond_op)
  (%add-overflow reg1 reg2 opnd1 opnd2)
  (%sub-overflow reg1 reg2 opnd1 opnd2)
  (%mul-overflow reg1 reg2 opnd1 opnd2)
  (%udiv opnd)
  (%udiv reg opnd1 opnd2)
  (%urem opnd)
  (%urem reg opnd1 opnd2)
  (%setb reg)
  (%setb reg opnd1 opnd2)
  (%setbe reg)
  (%setbe reg opnd1 opnd2)
  (%seta reg)
  (%seta reg opnd1 opnd2)
  (%setae reg)
  (%setae reg opnd1 opnd2)
  (%load-typed mty reg1 reg2 offset)
  (%store-typed mty reg1 offset opnd)
  (%fmov reg1 reg2)
  (%fadd opnd1 opnd2)
  (%fsub opnd1 opnd2)
  (%fmul opnd1 opnd2)
  (%fdiv opnd1 opnd2)
  (%fcmp opnd1 opnd2)
  (%fneg mty reg1 opnd2)
  (%fpext mty reg1 opnd2)
  (%fptrunc mty reg1 opnd2)
  (%sitofp reg1 opnd2)
  (%uitofp reg1 opnd2)
  (%fptosi reg1 opnd2)
  (%fptoui reg1 opnd2)
  (%fcmp-oeq reg1 opnd2 opnd3)
  (%fcmp-une reg1 opnd2 opnd3)
  (%fcmp-olt reg1 opnd2 opnd3)
  (%fcmp-ole reg1 opnd2 opnd3)
  (%fcmp-ogt reg1 opnd2 opnd3)
  (%fcmp-oge reg1 opnd2 opnd3)
  (%trunc mty reg1 opnd2)
  (%zext mty reg1 opnd2)
  (%sext mty reg1 opnd2)
  (%syscall)
  (%syscall si)
  (%memory-fence)
  (%safepoint-poll)
  (%atomic-cas! reg1 reg2 reg3)
  (%inline-asm str asm_clause ...)
  (%alloc opnd n tag)
  (%alloc opnd n tag si)
  (%alloc-stack opnd offset tag)
  (%managed-alloc opnd n tag)
  (%managed-alloc opnd n tag si)
  (%managed-alloc-stack opnd offset tag)
  (%managed-safepoint-poll)
  (%managed-write-barrier opnd1 offset opnd2)
  (%managed-box mty opnd1 opnd2)
  (%managed-unbox mty opnd1 opnd2)
  (%box-fixnum opnd1 opnd2)
  (%unbox-fixnum opnd1 opnd2)
  (%box-flonum opnd1 opnd2)
  (%unbox-flonum opnd1 opnd2)
  (%capture-cc lbl si)
  (%push-handler lbl si1 si2)
  (%pop-handler si)
  (%raise)
  (%set-values-count cnt)
  (%store-values-buf si cnt)
```

##### `StringEntry` (se)

```scheme
  (lbl str)
  (lbl (bytes n ...))
  (str1 str2)
```

##### `DataChunk` (dc)

```scheme
  n
  (zero n)
  (reloc lbl offset)
```

##### `DataEntry` (de)

```scheme
  (bss lbl al_val n)
  (bytes lbl al_val dc ...)
```

##### `SafepointEntry` (sm)

```scheme
  (lbl frame_size bitmap)
  (str frame_size bitmap)
```

##### `SwitchCase` (sc)

```scheme
  (opnd lbl)
  (opnd lbl (opnd ...))
```

##### `AliasEntry` (ae)

```scheme
  (lbl1 lbl2 bool_val)
```

##### `MetaClause` (mc)

```scheme
  (weak-fns (lbl ...))
  (weak-data (lbl ...))
  (aliases (ae ...))
  (top-asm (str ...))
```

##### `FunctionDecl` (f)

```scheme
  (%lir-function lbl (params (x ...)) (frame-size frame_size) (body inst ...))
```

##### `MainDecl` (m)

```scheme
  (%lir-main (frame-size frame_size) (body inst ...))
```

##### `Program` (p)

```scheme
  (%lir-program (strings (se ...)) (stackmaps (sm ...)) (%lir-functions f ...) m mc ...)
  (%lir-program (strings (se ...)) (data (de ...)) (stackmaps (sm ...)) (%lir-functions f ...) m mc ...)
```

---

### 言語: `L_lir_raw`

- **親言語 (Parent)**: (ルート言語)
- **エントリ非終端記号 (Entry)**: `Program`
- **Nongenerative ID**: `#f`

#### 終端記号 (Terminals)

| 述語 (Predicate) | メタ変数パターン (Meta-Variables) |
| :--- | :--- |
| `symbol` | `(x lbl var cond_op sp_lbl mty)` |
| `integer` | `(n offset shift frame_size tag si cnt bitmap line col al_val)` |
| `string` | `(str fn_name)` |
| `boolean` | `(bool_val)` |

#### 非終端記号とプロダクション規則 (Nonterminals & Productions)

##### `Register` (reg)

```scheme
  %rax
  %rbx
  %rcx
  %rdx
  %rsi
  %rdi
  %rbp
  %rsp
  %r8
  %r9
  %r10
  %r11
  %r12
  %r13
  %r14
  %r15
  %al
  %xmm0
  %xmm1
  %xmm2
  %xmm3
  %xmm4
  %xmm5
  %xmm6
  %xmm7
  %xmm8
  %xmm9
  %xmm10
  %xmm11
  %xmm12
  %xmm13
  %xmm14
  %xmm15
  (%reg x)
  (%reg mty x)
  (%freg x)
```

##### `StackSlot` (stk)

```scheme
  (%stack offset)
```

##### `MemRef` (mem)

```scheme
  (%mem reg offset)
  (%mem reg reg)
```

##### `LValue` (lval)

```scheme
  reg
  stk
  mem
```

##### `Operand` (opnd)

```scheme
  lval
  n
  lbl
```

##### `AsmOutSpec` (asm_out)

```scheme
  (lval str)
  (x str)
  (x str lval)
```

##### `AsmInSpec` (asm_in)

```scheme
  (opnd str)
  (x str opnd)
```

##### `AsmClobber` (asm_clob)

```scheme
  str
  x
```

##### `AsmClause` (asm_clause)

```scheme
  (:outputs (asm_out ...))
  (:inputs (asm_in ...))
  (:clobbers (asm_clob ...))
  (:volatile? bool_val)
```

##### `Inst` (inst)

```scheme
  (%nop)
  (%loc n line col)
  (%label lbl)
  (%block lbl (x ...) inst ...)
  (%jump lbl)
  (%jump lbl (opnd ...))
  (%jump-if-false reg lbl)
  (%jump-if-false reg lbl (opnd ...))
  (%jump-if reg lbl1 (opnd1 ...) lbl2 (opnd2 ...))
  (%jump-cond cond_op lbl)
  (%jump-cond str lbl)
  (%jump-if-zero lbl)
  (%direct-jump lbl)
  (%switch opnd lbl (opnd ...) (sc ...))
  (%switch opnd lbl (sc ...))
  (%return)
  (%return opnd)
  (%c-call fn_name shift)
  (%c-call fn_name shift al_val)
  (%call-foreign fn_name shift)
  (%call-foreign fn_name shift al_val)
  (%call-indirect reg shift)
  (%call-indirect reg shift al_val)
  (%call-closure shift)
  (%call-closure shift sp_lbl)
  (%call-closure shift str)
  (%direct-call lbl shift)
  (%direct-call lbl shift sp_lbl)
  (%direct-call lbl shift str)
  (%dispatch-consumer si1 si2 shift)
  (%mov lval opnd)
  (%load reg1 reg2 offset)
  (%store reg1 offset opnd)
  (%load-byte-zx reg1 reg2 offset)
  (%store-byte reg1 offset opnd)
  (%push reg)
  (%pop reg)
  (%code-ref reg lbl)
  (%str-ref reg lbl)
  (%global-ref reg var)
  (%global-addr reg var)
  (%global-set! var reg)
  (%add opnd1 opnd2)
  (%raw-add opnd1 opnd2)
  (%sub opnd1 opnd2)
  (%raw-sub opnd1 opnd2)
  (%imul opnd1 opnd2)
  (%raw-mul opnd1 opnd2)
  (%neg opnd)
  (%inc opnd)
  (%cqo)
  (%idiv opnd)
  (%shl opnd shift)
  (%shl opnd %rcx)
  (%shr opnd shift)
  (%shr opnd %rcx)
  (%shr reg opnd shift)
  (%shr reg opnd %rcx)
  (%sar opnd shift)
  (%sar opnd %rcx)
  (%bit-and opnd1 opnd2)
  (%bit-or opnd1 opnd2)
  (%bit-xor opnd1 opnd2)
  (%cmp opnd1 opnd2)
  (%raw-cmp opnd1 opnd2)
  (%set-boolean opnd cond_op)
  (%box-fixnum opnd1 opnd2)
  (%unbox-fixnum opnd1 opnd2)
  (%add-overflow reg1 reg2 opnd1 opnd2)
  (%sub-overflow reg1 reg2 opnd1 opnd2)
  (%mul-overflow reg1 reg2 opnd1 opnd2)
  (%udiv opnd)
  (%udiv reg opnd1 opnd2)
  (%urem opnd)
  (%urem reg opnd1 opnd2)
  (%setb reg)
  (%setb reg opnd1 opnd2)
  (%setbe reg)
  (%setbe reg opnd1 opnd2)
  (%seta reg)
  (%seta reg opnd1 opnd2)
  (%setae reg)
  (%setae reg opnd1 opnd2)
  (%load-typed mty reg1 reg2 offset)
  (%store-typed mty reg1 offset opnd)
  (%fmov reg1 reg2)
  (%fadd opnd1 opnd2)
  (%fsub opnd1 opnd2)
  (%fmul opnd1 opnd2)
  (%fdiv opnd1 opnd2)
  (%fcmp opnd1 opnd2)
  (%box-flonum opnd1 opnd2)
  (%unbox-flonum opnd1 opnd2)
  (%fneg mty reg1 opnd2)
  (%fpext mty reg1 opnd2)
  (%fptrunc mty reg1 opnd2)
  (%sitofp reg1 opnd2)
  (%uitofp reg1 opnd2)
  (%fptosi reg1 opnd2)
  (%fptoui reg1 opnd2)
  (%fcmp-oeq reg1 opnd2 opnd3)
  (%fcmp-une reg1 opnd2 opnd3)
  (%fcmp-olt reg1 opnd2 opnd3)
  (%fcmp-ole reg1 opnd2 opnd3)
  (%fcmp-ogt reg1 opnd2 opnd3)
  (%fcmp-oge reg1 opnd2 opnd3)
  (%trunc mty reg1 opnd2)
  (%zext mty reg1 opnd2)
  (%sext mty reg1 opnd2)
  (%syscall)
  (%syscall si)
  (%memory-fence)
  (%safepoint-poll)
  (%atomic-cas! reg1 reg2 reg3)
  (%inline-asm str asm_clause ...)
  (%alloc opnd n tag)
  (%alloc opnd n tag si)
  (%alloc-stack opnd offset tag)
  (%capture-cc lbl si)
  (%push-handler lbl si1 si2)
  (%pop-handler si)
  (%raise)
  (%set-values-count cnt)
  (%store-values-buf si cnt)
```

##### `StringEntry` (se)

```scheme
  (lbl str)
  (lbl (bytes n ...))
  (str1 str2)
```

##### `DataChunk` (dc)

```scheme
  n
  (zero n)
  (reloc lbl offset)
```

##### `DataEntry` (de)

```scheme
  (bss lbl al_val n)
  (bytes lbl al_val dc ...)
```

##### `SafepointEntry` (sm)

```scheme
  (lbl frame_size bitmap)
  (str frame_size bitmap)
```

##### `SwitchCase` (sc)

```scheme
  (opnd lbl)
  (opnd lbl (opnd ...))
```

##### `AliasEntry` (ae)

```scheme
  (lbl1 lbl2 bool_val)
```

##### `MetaClause` (mc)

```scheme
  (weak-fns (lbl ...))
  (weak-data (lbl ...))
  (aliases (ae ...))
  (top-asm (str ...))
```

##### `FunctionDecl` (f)

```scheme
  (%lir-function lbl (params (x ...)) (frame-size frame_size) (body inst ...))
```

##### `MainDecl` (m)

```scheme
  (%lir-main (frame-size frame_size) (body inst ...))
```

##### `Program` (p)

```scheme
  (%lir-program (strings (se ...)) (stackmaps (sm ...)) (%lir-functions f ...) m mc ...)
  (%lir-program (strings (se ...)) (data (de ...)) (stackmaps (sm ...)) (%lir-functions f ...) m mc ...)
```

---

### 言語: `L_lir_canonical`

- **親言語 (Parent)**: `L_lir_raw`
- **エントリ非終端記号 (Entry)**: `Program`
- **Nongenerative ID**: `L_lir_raw->L_lir_canonical`

#### 終端記号 (Terminals)

| 述語 (Predicate) | メタ変数パターン (Meta-Variables) |
| :--- | :--- |
| `symbol` | `(x lbl var cond_op sp_lbl mty)` |
| `integer` | `(n offset shift frame_size tag si cnt bitmap line col al_val)` |
| `string` | `(str fn_name)` |
| `boolean` | `(bool_val)` |

#### 非終端記号とプロダクション規則 (Nonterminals & Productions)

##### `Register` (reg)

```scheme
  %rax
  %rbx
  %rcx
  %rdx
  %rsi
  %rdi
  %rbp
  %rsp
  %r8
  %r9
  %r10
  %r11
  %r12
  %r13
  %r14
  %r15
  %al
  %xmm0
  %xmm1
  %xmm2
  %xmm3
  %xmm4
  %xmm5
  %xmm6
  %xmm7
  %xmm8
  %xmm9
  %xmm10
  %xmm11
  %xmm12
  %xmm13
  %xmm14
  %xmm15
  (%reg x)
  (%reg mty x)
  (%freg x)
```

##### `StackSlot` (stk)

```scheme
  (%stack offset)
```

##### `MemRef` (mem)

```scheme
  (%mem reg offset)
  (%mem reg reg)
```

##### `LValue` (lval)

```scheme
  reg
  stk
  mem
```

##### `Operand` (opnd)

```scheme
  lval
  n
  lbl
```

##### `AsmOutSpec` (asm_out)

```scheme
  (lval str)
  (x str)
  (x str lval)
```

##### `AsmInSpec` (asm_in)

```scheme
  (opnd str)
  (x str opnd)
```

##### `AsmClobber` (asm_clob)

```scheme
  str
  x
```

##### `AsmClause` (asm_clause)

```scheme
  (:outputs (asm_out ...))
  (:inputs (asm_in ...))
  (:clobbers (asm_clob ...))
  (:volatile? bool_val)
```

##### `Inst` (inst)

```scheme
  (%loc n line col)
  (%label lbl)
  (%block lbl (x ...) inst ...)
  (%jump lbl)
  (%jump lbl (opnd ...))
  (%jump-if-false reg lbl)
  (%jump-if-false reg lbl (opnd ...))
  (%jump-if reg lbl1 (opnd1 ...) lbl2 (opnd2 ...))
  (%jump-cond cond_op lbl)
  (%jump-cond str lbl)
  (%jump-if-zero lbl)
  (%direct-jump lbl)
  (%switch opnd lbl (opnd ...) (sc ...))
  (%switch opnd lbl (sc ...))
  (%return)
  (%return opnd)
  (%c-call fn_name shift)
  (%c-call fn_name shift al_val)
  (%call-foreign fn_name shift)
  (%call-foreign fn_name shift al_val)
  (%call-indirect reg shift)
  (%call-indirect reg shift al_val)
  (%call-closure shift)
  (%call-closure shift sp_lbl)
  (%call-closure shift str)
  (%direct-call lbl shift)
  (%direct-call lbl shift sp_lbl)
  (%direct-call lbl shift str)
  (%dispatch-consumer si1 si2 shift)
  (%mov lval opnd)
  (%load reg1 reg2 offset)
  (%store reg1 offset opnd)
  (%load-byte-zx reg1 reg2 offset)
  (%store-byte reg1 offset opnd)
  (%push reg)
  (%pop reg)
  (%code-ref reg lbl)
  (%str-ref reg lbl)
  (%global-ref reg var)
  (%global-addr reg var)
  (%global-set! var reg)
  (%add opnd1 opnd2)
  (%raw-add opnd1 opnd2)
  (%sub opnd1 opnd2)
  (%raw-sub opnd1 opnd2)
  (%imul opnd1 opnd2)
  (%raw-mul opnd1 opnd2)
  (%neg opnd)
  (%inc opnd)
  (%cqo)
  (%idiv opnd)
  (%shl opnd shift)
  (%shl opnd %rcx)
  (%shr opnd shift)
  (%shr opnd %rcx)
  (%shr reg opnd shift)
  (%shr reg opnd %rcx)
  (%sar opnd shift)
  (%sar opnd %rcx)
  (%bit-and opnd1 opnd2)
  (%bit-or opnd1 opnd2)
  (%bit-xor opnd1 opnd2)
  (%cmp opnd1 opnd2)
  (%raw-cmp opnd1 opnd2)
  (%set-boolean opnd cond_op)
  (%box-fixnum opnd1 opnd2)
  (%unbox-fixnum opnd1 opnd2)
  (%add-overflow reg1 reg2 opnd1 opnd2)
  (%sub-overflow reg1 reg2 opnd1 opnd2)
  (%mul-overflow reg1 reg2 opnd1 opnd2)
  (%udiv opnd)
  (%udiv reg opnd1 opnd2)
  (%urem opnd)
  (%urem reg opnd1 opnd2)
  (%setb reg)
  (%setb reg opnd1 opnd2)
  (%setbe reg)
  (%setbe reg opnd1 opnd2)
  (%seta reg)
  (%seta reg opnd1 opnd2)
  (%setae reg)
  (%setae reg opnd1 opnd2)
  (%load-typed mty reg1 reg2 offset)
  (%store-typed mty reg1 offset opnd)
  (%fmov reg1 reg2)
  (%fadd opnd1 opnd2)
  (%fsub opnd1 opnd2)
  (%fmul opnd1 opnd2)
  (%fdiv opnd1 opnd2)
  (%fcmp opnd1 opnd2)
  (%box-flonum opnd1 opnd2)
  (%unbox-flonum opnd1 opnd2)
  (%fneg mty reg1 opnd2)
  (%fpext mty reg1 opnd2)
  (%fptrunc mty reg1 opnd2)
  (%sitofp reg1 opnd2)
  (%uitofp reg1 opnd2)
  (%fptosi reg1 opnd2)
  (%fptoui reg1 opnd2)
  (%fcmp-oeq reg1 opnd2 opnd3)
  (%fcmp-une reg1 opnd2 opnd3)
  (%fcmp-olt reg1 opnd2 opnd3)
  (%fcmp-ole reg1 opnd2 opnd3)
  (%fcmp-ogt reg1 opnd2 opnd3)
  (%fcmp-oge reg1 opnd2 opnd3)
  (%trunc mty reg1 opnd2)
  (%zext mty reg1 opnd2)
  (%sext mty reg1 opnd2)
  (%syscall)
  (%syscall si)
  (%memory-fence)
  (%safepoint-poll)
  (%atomic-cas! reg1 reg2 reg3)
  (%inline-asm str asm_clause ...)
  (%alloc opnd n tag)
  (%alloc opnd n tag si)
  (%alloc-stack opnd offset tag)
  (%capture-cc lbl si)
  (%push-handler lbl si1 si2)
  (%pop-handler si)
  (%raise)
  (%set-values-count cnt)
  (%store-values-buf si cnt)
```

##### `StringEntry` (se)

```scheme
  (lbl str)
  (lbl (bytes n ...))
  (str1 str2)
```

##### `DataChunk` (dc)

```scheme
  n
  (zero n)
  (reloc lbl offset)
```

##### `DataEntry` (de)

```scheme
  (bss lbl al_val n)
  (bytes lbl al_val dc ...)
```

##### `SafepointEntry` (sm)

```scheme
  (lbl frame_size bitmap)
  (str frame_size bitmap)
```

##### `SwitchCase` (sc)

```scheme
  (opnd lbl)
  (opnd lbl (opnd ...))
```

##### `AliasEntry` (ae)

```scheme
  (lbl1 lbl2 bool_val)
```

##### `MetaClause` (mc)

```scheme
  (weak-fns (lbl ...))
  (weak-data (lbl ...))
  (aliases (ae ...))
  (top-asm (str ...))
```

##### `FunctionDecl` (f)

```scheme
  (%lir-function lbl (params (x ...)) (frame-size frame_size) (body inst ...))
```

##### `MainDecl` (m)

```scheme
  (%lir-main (frame-size frame_size) (body inst ...))
```

##### `Program` (p)

```scheme
  (%lir-program (strings (se ...)) (stackmaps (sm ...)) (%lir-functions f ...) m mc ...)
  (%lir-program (strings (se ...)) (data (de ...)) (stackmaps (sm ...)) (%lir-functions f ...) m mc ...)
```

#### 削除・排除された不変条件 (Removed Invariants)

本言語では以下の構文が明示的に禁止・脱糖済みとして排除されています：

- `%nop`

---

### 言語: `L_asm_x86`

- **親言語 (Parent)**: (ルート言語)
- **エントリ非終端記号 (Entry)**: `Program`
- **Nongenerative ID**: `#f`

#### 終端記号 (Terminals)

| 述語 (Predicate) | メタ変数パターン (Meta-Variables) |
| :--- | :--- |
| `symbol` | `(lbl var op cc)` |
| `integer` | `(n disp imm scale bitmap frame_size offset al_val align)` |
| `string` | `(str)` |
| `boolean` | `(bool_val)` |

#### 非終端記号とプロダクション規則 (Nonterminals & Productions)

##### `Register` (reg)

```scheme
  rax
  rbx
  rcx
  rdx
  rsi
  rdi
  rbp
  rsp
  r8
  r9
  r10
  r11
  r12
  r13
  r14
  r15
  al
  cl
  (%reg var)
```

##### `Memory` (mem)

```scheme
  (%disp disp reg)
  (%index reg reg scale disp)
  (%mem reg disp)
```

##### `Operand` (opnd)

```scheme
  reg
  mem
  (%imm imm)
  imm
  lbl
```

##### `Inst` (inst)

```scheme
  (%label lbl)
  (%p2align align)
  (%align align)
  (%raw-asm str)
  (mov opnd1 opnd2)
  (movzx opnd1 opnd2)
  (lea opnd1 opnd2)
  (add opnd1 opnd2)
  (sub opnd1 opnd2)
  (imul opnd1 opnd2)
  (and opnd1 opnd2)
  (or opnd1 opnd2)
  (xor opnd1 opnd2)
  (shl opnd1 opnd2)
  (shr opnd1 opnd2)
  (sar opnd1 opnd2)
  (neg opnd)
  (not opnd)
  (cmp opnd1 opnd2)
  (test opnd1 opnd2)
  (set cc opnd)
  (jmp lbl)
  (jcc cc lbl)
  (call opnd)
  (ret)
  (push opnd)
  (pop opnd)
  (cqo)
  (idiv opnd)
  (div opnd)
  (inc opnd)
  (syscall)
  (cld)
  (rep-movsb)
```

##### `StringEntry` (se)

```scheme
  (lbl str)
  (lbl (bytes n ...))
```

##### `DataChunk` (dc)

```scheme
  n
  (zero n)
  (reloc lbl offset)
```

##### `DataEntry` (de)

```scheme
  (bss lbl al_val n)
  (bytes lbl al_val dc ...)
```

##### `SafepointEntry` (sm)

```scheme
  (lbl frame_size bitmap)
```

##### `AliasEntry` (ae)

```scheme
  (lbl1 lbl2 bool_val)
```

##### `MetaClause` (mc)

```scheme
  (weak-fns (lbl ...))
  (weak-data (lbl ...))
  (aliases (ae ...))
  (top-asm (str ...))
```

##### `FunctionDecl` (f)

```scheme
  (%asm-function lbl (frame-size n) (body inst ...))
```

##### `MainDecl` (m)

```scheme
  (%asm-main (frame-size n) (body inst ...))
```

##### `Program` (p)

```scheme
  (%asm-program (strings (se ...)) (stackmaps (sm ...)) (%asm-functions f ...) m mc ...)
  (%asm-program (strings (se ...)) (data (de ...)) (stackmaps (sm ...)) (%asm-functions f ...) m mc ...)
```

---

### 言語: `L_asm_aarch64`

- **親言語 (Parent)**: (ルート言語)
- **エントリ非終端記号 (Entry)**: `Program`
- **Nongenerative ID**: `#f`

#### 終端記号 (Terminals)

| 述語 (Predicate) | メタ変数パターン (Meta-Variables) |
| :--- | :--- |
| `symbol` | `(lbl var op cc align)` |
| `integer` | `(n disp imm shift bitmap frame_size bytes)` |
| `string` | `(str)` |

#### 非終端記号とプロダクション規則 (Nonterminals & Productions)

##### `Register` (reg)

```scheme
  x0
  x1
  x2
  x3
  x4
  x5
  x6
  x7
  x8
  x9
  x10
  x11
  x12
  x13
  x14
  x15
  x16
  x17
  x18
  x19
  x20
  x21
  x22
  x23
  x24
  x25
  x26
  x27
  x28
  x29
  x30
  sp
  xzr
  w0
  w1
  w2
  w3
  w4
  w5
  w6
  w7
  w8
  w9
  w10
  w11
  w12
  w13
  w14
  w15
  w16
  w17
  w18
  w19
  w20
  w21
  w22
  w23
  w24
  w25
  w26
  w27
  w28
  w29
  w30
  wzr
  (%reg var)
```

##### `Memory` (mem)

```scheme
  (%mem reg disp)
  (%mem reg reg)
  (%stack disp)
```

##### `Operand` (opnd)

```scheme
  reg
  mem
  (%imm imm)
  imm
  lbl
```

##### `Inst` (inst)

```scheme
  (%label lbl)
  (%p2align align)
  (%align align)
  (%raw-asm str)
  (mov opnd1 opnd2)
  (movz opnd1 opnd2)
  (movk opnd1 opnd2)
  (adr opnd1 lbl)
  (add opnd1 opnd2 opnd3)
  (sub opnd1 opnd2 opnd3)
  (mul opnd1 opnd2 opnd3)
  (sdiv opnd1 opnd2 opnd3)
  (msub opnd1 opnd2 opnd3 opnd4)
  (and opnd1 opnd2 opnd3)
  (orr opnd1 opnd2 opnd3)
  (eor opnd1 opnd2 opnd3)
  (lsl opnd1 opnd2 opnd3)
  (lsr opnd1 opnd2 opnd3)
  (asr opnd1 opnd2 opnd3)
  (neg opnd1 opnd2)
  (cmp opnd1 opnd2)
  (cset opnd cc)
  (b lbl)
  (b.cc cc lbl)
  (cbz opnd lbl)
  (cbnz opnd lbl)
  (bl lbl)
  (blr opnd)
  (ret)
  (stp opnd1 opnd2 mem)
  (ldp opnd1 opnd2 mem)
  (str opnd mem)
  (ldr opnd mem)
  (strb opnd mem)
  (ldrb opnd mem)
  (svc imm)
  (dmb op)
```

##### `StringEntry` (se)

```scheme
  (lbl str)
  (lbl (bytes n ...))
```

##### `SafepointEntry` (sm)

```scheme
  (lbl frame_size bitmap)
```

##### `FunctionDecl` (f)

```scheme
  (%asm-function lbl (frame-size n) (body inst ...))
```

##### `MainDecl` (m)

```scheme
  (%asm-main (frame-size n) (body inst ...))
```

##### `Program` (p)

```scheme
  (%asm-program (strings (se ...)) (stackmaps (sm ...)) (%asm-functions f ...) m)
```

---

### 言語: `L_c_ast`

- **親言語 (Parent)**: (ルート言語)
- **エントリ非終端記号 (Entry)**: `TranslationUnit`
- **Nongenerative ID**: `#f`

#### 終端記号 (Terminals)

| 述語 (Predicate) | メタ変数パターン (Meta-Variables) |
| :--- | :--- |
| `symbol` | `(sym op assign_op)` |
| `string` | `(str raw_str)` |
| `integer` | `(n bid)` |
| `boolean` | `(bool_val)` |
| `any` | `(any_node specs params inits items fields enums)` |

#### 非終端記号とプロダクション規則 (Nonterminals & Productions)

##### `TranslationUnit` (tu)

```scheme
  (c-translation-unit ext ...)
```

##### `ExternalDecl` (ext)

```scheme
  (c-fn-def sym specs decl params stmt)
  (c-fn-def sym specs decl params stmt any_node)
  (c-decl specs inits)
  (c-typedef specs inits)
  (c-top-asm raw_str)
```

##### `Declarator` (decl)

```scheme
  (c-decl-id sym)
  (c-decl-id sym bid)
  (c-ptr-declarator any_node decl)
  (c-arr-declarator decl any_node)
  (c-fn-declarator decl params)
  (c-init-decl decl any_node)
  (c-attr-decl decl any_node any_node)
```

##### `Stmt` (stmt)

```scheme
  (c-block items ...)
  (c-if expr stmt1)
  (c-if expr stmt1 stmt2)
  (c-switch expr stmt)
  (c-case expr stmt)
  (c-default stmt)
  (c-while expr stmt)
  (c-do-while stmt expr)
  (c-for any_node1 any_node2 any_node3 stmt)
  (c-goto sym)
  (c-label sym stmt)
  (c-continue)
  (c-break)
  (c-return any_node)
  (c-expr-stmt any_node)
  (c-decl specs inits)
  (c-typedef specs inits)
  (c-asm bool_val raw_str any_node1 any_node2 any_node3)
```

##### `Expr` (expr)

```scheme
  (c-var-ref sym bid)
  (c-var-ref sym any_node)
  (c-const raw_str)
  (c-str raw_str)
  (c-unop op expr)
  (c-binop op expr1 expr2)
  (c-assign assign_op expr1 expr2)
  (c-ternary expr1 expr2 expr3)
  (c-call expr0 expr ...)
  (c-index expr1 expr2)
  (c-member expr sym bool_val)
  (c-cast any_node expr)
  (c-sizeof-type any_node)
  (c-sizeof-expr expr)
  (c-alignof-type any_node)
  (c-alignof-expr expr)
  (c-offsetof any_node any_node)
  (c-va-arg expr any_node)
  (c-compound-lit any_node inits)
```

---

### 言語: `L_c_typed`

- **親言語 (Parent)**: `L_c_ast`
- **エントリ非終端記号 (Entry)**: `TranslationUnit`
- **Nongenerative ID**: `L_c_ast->L_c_typed`

#### 終端記号 (Terminals)

| 述語 (Predicate) | メタ変数パターン (Meta-Variables) |
| :--- | :--- |
| `any` | `(any_node specs params inits items fields enums ctype)` |
| `boolean` | `(bool_val)` |
| `integer` | `(n bid)` |
| `string` | `(str raw_str)` |
| `symbol` | `(sym op assign_op)` |

#### 非終端記号とプロダクション規則 (Nonterminals & Productions)

##### `TranslationUnit` (tu)

```scheme
  (c-translation-unit ext ...)
```

##### `ExternalDecl` (ext)

```scheme
  (c-fn-def sym specs decl params stmt)
  (c-fn-def sym specs decl params stmt any_node)
  (c-decl specs inits)
  (c-typedef specs inits)
  (c-top-asm raw_str)
```

##### `Declarator` (decl)

```scheme
  (c-decl-id sym)
  (c-decl-id sym bid)
  (c-ptr-declarator any_node decl)
  (c-arr-declarator decl any_node)
  (c-fn-declarator decl params)
  (c-init-decl decl any_node)
  (c-attr-decl decl any_node any_node)
```

##### `Stmt` (stmt)

```scheme
  (c-block items ...)
  (c-if expr stmt1)
  (c-if expr stmt1 stmt2)
  (c-switch expr stmt)
  (c-case expr stmt)
  (c-default stmt)
  (c-while expr stmt)
  (c-do-while stmt expr)
  (c-for any_node1 any_node2 any_node3 stmt)
  (c-goto sym)
  (c-label sym stmt)
  (c-continue)
  (c-break)
  (c-return any_node)
  (c-expr-stmt any_node)
  (c-decl specs inits)
  (c-typedef specs inits)
  (c-asm bool_val raw_str any_node1 any_node2 any_node3)
```

##### `Expr` (expr)

```scheme
  (c-var-ref sym bid)
  (c-var-ref sym any_node)
  (c-const raw_str)
  (c-str raw_str)
  (c-unop op expr)
  (c-binop op expr1 expr2)
  (c-assign assign_op expr1 expr2)
  (c-ternary expr1 expr2 expr3)
  (c-call expr0 expr ...)
  (c-index expr1 expr2)
  (c-member expr sym bool_val)
  (c-cast any_node expr)
  (c-sizeof-type any_node)
  (c-sizeof-expr expr)
  (c-alignof-type any_node)
  (c-alignof-expr expr)
  (c-offsetof any_node any_node)
  (c-va-arg expr any_node)
  (c-compound-lit any_node inits)
  (c-typed ctype expr)
  (c-implicit-cast ctype expr)
  (c-init-list any_node)
  (c-va-start expr)
  (c-va-arg expr ctype)
  (c-va-end expr)
  (c-va-copy expr1 expr2)
```

---

