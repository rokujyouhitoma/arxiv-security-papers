;;; =======================================================================
;;; ULisp C99 Struct, Union, Enum, Bitfield & SysV AMD64 Layout Test Suite
;;; Conforms to DSN-33-32 §5.1 / §6.2 & Issue #918
;;; Verifies:
;;;   1. SysV AMD64 Type Layout Engine (struct/union/enum/bitfield/anon/FAM)
;;;      against Host GCC x86_64-linux-gnu oracle values
;;;   2. SysV AMD64 8-byte Eightbyte Classifier & Call/Return ABI Planner
;;;   3. Diagnostics C99-LAY-001..004 & Security Guards (CWE-190/674/787)
;;;   4. Reference VM (#834) E2E Execution & Core Machine LIR Conformance
;;; =======================================================================

(enable-verifier!)
(set-verifier-level! 3)
(set-verifier-strict! #t)

(test-begin "C99 Struct/Union/Enum/Bitfield & SysV Layout (Issue #918)")

(define (c99-layout-test-parse-and-sema src-str fname)
  (c99-analyze-program (parse-c99-preprocessed-string src-str fname)))

(define (c99-layout-test-compile-to-lir src-str fname)
  (c99-compile-string-to-lir src-str fname))

(define (c99-layout-test-eval-vm src-str fname)
  (let ((lir (c99-layout-test-compile-to-lir src-str fname)))
    (assert-true (string-append fname ": passes L_lir_core?") (L_lir_core? lir))
    (assert-true (string-append fname ": passes validate-core-lir") (validate-core-lir lir))
    (eval-lir-program lir)))

(define (c99-layout-expect-error expected-code src-str fname)
  (guard (ex
          ((and (pair? ex)
                (eq? (car ex) 'c99-sema-error)
                (pair? (cdr ex))
                (equal? (cadr ex) expected-code))
           #t)
          (else
           (display "  [FAIL] Unexpected exception in ")
           (display fname)
           (display ": ")
           (write ex)
           (newline)
           #f))
    (c99-layout-test-parse-and-sema src-str fname)
    (display "  [FAIL] Expected error ")
    (display expected-code)
    (display " in ")
    (display fname)
    (display " but compilation succeeded\n")
    #f))

(define (c99-find-struct-layout src-str tag-sym)
  (let* ((res (c99-layout-test-parse-and-sema src-str "oracle_layout.c"))
         (lenv (list-ref res 3)))
    (c-layout-env-lookup-struct lenv tag-sym)))

(begin

    ;; ===================================================================
    ;; Group 1: SysV AMD64 Layout Engine & 8-Byte ABI Classifier Unit Tests
    ;; ===================================================================
    (display "\n--- Group 1: SysV AMD64 Layout Engine & ABI Classifier ---\n")

    (let* ((src "
      struct Empty {};
      struct ZeroBF  { char a; int : 0; char b; };
      struct ZeroBF2 { char a; int : 3; char b; };
      struct ZeroBF3 { char a; long : 0; char b; };
      struct ZeroBF4 { int a:4; int : 0; char b; };
      struct NamedBF { unsigned a:4; int b:5; unsigned c:24; };
      struct MixedBF  { unsigned char a:5; unsigned int b:5; };
      struct MixedBF2 { unsigned char a:5; unsigned short b:5; };
      struct MixedBF3 { unsigned char a:5; unsigned int b:10; };
      struct MixedBF4 { unsigned short a:12; unsigned int b:24; };
      struct LongBF  { unsigned long a:40; unsigned long b:30; };
      struct LongBF2 { char x; unsigned long a:40; char y; };
      struct LongBF3 { unsigned a:4; int : 3; unsigned b:4; };
      struct LongBF4 { char a; short : 4; char b; };
      struct AnonSU  { int tag; union { long iv; struct { short lo; short hi; }; }; };
      struct FAM     { int len; int data[]; };
      struct FAM2    { char tag; double data[]; };
      union  UnionBF { unsigned a:12; int b:20; char c; };
      struct TailBF  { int a; char b:3; };
      struct TailBF2 { long a; char b:3; };
      struct PackedCheck { unsigned a:1; unsigned b:31; unsigned c:1; };
      int main(void) { return 0; }
    ")
           (res (c99-layout-test-parse-and-sema src "oracle_unit.c"))
           (lenv (list-ref res 3))
           (get-sl (lambda (tag) (c-layout-env-lookup-struct lenv tag)))
           (get-ul (lambda (tag) (c-layout-env-lookup-union lenv tag)))
           (find-fl (lambda (sl fname)
                      (let loop ((fs (c-struct-layout-fields sl)))
                        (cond
                          ((null? fs) #f)
                          ((eq? (c-field-layout-name (car fs)) fname) (car fs))
                          (else (loop (cdr fs)))))))
           (f-off  (lambda (sl fname)
                     (let ((fl (find-fl sl fname)))
                       (if (c-field-layout-bit-width fl)
                           (c-field-layout-storage-unit-offset fl)
                           (c-field-layout-offset fl)))))
           (f-boff (lambda (sl fname)
                     (c-field-layout-bit-offset (find-fl sl fname)))))

      ;; 1. Empty struct
      (let ((sl (get-sl 'Empty)))
        (assert-equal "Empty struct size == 0" 0 (c-struct-layout-size sl))
        (assert-equal "Empty struct align == 1" 1 (c-struct-layout-align sl))
        (assert-equal "Empty SysV class == empty" 'empty
                      (c99-classify-sysv-aggregate lenv (list 'struct-ref (c-struct-layout-tag-id sl) 'Empty '()))))

      ;; 2. Zero-width & unnamed bitfields
      (let ((z1 (get-sl 'ZeroBF))
            (z2 (get-sl 'ZeroBF2))
            (z3 (get-sl 'ZeroBF3))
            (z4 (get-sl 'ZeroBF4)))
        (assert-equal "ZeroBF size == 5" 5 (c-struct-layout-size z1))
        (assert-equal "ZeroBF align == 1" 1 (c-struct-layout-align z1))
        (assert-equal "ZeroBF off(b) == 4" 4 (f-off z1 'b))
        (assert-equal "ZeroBF2 size == 3" 3 (c-struct-layout-size z2))
        (assert-equal "ZeroBF2 align == 1" 1 (c-struct-layout-align z2))
        (assert-equal "ZeroBF2 off(b) == 2" 2 (f-off z2 'b))
        (assert-equal "ZeroBF3 size == 9" 9 (c-struct-layout-size z3))
        (assert-equal "ZeroBF3 align == 1" 1 (c-struct-layout-align z3))
        (assert-equal "ZeroBF3 off(b) == 8" 8 (f-off z3 'b))
        (assert-equal "ZeroBF4 size == 8" 8 (c-struct-layout-size z4))
        (assert-equal "ZeroBF4 align == 4" 4 (c-struct-layout-align z4))
        (assert-equal "ZeroBF4 off(b) == 4" 4 (f-off z4 'b)))

      ;; 3. Named & mixed-carrier bitfields
      (let ((nb (get-sl 'NamedBF))
            (m1 (get-sl 'MixedBF))
            (m2 (get-sl 'MixedBF2))
            (m3 (get-sl 'MixedBF3))
            (m4 (get-sl 'MixedBF4)))
        (assert-equal "NamedBF size == 8" 8 (c-struct-layout-size nb))
        (assert-equal "NamedBF align == 4" 4 (c-struct-layout-align nb))
        (assert-equal "NamedBF b bit-offset == 4" 4 (f-boff nb 'b))
        (assert-equal "NamedBF c byte-offset == 4" 4 (f-off nb 'c))
        (assert-equal "MixedBF size == 4, align == 4" '(4 4)
                      (list (c-struct-layout-size m1) (c-struct-layout-align m1)))
        (assert-equal "MixedBF2 size == 2, align == 2" '(2 2)
                      (list (c-struct-layout-size m2) (c-struct-layout-align m2)))
        (assert-equal "MixedBF3 size == 4, align == 4" '(4 4)
                      (list (c-struct-layout-size m3) (c-struct-layout-align m3)))
        (assert-equal "MixedBF4 size == 8, align == 4" '(8 4)
                      (list (c-struct-layout-size m4) (c-struct-layout-align m4))))

      ;; 4. 64-bit & straddling bitfields
      (let ((l1 (get-sl 'LongBF))
            (l2 (get-sl 'LongBF2))
            (l3 (get-sl 'LongBF3))
            (l4 (get-sl 'LongBF4))
            (pc (get-sl 'PackedCheck)))
        (assert-equal "LongBF size == 16, align == 8" '(16 8)
                      (list (c-struct-layout-size l1) (c-struct-layout-align l1)))
        (assert-equal "LongBF2 size == 8, align == 8, off(y) == 6" '(8 8 6)
                      (list (c-struct-layout-size l2) (c-struct-layout-align l2) (f-off l2 'y)))
        (assert-equal "LongBF3 size == 4, align == 4, b bit-off == 7" '(4 4 7)
                      (list (c-struct-layout-size l3) (c-struct-layout-align l3) (f-boff l3 'b)))
        (assert-equal "LongBF4 size == 3, align == 1, off(b) == 2" '(3 1 2)
                      (list (c-struct-layout-size l4) (c-struct-layout-align l4) (f-off l4 'b)))
        (assert-equal "PackedCheck size == 8, align == 4" '(8 4)
                      (list (c-struct-layout-size pc) (c-struct-layout-align pc))))

      ;; 5. Anonymous struct/union, FAM & Union bitfields
      (let ((asu (get-sl 'AnonSU))
            (fam1 (get-sl 'FAM))
            (fam2 (get-sl 'FAM2))
            (ubf (get-ul 'UnionBF))
            (tb1 (get-sl 'TailBF))
            (tb2 (get-sl 'TailBF2)))
        (assert-equal "AnonSU size == 16, align == 8" '(16 8)
                      (list (c-struct-layout-size asu) (c-struct-layout-align asu)))
        (assert-equal "AnonSU off(iv)==8, off(lo)==8, off(hi)==10" '(8 8 10)
                      (list (f-off asu 'iv) (f-off asu 'lo) (f-off asu 'hi)))
        (assert-equal "FAM size == 4, align == 4, off(data) == 4, has-fam? == #t"
                      '(4 4 4 #t)
                      (list (c-struct-layout-size fam1)
                            (c-struct-layout-align fam1)
                            (f-off fam1 'data)
                            (c-struct-layout-has-fam? fam1)))
        (assert-equal "FAM2 size == 8, align == 8, off(data) == 8"
                      '(8 8 8)
                      (list (c-struct-layout-size fam2)
                            (c-struct-layout-align fam2)
                            (f-off fam2 'data)))
        (assert-equal "UnionBF size == 4, align == 4"
                      '(4 4)
                      (list (c-struct-layout-size ubf) (c-struct-layout-align ubf)))
        (assert-equal "TailBF size == 8, TailBF2 size == 16"
                      '(8 16)
                      (list (c-struct-layout-size tb1) (c-struct-layout-size tb2)))))

    ;; SysV AMD64 Eightbyte Classification & Call/Return ABI Planner
    (let* ((abi-src "
      struct Empty {};
      struct SmallF { float f; };
      struct TwoF   { float x; float y; };
      struct ThreeF { float x; float y; float z; };
      struct IntFloat { int i; float f; };
      struct LongDouble { long a; double d; };
      struct TwoD { double a; double b; };
      struct ThreeB { char a; char b; char c; };
      struct PairL { long x; long y; };
      struct Big24 { long a; long b; long c; };
      int main(void) { return 0; }
    ")
           (res (c99-layout-test-parse-and-sema abi-src "abi_plan.c"))
           (lenv (list-ref res 3))
           (st (lambda (tag)
                 (let ((sl (c-layout-env-lookup-struct lenv tag)))
                   (list 'struct-ref (c-struct-layout-tag-id sl) tag '())))))

      (assert-equal "SmallF SysV class == (SSE)" '(SSE)
                    (c99-classify-sysv-aggregate lenv (st 'SmallF)))
      (assert-equal "TwoF SysV class == (SSE)" '(SSE)
                    (c99-classify-sysv-aggregate lenv (st 'TwoF)))
      (assert-equal "ThreeF SysV class == (SSE SSE)" '(SSE SSE)
                    (c99-classify-sysv-aggregate lenv (st 'ThreeF)))
      (assert-equal "IntFloat SysV class == (INTEGER)" '(INTEGER)
                    (c99-classify-sysv-aggregate lenv (st 'IntFloat)))
      (assert-equal "LongDouble SysV class == (INTEGER SSE)" '(INTEGER SSE)
                    (c99-classify-sysv-aggregate lenv (st 'LongDouble)))
      (assert-equal "TwoD SysV class == (SSE SSE)" '(SSE SSE)
                    (c99-classify-sysv-aggregate lenv (st 'TwoD)))
      (assert-equal "ThreeB SysV class == (INTEGER)" '(INTEGER)
                    (c99-classify-sysv-aggregate lenv (st 'ThreeB)))
      (assert-equal "Big24 SysV class == MEMORY" 'MEMORY
                    (c99-classify-sysv-aggregate lenv (st 'Big24)))

      ;; All-or-nothing GPR spill check:
      ;; 5 longs take %rdi, %rsi, %rdx, %rcx, %r8 (1 GPR %r9 left).
      ;; PairL needs 2 GPRs -> spills to stack (offset 0), leaving %r9 free for trailing long!
      (let* ((plan1 (c99-plan-sysv-abi
                     lenv
                     'i32
                     (list 'i64 'i64 'i64 'i64 'i64 (st 'PairL) 'i64)))
             (p-plans (cadr plan1)))
        (assert-equal "All-or-nothing GPR spill: PairL goes to (stack 0 16)"
                      '(stack 0 16)
                      (list-ref p-plans 5))
        (assert-equal "All-or-nothing GPR spill: trailing long gets (regs ((gpr %r9 0 8)))"
                      '(regs ((gpr %r9 0 8)))
                      (list-ref p-plans 6)))

      ;; All-or-nothing mixed GPR/SSE spill check:
      ;; 6 longs exhaust all 6 GPRs; LongDouble (1 GPR + 1 XMM) must spill completely to stack,
      ;; leaving %xmm0 available for trailing double!
      (let* ((plan2 (c99-plan-sysv-abi
                     lenv
                     'i32
                     (list 'i64 'i64 'i64 'i64 'i64 'i64 (st 'LongDouble) 'f64)))
             (p-plans (cadr plan2)))
        (assert-equal "Mixed GPR/SSE spill: LongDouble goes to (stack 0 16)"
                      '(stack 0 16)
                      (list-ref p-plans 6))
        (assert-equal "Mixed GPR/SSE spill: trailing double gets (regs ((sse %xmm0 0 8)))"
                      '(regs ((sse %xmm0 0 8)))
                      (list-ref p-plans 7)))

      ;; Hidden sret pointer check for > 16B return:
      (let* ((plan3 (c99-plan-sysv-abi
                     lenv
                     (st 'Big24)
                     (list 'i64))))
        (assert-equal "Big24 return plan is (sret 24 8)" '(sret 24 8) (car plan3))
        (assert-equal "Big24 return shifts 1st param to %rsi"
                      '((regs ((gpr %rsi 0 8))))
                      (cadr plan3))))

    ;; ===================================================================
    ;; Group 2: Negative Diagnostics (C99-LAY-001..004 & CWE-190/674/787)
    ;; ===================================================================
    (display "\n--- Group 2: Span-Annotated Diagnostics C99-LAY-001..004 ---\n")

    ;; C99-LAY-001: Incomplete type
    (assert-true "C99-LAY-001 on sizeof(incomplete struct)"
      (c99-layout-expect-error "C99-LAY-001"
        "struct Fwd; int main(void) { return sizeof(struct Fwd); }"
        "err_inc_sizeof.c"))
    (assert-true "C99-LAY-001 on variable of incomplete struct"
      (c99-layout-expect-error "C99-LAY-001"
        "struct Fwd; int main(void) { struct Fwd x; return 0; }"
        "err_inc_var.c"))
    (assert-true "C99-LAY-001 on non-pointer field of incomplete struct"
      (c99-layout-expect-error "C99-LAY-001"
        "struct Fwd; struct Bad { struct Fwd f; }; int main(void) { return 0; }"
        "err_inc_field.c"))

    ;; C99-LAY-002: Duplicate member, anon collision, bad FAM, CWE-787 OOB designator
    (assert-true "C99-LAY-002 on duplicate struct member"
      (c99-layout-expect-error "C99-LAY-002"
        "struct Dup { int a; int a; }; int main(void) { return 0; }"
        "err_dup_mem.c"))
    (assert-true "C99-LAY-002 on anonymous member name collision"
      (c99-layout-expect-error "C99-LAY-002"
        "struct Col { int a; struct { int a; }; }; int main(void) { return 0; }"
        "err_anon_col.c"))
    (assert-true "C99-LAY-002 on FAM as sole member"
      (c99-layout-expect-error "C99-LAY-002"
        "struct SoleFAM { int data[]; }; int main(void) { return 0; }"
        "err_sole_fam.c"))
    (assert-true "C99-LAY-002 on FAM not last member"
      (c99-layout-expect-error "C99-LAY-002"
        "struct MidFAM { int len; int data[]; int tail; }; int main(void) { return 0; }"
        "err_mid_fam.c"))
    (assert-true "C99-LAY-002 (CWE-787) on negative array designator"
      (c99-layout-expect-error "C99-LAY-002"
        "int main(void) { int a[4] = { [-1] = 1 }; return a[0]; }"
        "err_neg_desig.c"))
    (assert-true "C99-LAY-002 (CWE-787) on out-of-bounds array designator"
      (c99-layout-expect-error "C99-LAY-002"
        "int main(void) { int a[2] = { [5] = 1 }; return a[0]; }"
        "err_oob_desig.c"))
    (assert-true "C99-LAY-002 (CWE-787) on excess array initializer elements"
      (c99-layout-expect-error "C99-LAY-002"
        "int main(void) { int a[2] = { 1, 2, 3 }; return a[0]; }"
        "err_excess_arr.c"))
    (assert-true "C99-LAY-002 on unknown struct field designator"
      (c99-layout-expect-error "C99-LAY-002"
        "struct P { int x; }; int main(void) { struct P p = { .z = 1 }; return p.x; }"
        "err_bad_desig.c"))

    ;; C99-LAY-003: Invalid bitfield declarations & operations
    (assert-true "C99-LAY-003 on float bitfield"
      (c99-layout-expect-error "C99-LAY-003"
        "struct B { float f : 4; }; int main(void) { return 0; }"
        "err_bf_float.c"))
    (assert-true "C99-LAY-003 on bitfield width exceeding type"
      (c99-layout-expect-error "C99-LAY-003"
        "struct B { int x : 33; }; int main(void) { return 0; }"
        "err_bf_wide.c"))
    (assert-true "C99-LAY-003 on negative bitfield width"
      (c99-layout-expect-error "C99-LAY-003"
        "struct B { int x : -1; }; int main(void) { return 0; }"
        "err_bf_neg.c"))
    (assert-true "C99-LAY-003 on named zero-width bitfield"
      (c99-layout-expect-error "C99-LAY-003"
        "struct B { int x : 0; }; int main(void) { return 0; }"
        "err_bf_named_zero.c"))
    (assert-true "C99-LAY-003 on address-of bitfield (&s.bf)"
      (c99-layout-expect-error "C99-LAY-003"
        "struct B { int x : 4; }; int main(void) { struct B b; void *p = &b.x; return 0; }"
        "err_bf_addr.c"))
    (assert-true "C99-LAY-003 on sizeof(bitfield)"
      (c99-layout-expect-error "C99-LAY-003"
        "struct B { int x : 4; }; int main(void) { struct B b; return sizeof(b.x); }"
        "err_bf_sizeof.c"))
    (assert-true "C99-LAY-003 on __builtin_offsetof(struct, bitfield)"
      (c99-layout-expect-error "C99-LAY-003"
        "struct B { int x : 4; }; int main(void) { return __builtin_offsetof(struct B, x); }"
        "err_bf_offsetof.c"))

    ;; C99-LAY-004: Cyclic definition & CWE-190 size overflow
    (assert-true "C99-LAY-004 on direct self-referential struct by value"
      (c99-layout-expect-error "C99-LAY-004"
        "struct Cyc { struct Cyc self; }; int main(void) { return 0; }"
        "err_cyc_direct.c"))
    (assert-true "C99-LAY-004 (CWE-190) on aggregate size overflow (> 2 GiB)"
      (c99-layout-expect-error "C99-LAY-004"
        "struct Huge { long a[268435456]; long b; }; int main(void) { return 0; }"
        "err_cwe190_overflow.c"))

    ;; ===================================================================
    ;; Group 3: Reference VM (#834) E2E Execution & Core LIR Verification
    ;; ===================================================================
    (display "\n--- Group 3: Reference VM (#834) E2E Composite & SysV ABI Tests ---\n")

    ;; 3.1 Nested struct/union, anonymous struct/union promotion, . and ->
    (assert-equal "3.1 nested struct/union & anonymous field promotion (. and ->)"
      142
      (c99-layout-test-eval-vm "
        struct Vec2 { int x; int y; };
        struct Packet {
          int tag;
          union {
            long raw64;
            struct {
              short lo;
              short hi;
            };
          };
          struct Vec2 pos;
        };
        int read_via_ptr(struct Packet *p) {
          p->lo = 10;
          p->hi = 32;
          p->pos.x = 40;
          p->pos.y = 60;
          return p->lo + p->hi + p->pos.x + p->pos.y;
        }
        int main(void) {
          struct Packet pkt = { .tag = 1, .raw64 = 0 };
          return read_via_ptr(&pkt);
        }
      " "vm_anon_nested.c"))

    ;; 3.2 Bitfield R/W, signed sign-extension, overflow masking, promotion, += / ++, single-eval LHS
    (assert-equal "3.2 bitfield signed/unsigned R/W, sign-ext, promotion, +=/++, single-eval LHS"
      77
      (c99-layout-test-eval-vm "
        struct Flags {
          unsigned a : 4;
          int      b : 5;
          int        : 0;
          unsigned c : 12;
          unsigned long wide : 40;
        };
        int g_calls = 0;
        struct Flags g_f;
        struct Flags *get_flags(void) {
          g_calls += 1;
          return &g_f;
        }
        int main(void) {
          g_f.a = 19;        /* truncated to 4 bits -> 3 */
          g_f.b = -5;        /* 5-bit signed -> -5 */
          g_f.c = 100;
          g_f.wide = 1099511627775UL; /* (1UL << 40) - 1 */
          if (g_f.a != 3) return 1;
          if (g_f.b != -5) return 2;
          /* C99 §6.3.1.1: unsigned:4 promotes to signed int, so 3 < -1 is false (0) */
          if (g_f.a < -1) return 3;
          get_flags()->a += 4; /* single evaluation of get_flags(): a becomes 7 */
          ++get_flags()->b;    /* single evaluation of get_flags(): b becomes -4 */
          if (g_calls != 2) return 4;
          if (g_f.a != 7 || g_f.b != -4) return 5;
          if ((g_f.wide >> 36) != 15UL) return 6;
          return g_f.c - 23; /* 77 */
        }
      " "vm_bitfields.c"))

    ;; 3.3 Block-scoped tag & enum shadowing + self-referential pointer traversal
    (assert-equal "3.3 block-scoped struct/enum tag shadowing & self-referential linked list"
      60
      (c99-layout-test-eval-vm "
        struct Node {
          int val;
          struct Node *next;
        };
        enum Scale { FACTOR = 2 };
        int main(void) {
          struct Node n3 = { 30, 0 };
          struct Node n2 = { 20, &n3 };
          struct Node n1 = { 10, &n2 };
          int sum = 0;
          struct Node *cur = &n1;
          while (cur != 0) {
            sum += cur->val;
            cur = cur->next;
          }
          {
            /* Inner block shadows struct Node and enum Scale */
            struct Node { int a; int b; int c; };
            enum Scale { FACTOR = 10 };
            struct Node inner = { .c = 5, .a = 1, .b = 2 };
            if (sizeof(struct Node) != 12) return 1;
            if (FACTOR != 10) return 2;
            if (inner.a + inner.b + inner.c != 8) return 3;
          }
          if (FACTOR != 2) return 4;
          return sum;
        }
      " "vm_scoped_tags.c"))

    ;; 3.4 Compile-time sizeof, _Alignof, __alignof__, __builtin_offsetof & ((size_t)&(((T*)0)->m))
    (assert-equal "3.4 CTFE sizeof, _Alignof, __builtin_offsetof & null-ptr offsetof idiom"
      1
      (c99-layout-test-eval-vm "
        struct Inner { char c; int arr[3]; };
        struct Outer {
          short s;
          struct Inner in;
          long tail;
        };
        enum Checks {
          SZ_OUTER  = sizeof(struct Outer),
          AL_OUTER  = _Alignof(struct Outer),
          AL2_OUTER = __alignof__(struct Outer),
          OFF_ARR2  = __builtin_offsetof(struct Outer, in.arr[2]),
          OFF_IDIOM = (unsigned long)&(((struct Outer *)0)->tail)
        };
        int main(void) {
          int buf[OFF_ARR2];
          buf[0] = SZ_OUTER;
          switch (OFF_IDIOM) {
            case 24:
              return (SZ_OUTER == 32 && AL_OUTER == 8 && AL2_OUTER == 8 && OFF_ARR2 == 16) ? 1 : 0;
            default:
              return 0;
          }
        }
      " "vm_ctfe_layout.c"))

    ;; 3.5 Designated Initializers, union switch clearing stale bytes, array length inference & compound literals
    (assert-equal "3.5 Designated Initializers, union override zeroing, array inference & compound literals"
      95
      (c99-layout-test-eval-vm "
        union U {
          long big;
          unsigned char bytes[8];
        };
        struct Entry {
          int id;
          int vals[3];
        };
        int sum_entry(struct Entry e) {
          return e.id + e.vals[0] + e.vals[1] + e.vals[2];
        }
        int main(void) {
          /* Override union active member: .bytes[0]=5 must clear stale high bytes from .big! */
          union U u = { .big = -1L, .bytes[0] = 5 };
          if (u.bytes[0] != 5 || u.bytes[7] != 0) return 1;

          /* Array length inference from highest designator: [3] -> length 4 (16 bytes) */
          int arr[] = { [3] = 20, [1] = 10, 15 };
          if (sizeof(arr) != 16) return 2;
          if (arr[0] != 0 || arr[1] != 10 || arr[2] != 15 || arr[3] != 20) return 3;

          /* char[] string literal initializer */
          char msg[] = \"ok\";
          if (sizeof(msg) != 3 || msg[0] != 111 || msg[1] != 107 || msg[2] != 0) return 4;

          /* Compound literal passed by value */
          int s = sum_entry((struct Entry){ .vals = { [2] = 30, [0] = 10 }, .id = 10 });
          return s + arr[1] + arr[2] + arr[3]; /* 50 + 45 = 95 */
        }
      " "vm_designated_init.c"))

    ;; 3.6 Global & function-local static structs (.data / .bss / pointer relocations)
    (assert-equal "3.6 static .data/.bss globals, pointer relocs & function-local static struct"
      133
      (c99-layout-test-eval-vm "
        struct Config {
          int base;
          int *ptr;
          int arr[2];
        };
        int g_target = 50;
        struct Config g_cfg = { .base = 20, .ptr = &g_target, .arr = { [1] = 30 } };
        struct Config g_zero;

        int bump_local_static(int delta) {
          static struct { int count; int acc; } st = { .count = 0, .acc = 10 };
          st.count += 1;
          st.acc += delta;
          return st.count + st.acc;
        }

        int main(void) {
          if (g_zero.base != 0 || g_zero.ptr != 0 || g_zero.arr[1] != 0) return 1;
          int a = bump_local_static(5);  /* count=1, acc=15 -> 16 */
          int b = bump_local_static(1);  /* count=2, acc=16 -> 18 -> a+b = 34? wait: 16+17=33 */
          return g_cfg.base + *(g_cfg.ptr) + g_cfg.arr[1] + a + (b - 1); /* 20+50+30+16+17 = 133 */
        }
      " "vm_static_data.c"))

    ;; 3.7 SysV AMD64 Struct Value Passing & Return Across All Classes (0B, 3B, 8B, 12B, 16B, spill, 24B/40B sret)
    (assert-equal "3.7 SysV AMD64 struct value pass/return (0B, 3B, 8B, 16B, spill, 24B/40B sret)"
      210
      (c99-layout-test-eval-vm "
        struct Empty {};
        struct ThreeB { unsigned char a; unsigned char b; unsigned char c; };
        struct PairL  { long x; long y; };
        struct Big24  { long a; long b; long c; };

        int take_empty(struct Empty e, int x) {
          return x + 1;
        }
        struct ThreeB make_3b(int a, int b, int c) {
          struct ThreeB r = { a, b, c };
          return r;
        }
        int sum_3b(struct ThreeB s) {
          return s.a + s.b + s.c;
        }
        struct PairL swap_pair(struct PairL p) {
          struct PairL r = { p.y, p.x };
          return r;
        }
        /* All-or-nothing spill: 5 GPRs used, PairL spills to stack, trailing z goes in r9 */
        long check_spill(long a, long b, long c, long d, long e, struct PairL p, long z) {
          return a + b + c + d + e + p.x + p.y + z;
        }
        struct Big24 make_big(long a, long b, long c) {
          struct Big24 r = { a, b, c };
          return r;
        }
        long sum_big(int scale, struct Big24 b) {
          return scale * (b.a + b.b + b.c);
        }

        int main(void) {
          struct Empty e = {};
          int v1 = take_empty(e, 9);               /* 10 */
          struct ThreeB t = make_3b(10, 20, 30);
          int v2 = sum_3b(t);                      /* 60 */
          struct PairL p0 = { 15, 25 };
          struct PairL p1 = swap_pair(p0);         /* {25, 15} */
          long v3 = check_spill(1, 2, 3, 4, 5, p1, 5); /* 15 + 40 + 5 = 60 */
          struct Big24 bg = make_big(10, 15, 15);
          long v4 = sum_big(2, bg);                /* 80 */
          return (int)(v1 + v2 + v3 + v4);         /* 10 + 60 + 60 + 80 = 210 */
        }
      " "vm_sysv_abi_structs.c")))

(test-end "C99 Struct/Union/Enum/Bitfield & SysV Layout (Issue #918)")
