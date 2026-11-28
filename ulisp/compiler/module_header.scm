;;; =======================================================================
;;; ULisp Compiler Module Header & Interface Specification
;;; Conforms to DSN-33 Architecture Specification & Issue #608
;;; =======================================================================

;; I/O Compatibility Macros (expanding to stdlib runtime ports)
(define-syntax newline
  (syntax-rules ()
    ((newline) (port-newline *stdout-port*))
    ((newline p) (port-newline p))))

(define-syntax display
  (syntax-rules ()
    ((display val) (port-display val *stdout-port*))
    ((display val p) (port-display val p))))

(define-syntax write
  (syntax-rules ()
    ((write val) (port-write val *stdout-port*))
    ((write val p) (port-write val p))))

(define-syntax read
  (syntax-rules ()
    ((read) (port-read *stdin-port*))
    ((read p) (port-read p))))

(define-syntax read-u8
  (syntax-rules ()
    ((read-u8) (port-read-u8 *stdin-port*))
    ((read-u8 p) (port-read-u8 p))))

(define-syntax read-char
  (syntax-rules ()
    ((read-char) (port-read-char (current-input-port)))
    ((read-char p) (port-read-char p))))

(define-syntax read-string
  (syntax-rules ()
    ((read-string k) (port-read-string k (current-input-port)))
    ((read-string k p) (port-read-string k p))))

(define-syntax write-string
  (syntax-rules ()
    ((write-string s) (port-write-string s (current-output-port)))
    ((write-string s p) (port-write-string s p))))

(define-syntax flush-output-port
  (syntax-rules ()
    ((flush-output-port) (port-flush-output (current-output-port)))
    ((flush-output-port p) (port-flush-output p))))

(define-syntax write-u8
  (syntax-rules ()
    ((write-u8 b) (port-write-u8 b *stdout-port*))
    ((write-u8 b p) (port-write-u8 b p))))

(define-syntax write-bytevector
  (syntax-rules ()
    ((write-bytevector bv)
     (let ((b bv))
       (port-write-bytevector-range b *stdout-port* 0 (bytevector-length b))))
    ((write-bytevector bv p)
     (let ((b bv))
       (port-write-bytevector-range b p 0 (bytevector-length b))))
    ((write-bytevector bv p start)
     (let ((b bv))
       (port-write-bytevector-range b p start (bytevector-length b))))
    ((write-bytevector bv p start end)
     (port-write-bytevector-range bv p start end))))

;; String-append macro (expanding to stdlib string-append2)
(define-syntax string-append
  (syntax-rules ()
    ((string-append) "")
    ((string-append s) s)
    ((string-append s1 s2) (string-append2 s1 s2))
    ((string-append s1 s2 s3) (string-append2 s1 (string-append2 s2 s3)))
    ((string-append s1 s2 s3 s4) (string-append2 s1 (string-append2 s2 (string-append2 s3 s4))))
    ((string-append s1 s2 s3 s4 s5) (string-append2 s1 (string-append2 s2 (string-append2 s3 (string-append2 s4 s5)))))
    ((string-append s1 s2 s3 s4 s5 s6 ...) (string-append2 s1 (string-append s2 s3 s4 s5 s6 ...)))))

(define-syntax string->number
  (syntax-rules ()
    ((string->number s) (string->number-core s 10 #f))
    ((string->number s r) (string->number-core s r #t))))

;; Declare inter-module extern identifiers so the compiler's reader interns them into *symbol-registry*
(define-syntax %declare-extern-identifiers
  (syntax-rules ()
    ((%declare-extern-identifiers id ...)
     (begin))))

(%declare-extern-identifiers
  quote
  quasiquote
  unquote
  unquote-splicing
  vector
  bytevector
  ...
  _
  guard
  cons
  list
  append
  map
  nanopass-map2
  nanopass-map3
  lambda
  let
  let*
  letrec
  if
  begin
  set!
  define
  %program
  entry
  exit
  L_cst
  L_src
  L_core
  L_anf
  L_lifted
  L_lir_core
  L_lir_managed
  L_mir_ssa
  L_lir_mach
  __lang_L_mir_ssa
  __lang_L_lir_mach
  parse-L_mir_ssa
  unparse-L_mir_ssa
  parse-L_lir_mach
  unparse-L_lir_mach
  L_lir_raw
  L_lir_canonical
  L_asm_x86
  L_asm_aarch64
  L_x86_64
  L_aarch64
  L_c
  L_cst?
  L_src?
  L_core?
  L_anf?
  L_lifted?
  L_lir_core?
  L_lir_managed?
  L_mir_ssa?
  L_lir_mach?
  L_lir_raw?
  L_lir_canonical?
  L_asm_x86?
  L_asm_aarch64?
  string-append2
  vector-append2
  bytevector-append2
  nanopass-try-clause
  nanopass-catamorphism-step
  set-current-pass!
  nanopass-verifier-enabled?
  nanopass-verify-ast
  with-call-frame
  nanopass-display-ast-diff
  nanopass-trace-enabled?
  nanopass-register-language!
  nanopass-parse-language-spec
  nanopass-parse
  nanopass-unparse
  nanopass-ast-valid?
  nanopass-parse-nt
  current-jiffy
  jiffies-per-second
  sys-getenv
  get-environment-variable
  get-environment-variables
  command-line
  sys-chmod
  sys-fork
  sys-execve
  sys-wait4
  sys-waitpid
  process-exec
  file-exists?
  delete-file
  open-input-file
  open-output-file
  close-input-port
  close-output-port
  call-with-input-file
  call-with-output-file
  current-input-port
  current-output-port
  current-error-port
  port-read-string
  port-write-string
  port-flush-output
  num-bitwise-and
  num-bitwise-ior
  ulisp_fn_num_bitwise_and
  ulisp_fn_num_bitwise_ior
  bitwise-not
  bitwise-xor
  arithmetic-shift
  sys-bench-passes?
  sys-clock-gettime-monotonic
  gc-current-heap-bytes
  occurs-in?
  unboxed-fn?
  *top-level-vars*
  *top-level-fns*
  slurp-single-file
  desugar-libraries-and-imports
  expand-dsl-forms
  expand-macros-in-forms
  rewrite-top-level
  desugar-all
  cp0-optimize
  lvn-all
  anf-all
  annotate-all
  rtyper-all
  contify-all
  closure-convert
  alias-escape-all
  generate-lir
  *enable-lir-linear-scan*
  lir-linear-scan-enabled?
  set-lir-linear-scan-enabled!
  lir-imm32-constant
  lir-fuse-branches
  lir-peephole-optimize
  lir-physical-register-sym?
  lir-virtual-register?
  lir-tree-has-virtual-reg?
  lir-block-param-physical?
  lir-check-no-virtual-regs
  lir-verify-mach-purity
  validate-mir-ssa
  verify-mir-ssa
  validate-mach-lir
  verify-mach-lir
  lir-verify-parallel-move-plan
  *lir-pmov-gpr-scratch-pool*
  *lir-pmov-fpr-scratch-pool*
  lir-pmov-unwrap-reg
  lir-pmov-phys-reg-sym?
  lir-pmov-canon-exact-reg
  lir-pmov-canon-gpr-family
  lir-pmov-loc-equal?
  lir-pmov-reg-aliases?
  lir-pmov-float-loc?
  lir-pmov-stack-loc?
  lir-pmov-mem-loc?
  lir-pmov-rsp-loc?
  lir-pmov-loc-reads?
  lir-pmov-select-scratch
  lir-parallel-move-plan
  lir-emit-single-move
  lir-emit-parallel-moves
  lir-emit-parallel-moves-with-usage
  lir-to-mir-ssa
  braun-ssa-transform-program
  lower-mir-ssa-to-mach-lir
  *c99-lower-mir-hook*
  *c99-lower-abi-hook*
  *c99-lower-inline-asm-hook*
  c99-lower-mir-pass-run
  c99-lower-abi-pass-run
  c99-lower-inline-asm-pass-run
  *enable-lir-linear-scan*
  lir-linear-scan-enabled?
  set-lir-linear-scan-enabled!
  port-write-bytevector-range
  port-write-bytevector
  port-read-char
  %file-input-port
  assemble-and-build-elf-obj
  emit-x86-64-elf-obj
  build-x86-64-elf-obj
  emit-x86-64-profiled
  build-x86-64-elf-obj-profiled
  assemble-x86-relocatable-profiled
  profile-x86-asm-parse-only
  assemble-stream-to-elf-obj
  record-picopass-firing!
  picopass-enabled?
  register-mandatory-picopass!
  disable-picopass!
  enable-picopass!
  auto-bisect-picopasses
  with-disabled-picopasses
  reset-disabled-picopasses!
  reset-picopass-provenance!
  enable-picopass-provenance!
  disable-picopass-provenance!
  picopass-provenance-enabled?
  get-picopass-firing-counts
  get-picopass-firing-log
  rule-mandatory?
  picopass-mandatory?
  femto-get-cached-attr
  femto-register-attr-dependencies!
  femto-cache-invalidate-tags!
  femto-cache-invalidate-node!
  femto-cache-reset!
  femto-cache-stats
  femto-cache-hit-rate
  expr-size-le?
  define-value-repr
  repr:scheme-64bit-tagged
  repr:c-unboxed
  repr:nan-boxing-64bit
  repr:guest-3bit-tagged
  scheme-standard
  c-unboxed
  nan-boxing-64bit
  guest-3bit-tagged
  guest-tagged
  current-value-repr
  value-repr-name
  with-value-repr
  *static-const-counter*
  *static-constants*
  can-emit-static-quoted-datum?
  intern-static-constant!
  repr-encode-immediate
  repr-emit-box-fixnum
  repr-emit-unbox-fixnum
  repr-emit-box-flonum
  repr-emit-unbox-flonum
  repr-special-tag
  repr-special-shift
  repr-encode-special-with
  repr-encode-special
  repr-decode-special-with
  repr-decode-special
  repr-encode-undef
  repr-nan-box-base
  repr-nan-box-payload-mask
  repr-nan-box-tag-shift
  repr-nan-box-tag-unit
  repr-nan-box-subtag
  repr-nan-boxed-value?
  repr-nan-tag-of
  repr-nan-box-pointer
  repr-nan-pointer?
  repr-nan-unbox-pointer
  repr-nan-box-special
  repr-nan-special?
  repr-nan-unbox-special
  repr-gc-heap-tags-with
  repr-gc-heap-tags
  repr-gc-heap-value?
  repr-gc-untag-ptr
  repr-format-tagged-value
  repr-runtime-constant-alist
  repr-generate-runtime-printer-defs
  make-binding
  binding?
  binding-id
  binding-source-name
  binding-unique-sym
  binding-kind
  binding-namespace
  binding-scope-id
  binding-storage-class
  binding-type-attr
  binding-visibility
  binding-scope-set
  binding-source-span
  lookup-binding-by-id
  lookup-binding-by-symbol
  binding-id-set-union
  binding-id-set-difference
  binding-id-set-intersection
  resolve-hygienic-binding
  scope-define!
  scope-lookup-binding
  scope-lookup-kind
  scope-typedef-name?
  make-scope-manager
  scope-manager-push!
  scope-manager-pop!
  free-binding-ids
  closure-capture-binding-ids
  symbol->hash-idx
  open-binary-input-file
  open-binary-output-file
  port-read-u8
  port-write-u8
  bitwise-and
  bitwise-ior
  source-span?
  make-source-span
  %make-source-span-raw
  dual-source-span?
  make-dual-source-span
  %make-dual-source-span-raw
  any-source-span?
  span-guest-file
  span-guest-line
  span-guest-col
  span-interp-file
  span-interp-line
  span-interp-col
  span-effective-file
  span-effective-line
  span-effective-col
  span-effective-interp-file
  span-effective-interp-line
  span-effective-interp-col
  dual-source-span->source-span
  span-file
  span-start-line
  span-start-col
  span-end-line
  span-end-col
  span-macro-origin
  span-node-id
  sbi-serialize
  sbi-deserialize
  sbi-deserialize-full
  sbi-write-file
  sbi-read-file
  sbi-read-file-full
  sbi-binary-bytevector?
  sbi-binary-file?
  sbi-import-forms
  sbi-cache-valid?
  sbi-load-or-build-pch
  sbi-merge-lir-modules
  sbi-sha256-bytevector
  sbi-sha256-string
  sbi-sha256-file
  sbi-sha256-hex
  *pass-analysis-contracts*
  *pass-proc-analysis-contracts*
  *nanopass-pre-pass-analysis-hook*
  *nanopass-post-pass-analysis-hook*
  normalize-analysis-spec-list
  alist-upsert-eq
  register-pass-analysis-contract!
  register-pass-proc-analysis-contract!
  lookup-pass-analysis-contract
  reset-pass-analysis-contracts!
  nanopass-invoke-pre-pass-analysis!
  nanopass-invoke-post-pass-analysis!
  set-pass-analysis-contract!
  pass-analysis-contract
  pass-requires-analyses
  pass-preserves-analyses
  pass-invalidates-analyses
  make-analysis-descriptor
  register-analysis-property!
  lookup-analysis-property
  require-analysis
  invalidate-analysis!
  invalidate-all-analyses!
  ensure-pass-required-analyses!
  apply-pass-analysis-invalidation!
  reset-analysis-cache!
  analysis-cache-stats
  analysis-valid?
  get-cached-analysis
  analysis-compute-count
  analysis-hit-count
  analysis-invalidation-count
  init-default-analysis-properties!
  *last-fixpoint-iterations*
  *last-fixpoint-converged?*
  last-fixpoint-iterations
  last-fixpoint-converged?
  resolve-fixpoint-pass-descriptor
  make-pass-descriptor-with-opts
  scope-define-opts
  cdr*
  memv
  assv
  member
  string->number-core
  run-pass-fixpoint
  stage-poly-lower
  stage-poly-lower-form
  stage-poly-lower-all
  contains-stage-meta-syntax?
  eval-in-stage
  make-later-dict
  with-spec-limits
  current-max-spec-instances
  current-max-spec-depth
  run-triple-differential-oracle
  verify-residual-anf-conformance
  %number?
  %complex?
  %real?
  %rational?
  %integer?
  %exact?
  %inexact?
  %exact-integer?
  lower-lir-reg8
  canonical-x86-set-cc
  x86-reg8->reg64
  x86-set-overflow-cc?
  x86-set-eq-ne-cc?)

(define-syntax number?
  (syntax-rules ()
    ((_ x) (let ((__v x)) (if (fixnum? __v) #t (%number? __v))))))
(define-syntax complex?
  (syntax-rules ()
    ((_ x) (let ((__v x)) (if (fixnum? __v) #t (%complex? __v))))))
(define-syntax real?
  (syntax-rules ()
    ((_ x) (let ((__v x)) (if (fixnum? __v) #t (%real? __v))))))
(define-syntax rational?
  (syntax-rules ()
    ((_ x) (let ((__v x)) (if (fixnum? __v) #t (%rational? __v))))))
(define-syntax integer?
  (syntax-rules ()
    ((_ x) (let ((__v x)) (if (fixnum? __v) #t (%integer? __v))))))
(define-syntax exact?
  (syntax-rules ()
    ((_ x) (let ((__v x)) (if (fixnum? __v) #t (%exact? __v))))))
(define-syntax inexact?
  (syntax-rules ()
    ((_ x) (let ((__v x)) (if (fixnum? __v) #f (%inexact? __v))))))
(define-syntax exact-integer?
  (syntax-rules ()
    ((_ x) (let ((__v x)) (if (fixnum? __v) #t (%exact-integer? __v))))))


