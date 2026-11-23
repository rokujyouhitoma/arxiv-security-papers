;;; =======================================================================
;;; ULisp C99 Frontend: Pure Scheme C99 Preprocessor (CPP)
;;; Conforms to DSN-33-11 §3.3/§4.1, DSN-33-32 §3.1/§5.1 & Issue #914
;;; Implements:
;;;   - #include "..." / <...> resolution, #pragma once & #ifndef guard cache
;;;   - Object/Function/Variadic (#define ... __VA_ARGS__), #undef, -D/-I/-U
;;;   - Dave Prosser Blue-painted (hide-set) recursive macro suppression
;;;   - # stringification & ## token pasting (+ , ## __VA_ARGS__)
;;;   - CTFE (#825) & 64-bit (#832) #if / #elif constant integer evaluation
;;;   - Source span propagation (span-macro-origin) & diagnostic reporting (#833)
;;; =======================================================================

;;; -----------------------------------------------------------------------
;;; 1. Data Structures: <cpp-macro>, <cpp-context> & Metrics
;;; -----------------------------------------------------------------------

(define-record-type <cpp-macro>
  (make-cpp-macro name function-like? params variadic? body def-span builtin-proc)
  cpp-macro?
  (name           cpp-macro-name)
  (function-like? cpp-macro-function-like?)
  (params         cpp-macro-params)
  (variadic?      cpp-macro-variadic?)
  (body           cpp-macro-body)
  (def-span       cpp-macro-def-span)
  (builtin-proc   cpp-macro-builtin-proc))

(define-record-type <cpp-context>
  (make-cpp-context include-paths system-include-paths macros
                    pragma-once-files include-guard-cache
                    include-depth max-include-depth
                    expansion-steps max-expansion-steps
                    virtual-files included-files macro-buckets)
  cpp-context?
  (include-paths        cpp-ctx-include-paths        cpp-ctx-include-paths-set!)
  (system-include-paths cpp-ctx-system-include-paths cpp-ctx-system-include-paths-set!)
  (macros               cpp-ctx-macros               cpp-ctx-macros-set!)
  (pragma-once-files    cpp-ctx-pragma-once-files    cpp-ctx-pragma-once-files-set!)
  (include-guard-cache  cpp-ctx-include-guard-cache  cpp-ctx-include-guard-cache-set!)
  (include-depth        cpp-ctx-include-depth        cpp-ctx-include-depth-set!)
  (max-include-depth    cpp-ctx-max-include-depth)
  (expansion-steps      cpp-ctx-expansion-steps      cpp-ctx-expansion-steps-set!)
  (max-expansion-steps  cpp-ctx-max-expansion-steps)
  (virtual-files        cpp-ctx-virtual-files        cpp-ctx-virtual-files-set!)
  (included-files       cpp-ctx-included-files       cpp-ctx-included-files-set!)
  (macro-buckets        cpp-ctx-macro-buckets        cpp-ctx-macro-buckets-set!))

(define (cpp-record-included-file! ctx path)
  (if (and (string? path) (> (string-length path) 0))
      (let ((norm (%cpp-normalize-path path)))
        (if (not (member norm (cpp-ctx-included-files ctx)))
            (cpp-ctx-included-files-set!
             ctx (append (cpp-ctx-included-files ctx) (list norm)))))))

(define *cpp-max-include-depth* 64)
(define *cpp-max-expansion-steps* 1000000)
(define *cpp-include-skip-counter* (cons 0 '()))

(define (cpp-reset-metrics!)
  (set-car! *cpp-include-skip-counter* 0))

(define (cpp-include-skip-count)
  (car *cpp-include-skip-counter*))

(define (%cpp-inc-skip-count!)
  (set-car! *cpp-include-skip-counter* (+ (car *cpp-include-skip-counter*) 1)))

(define (%cpp-raise-error code sp msg)
  (let* ((safe-sp (if (source-span? sp)
                      sp
                      (make-source-span "<c99-cpp>" 1 1 1 1 #f (next-source-span-id!))))
         (diag (make-diagnostic 'error code safe-sp msg)))
    (report-diagnostic diag)
    (raise (list 'c99-cpp-error code msg safe-sp))))

(define (%cpp-attach-origin sp origin-sp)
  (if (not (source-span? sp))
      origin-sp
      (if (source-span? origin-sp)
          (make-source-span (span-file sp)
                            (span-start-line sp)
                            (span-start-col sp)
                            (span-end-line sp)
                            (span-end-col sp)
                            origin-sp
                            (next-source-span-id!))
          sp)))

(define (%cpp-tokens-attach-origin toks call-span)
  (map (lambda (t)
         (c-token-clone-with-span t (%cpp-attach-origin (c-token-span t) call-span)))
       toks))

;;; -----------------------------------------------------------------------
;;; 2. Path Normalization & Include Path Management
;;; -----------------------------------------------------------------------

(define (%cpp-string-split-slash str)
  (let ((n (string-length str)))
    (let loop ((i 0) (start 0) (parts '()))
      (cond
        ((>= i n)
         (reverse (if (> i start) (cons (substring str start i) parts) parts)))
        ((char=? (string-ref str i) #\/)
         (loop (+ i 1) (+ i 1)
               (if (> i start) (cons (substring str start i) parts) parts)))
        (else
         (loop (+ i 1) start parts))))))

(define (%cpp-string-join-with parts sep)
  (if (null? parts)
      ""
      (let loop ((rest (cdr parts)) (acc (list (car parts))))
        (if (null? rest)
            (apply string-append (reverse acc))
            (loop (cdr rest) (cons (car rest) (cons sep acc)))))))

(define (%cpp-normalize-path path)
  (let* ((n (string-length path))
         (abs? (and (> n 0) (char=? (string-ref path 0) #\/)))
         (segs (%cpp-string-split-slash path)))
    (let loop ((rest segs) (stack '()))
      (if (null? rest)
          (let ((joined (%cpp-string-join-with (reverse stack) "/")))
            (cond
              ((and abs? (string=? joined "")) "/")
              (abs? (string-append "/" joined))
              ((string=? joined "") ".")
              (else joined)))
          (let ((seg (car rest)))
            (cond
              ((string=? seg ".") (loop (cdr rest) stack))
              ((string=? seg "..")
               (if (and (pair? stack) (not (string=? (car stack) "..")))
                   (loop (cdr rest) (cdr stack))
                   (if abs?
                       (loop (cdr rest) stack)
                       (loop (cdr rest) (cons ".." stack)))))
              (else
               (loop (cdr rest) (cons seg stack)))))))))

(define (%cpp-path-dirname path)
  (let ((n (string-length path)))
    (let loop ((i (- n 1)))
      (cond
        ((< i 0) ".")
        ((char=? (string-ref path i) #\/)
         (if (= i 0) "/" (substring path 0 i)))
        (else (loop (- i 1)))))))

(define (%cpp-path-join dir rel)
  (let ((rn (string-length rel)))
    (if (and (> rn 0) (char=? (string-ref rel 0) #\/))
        (%cpp-normalize-path rel)
        (if (or (string=? dir "") (string=? dir "."))
            (%cpp-normalize-path rel)
            (%cpp-normalize-path (string-append dir "/" rel))))))

(define *cpp-builtin-system-include-paths*
  '("frontend_c/include" "ulisp/frontend_c/include" "/__ulisp_builtin__"))

(define (%cpp-insert-before-builtins paths new-path)
  (let loop ((xs paths) (acc '()))
    (cond
      ((null? xs) (reverse (cons new-path acc)))
      ((member (car xs) *cpp-builtin-system-include-paths*)
       (append (reverse acc) (cons new-path xs)))
      (else
       (loop (cdr xs) (cons (car xs) acc))))))

(define (cpp-add-include-path! ctx dir-path . maybe-system?)
  (let ((sys? (and (pair? maybe-system?) (car maybe-system?)))
        (norm (%cpp-normalize-path dir-path)))
    (if sys?
        (cpp-ctx-system-include-paths-set!
         ctx (%cpp-insert-before-builtins (cpp-ctx-system-include-paths ctx) norm))
        (cpp-ctx-include-paths-set!
         ctx (append (cpp-ctx-include-paths ctx) (list norm))))))

(define (cpp-register-virtual-file! ctx filepath content-str)
  (let* ((norm (%cpp-normalize-path filepath))
         (filtered
          (let loop ((xs (cpp-ctx-virtual-files ctx)) (acc '()))
            (cond
              ((null? xs) (reverse acc))
              ((string=? (caar xs) norm) (loop (cdr xs) acc))
              (else (loop (cdr xs) (cons (car xs) acc)))))))
    (cpp-ctx-virtual-files-set! ctx (cons (cons norm content-str) filtered))))

(define (%cpp-lookup-virtual-file ctx path)
  (let ((slot (assoc (%cpp-normalize-path path) (cpp-ctx-virtual-files ctx))))
    (if slot (cdr slot) #f)))

;;; -----------------------------------------------------------------------
;;; 3. Macro Table Operations & Built-in Predefined Macros
;;; -----------------------------------------------------------------------

(define (%cpp-sym-bucket sym)
  (let* ((s (symbol->string sym))
         (n (string-length s)))
    (if (= n 0)
        0
        (modulo (+ (* (char->integer (string-ref s 0)) 31)
                   (+ (* (char->integer (string-ref s (- n 1))) 17)
                      n))
                128))))

(define (%cpp-bucket-remove lst name-sym)
  (let loop ((xs lst) (acc '()))
    (cond
      ((null? xs) (reverse acc))
      ((eq? (caar xs) name-sym) (loop (cdr xs) acc))
      (else (loop (cdr xs) (cons (car xs) acc))))))

(define (%cpp-rebuild-macro-buckets! ctx)
  (let ((vec (make-vector 128 '())))
    (for-each
     (lambda (entry)
       (let ((idx (%cpp-sym-bucket (car entry))))
         (vector-set! vec idx (cons entry (vector-ref vec idx)))))
     (reverse (cpp-ctx-macros ctx)))
    (cpp-ctx-macro-buckets-set! ctx vec)))

(define (cpp-lookup-macro ctx name-sym)
  (let* ((vec (cpp-ctx-macro-buckets ctx))
         (slot (assq name-sym (vector-ref vec (%cpp-sym-bucket name-sym)))))
    (if slot (cdr slot) #f)))

(define (%cpp-set-macro! ctx name-sym mac)
  (let* ((vec (cpp-ctx-macro-buckets ctx))
         (idx (%cpp-sym-bucket name-sym))
         (bucket (vector-ref vec idx))
         (had? (assq name-sym bucket))
         (new-entry (cons name-sym mac)))
    (vector-set! vec idx (cons new-entry (if had? (%cpp-bucket-remove bucket name-sym) bucket)))
    (if had?
        (cpp-ctx-macros-set! ctx (cons new-entry (%cpp-bucket-remove (cpp-ctx-macros ctx) name-sym)))
        (cpp-ctx-macros-set! ctx (cons new-entry (cpp-ctx-macros ctx))))))

(define (cpp-undef! ctx name-sym)
  (let* ((vec (cpp-ctx-macro-buckets ctx))
         (idx (%cpp-sym-bucket name-sym))
         (bucket (vector-ref vec idx)))
    (if (assq name-sym bucket)
        (begin
          (vector-set! vec idx (%cpp-bucket-remove bucket name-sym))
          (cpp-ctx-macros-set! ctx (%cpp-bucket-remove (cpp-ctx-macros ctx) name-sym))))))

(define (cpp-define-object! ctx name-sym body-tokens . maybe-span)
  (let ((sp (if (pair? maybe-span) (car maybe-span) #f)))
    (%cpp-set-macro! ctx name-sym
                     (make-cpp-macro name-sym #f '() #f body-tokens sp #f))))

(define (cpp-define-function! ctx name-sym params variadic? body-tokens . maybe-span)
  (let ((sp (if (pair? maybe-span) (car maybe-span) #f)))
    (%cpp-set-macro! ctx name-sym
                     (make-cpp-macro name-sym #t params variadic? body-tokens sp #f))))

(define (%cpp-strip-eof toks)
  (let loop ((xs toks) (acc '()))
    (cond
      ((null? xs) (reverse acc))
      ((eq? (c-token-kind (car xs)) 'eof) (loop (cdr xs) acc))
      (else (loop (cdr xs) (cons (car xs) acc))))))

(define (%cpp-find-eq-idx str)
  (let ((n (string-length str)))
    (let loop ((i 0))
      (cond
        ((>= i n) #f)
        ((char=? (string-ref str i) #\=) i)
        (else (loop (+ i 1)))))))

(define (cpp-define-string! ctx name-str . maybe-val-str)
  (let* ((eq-idx (if (pair? maybe-val-str) #f (%cpp-find-eq-idx name-str)))
         (clean-name (if eq-idx (substring name-str 0 eq-idx) name-str))
         (val-str (cond
                    ((pair? maybe-val-str) (car maybe-val-str))
                    (eq-idx (substring name-str (+ eq-idx 1) (string-length name-str)))
                    (else "1")))
         (body-toks (%cpp-strip-eof (c-tokenize-string val-str "<cmdline>")))
         (sym (string->symbol clean-name)))
    (cpp-define-object! ctx sym body-toks #f)))

(define (%cpp-register-builtin! ctx name-sym proc)
  (%cpp-set-macro! ctx name-sym
                   (make-cpp-macro name-sym #f '() #f '() #f proc)))

(define (%cpp-escape-c-string str)
  (let ((n (string-length str)))
    (let loop ((i 0) (parts '()))
      (if (>= i n)
          (apply string-append (reverse parts))
          (let* ((ch (string-ref str i))
                 (seg (cond
                        ((char=? ch #\\) "\\\\")
                        ((char=? ch #\") "\\\"")
                        ((char=? ch #\newline) "\\n")
                        ((char=? ch #\tab) "\\t")
                        (else (string ch)))))
            (loop (+ i 1) (cons seg parts)))))))

(define *c99-builtin-stdarg-h*
  (string-append
   "/* ULisp C99 Built-in <stdarg.h> (ISO C99 §7.15 & System V AMD64 psABI §3.5.7) */\n"
   "#ifndef _ULISP_STDARG_H\n"
   "#define _ULISP_STDARG_H\n\n"
   "typedef __builtin_va_list va_list;\n"
   "typedef __builtin_va_list __gnuc_va_list;\n\n"
   "#define va_start(ap, last) __builtin_va_start(ap, last)\n"
   "#define va_arg(ap, type)   __builtin_va_arg(ap, type)\n"
   "#define va_end(ap)         __builtin_va_end(ap)\n"
   "#define va_copy(dst, src)  __builtin_va_copy(dst, src)\n\n"
   "#endif /* _ULISP_STDARG_H */\n"))

(define *c99-builtin-setjmp-h*
  (string-append
   "/* ULisp C99 Built-in <setjmp.h> (ISO C99 §7.13 & SysV AMD64 ULisp 64B ABI) */\n"
   "#ifndef _ULISP_SETJMP_H\n"
   "#define _ULISP_SETJMP_H\n\n"
   "typedef long jmp_buf[8];\n"
   "typedef long sigjmp_buf[8];\n\n"
   "int setjmp(jmp_buf env);\n"
   "int _setjmp(jmp_buf env);\n"
   "int sigsetjmp(sigjmp_buf env, int savemask);\n"
   "void longjmp(jmp_buf env, int val);\n"
   "void _longjmp(jmp_buf env, int val);\n"
   "void siglongjmp(sigjmp_buf env, int val);\n\n"
   "#endif /* _ULISP_SETJMP_H */\n"))

(define *c99-builtin-math-h*
  (string-append
   "/* ULisp C99 Built-in <math.h> (ISO C99 §7.12 & System V AMD64 libm ABI) */\n"
   "#ifndef _ULISP_MATH_H\n"
   "#define _ULISP_MATH_H\n\n"
   "#define M_E        2.7182818284590452354\n"
   "#define M_LOG2E    1.4426950408889634074\n"
   "#define M_LOG10E   0.43429448190325182765\n"
   "#define M_LN2      0.69314718055994530942\n"
   "#define M_LN10     2.30258509299404568402\n"
   "#define M_PI       3.14159265358979323846\n"
   "#define M_PI_2     1.57079632679489661923\n"
   "#define M_PI_4     0.78539816339744830962\n"
   "#define M_1_PI     0.31830988618379067154\n"
   "#define M_2_PI     0.63661977236758134308\n"
   "#define M_2_SQRTPI 1.12837916709551257390\n"
   "#define M_SQRT2    1.41421356237309504880\n"
   "#define M_SQRT1_2  0.70710678118654752440\n\n"
   "#define HUGE_VAL   (1.0 / 0.0)\n"
   "#define HUGE_VALF  (1.0f / 0.0f)\n"
   "#define INFINITY   (1.0f / 0.0f)\n"
   "#define NAN        (0.0f / 0.0f)\n\n"
   "#define isnan(x)    ((x) != (x))\n"
   "#define isfinite(x) (((x) - (x)) == 0.0)\n"
   "#define isinf(x)    (((x) == (x)) && (((x) - (x)) != 0.0))\n"
   "#define signbit(x)  (((x) < 0.0) || (((x) == 0.0) && ((1.0 / (x)) < 0.0)))\n\n"
   "typedef float float_t;\n"
   "typedef double double_t;\n\n"
   "double acos(double x);\n"
   "double asin(double x);\n"
   "double atan(double x);\n"
   "double atan2(double y, double x);\n"
   "double cos(double x);\n"
   "double sin(double x);\n"
   "double tan(double x);\n"
   "double cosh(double x);\n"
   "double sinh(double x);\n"
   "double tanh(double x);\n"
   "double exp(double x);\n"
   "double frexp(double x, int *exp);\n"
   "double ldexp(double x, int exp);\n"
   "double log(double x);\n"
   "double log10(double x);\n"
   "double log2(double x);\n"
   "double modf(double x, double *iptr);\n"
   "double pow(double x, double y);\n"
   "double sqrt(double x);\n"
   "double ceil(double x);\n"
   "double fabs(double x);\n"
   "double floor(double x);\n"
   "double fmod(double x, double y);\n"
   "double trunc(double x);\n"
   "double round(double x);\n"
   "double hypot(double x, double y);\n"
   "double copysign(double x, double y);\n"
   "double fmin(double x, double y);\n"
   "double fmax(double x, double y);\n\n"
   "float acosf(float x);\n"
   "float asinf(float x);\n"
   "float atanf(float x);\n"
   "float atan2f(float y, float x);\n"
   "float cosf(float x);\n"
   "float sinf(float x);\n"
   "float tanf(float x);\n"
   "float coshf(float x);\n"
   "float sinhf(float x);\n"
   "float tanhf(float x);\n"
   "float expf(float x);\n"
   "float frexpf(float x, int *exp);\n"
   "float ldexpf(float x, int exp);\n"
   "float logf(float x);\n"
   "float log10f(float x);\n"
   "float log2f(float x);\n"
   "float modff(float x, float *iptr);\n"
   "float powf(float x, float y);\n"
   "float sqrtf(float x);\n"
   "float ceilf(float x);\n"
   "float fabsf(float x);\n"
   "float floorf(float x);\n"
   "float fmodf(float x, float y);\n"
   "float truncf(float x);\n"
   "float roundf(float x);\n"
   "float hypotf(float x, float y);\n"
   "float copysignf(float x, float y);\n"
   "float fminf(float x, float y);\n"
   "float fmaxf(float x, float y);\n\n"
   "#endif /* _ULISP_MATH_H */\n"))

(define *c99-builtin-stddef-h*
  (string-append
   "#ifndef _ULISP_STDDEF_H\n#define _ULISP_STDDEF_H\n"
   "typedef long ptrdiff_t;\ntypedef unsigned long size_t;\ntypedef int wchar_t;\n"
   "typedef struct { long long __max_align_ll; double __max_align_d; } max_align_t;\n"
   "#ifndef NULL\n#define NULL ((void *)0)\n#endif\n"
   "#ifndef offsetof\n#define offsetof(type, member) __builtin_offsetof(type, member)\n#endif\n"
   "#endif\n"))

(define *c99-builtin-stdint-h*
  (string-append
   "#ifndef _ULISP_STDINT_H\n#define _ULISP_STDINT_H\n"
   "typedef signed char int8_t; typedef short int16_t; typedef int int32_t; typedef long int64_t;\n"
   "typedef unsigned char uint8_t; typedef unsigned short uint16_t; typedef unsigned int uint32_t; typedef unsigned long uint64_t;\n"
   "typedef signed char int_least8_t; typedef short int_least16_t; typedef int int_least32_t; typedef long int_least64_t;\n"
   "typedef unsigned char uint_least8_t; typedef unsigned short uint_least16_t; typedef unsigned int uint_least32_t; typedef unsigned long uint_least64_t;\n"
   "typedef signed char int_fast8_t; typedef long int_fast16_t; typedef long int_fast32_t; typedef long int_fast64_t;\n"
   "typedef unsigned char uint_fast8_t; typedef unsigned long uint_fast16_t; typedef unsigned long uint_fast32_t; typedef unsigned long uint_fast64_t;\n"
   "typedef long intptr_t; typedef unsigned long uintptr_t;\n"
   "typedef long intmax_t; typedef unsigned long uintmax_t;\n"
   "#define INT8_MIN (-128)\n#define INT16_MIN (-32767 - 1)\n#define INT32_MIN (-2147483647 - 1)\n#define INT64_MIN (-9223372036854775807L - 1L)\n"
   "#define INT8_MAX 127\n#define INT16_MAX 32767\n#define INT32_MAX 2147483647\n#define INT64_MAX 9223372036854775807L\n"
   "#define UINT8_MAX 255\n#define UINT16_MAX 65535\n#define UINT32_MAX 4294967295U\n#define UINT64_MAX 18446744073709551615UL\n"
   "#define INTPTR_MIN INT64_MIN\n#define INTPTR_MAX INT64_MAX\n#define UINTPTR_MAX UINT64_MAX\n"
   "#define INTMAX_MIN INT64_MIN\n#define INTMAX_MAX INT64_MAX\n#define UINTMAX_MAX UINT64_MAX\n"
   "#define PTRDIFF_MIN INT64_MIN\n#define PTRDIFF_MAX INT64_MAX\n#define SIZE_MAX UINT64_MAX\n"
   "#define SIG_ATOMIC_MIN INT32_MIN\n#define SIG_ATOMIC_MAX INT32_MAX\n"
   "#define INT8_C(x) x\n#define INT16_C(x) x\n#define INT32_C(x) x\n#define INT64_C(x) x ## L\n"
   "#define UINT8_C(x) x\n#define UINT16_C(x) x\n#define UINT32_C(x) x ## U\n#define UINT64_C(x) x ## UL\n"
   "#define INTMAX_C(x) x ## L\n#define UINTMAX_C(x) x ## UL\n"
   "#endif\n"))

(define *c99-builtin-stdbool-h*
  "#ifndef _ULISP_STDBOOL_H\n#define _ULISP_STDBOOL_H\n#define bool _Bool\n#define true 1\n#define false 0\n#define __bool_true_false_are_defined 1\n#endif\n")

(define *c99-builtin-limits-h*
  (string-append
   "#ifndef _ULISP_LIMITS_H\n#define _ULISP_LIMITS_H\n"
   "#define CHAR_BIT 8\n#define MB_LEN_MAX 16\n"
   "#define SCHAR_MIN (-128)\n#define SCHAR_MAX 127\n#define UCHAR_MAX 255\n"
   "#define CHAR_MIN SCHAR_MIN\n#define CHAR_MAX SCHAR_MAX\n"
   "#define SHRT_MIN (-32767 - 1)\n#define SHRT_MAX 32767\n#define USHRT_MAX 65535\n"
   "#define INT_MIN (-2147483647 - 1)\n#define INT_MAX 2147483647\n#define UINT_MAX 4294967295U\n"
   "#define LONG_MIN (-9223372036854775807L - 1L)\n#define LONG_MAX 9223372036854775807L\n#define ULONG_MAX 18446744073709551615UL\n"
   "#define LLONG_MIN (-9223372036854775807LL - 1LL)\n#define LLONG_MAX 9223372036854775807LL\n#define ULLONG_MAX 18446744073709551615ULL\n"
   "#endif\n"))

(define *c99-builtin-float-h*
  (string-append
   "#ifndef _ULISP_FLOAT_H\n#define _ULISP_FLOAT_H\n"
   "#define FLT_RADIX 2\n#define FLT_ROUNDS 1\n#define FLT_EVAL_METHOD 0\n"
   "#define FLT_MANT_DIG 24\n#define FLT_DIG 6\n#define FLT_MIN_EXP (-125)\n#define FLT_MAX_EXP 128\n#define FLT_MIN_10_EXP (-37)\n#define FLT_MAX_10_EXP 38\n"
   "#define FLT_MAX 3.40282347e+38F\n#define FLT_MIN 1.17549435e-38F\n#define FLT_EPSILON 1.19209290e-7F\n"
   "#define DBL_MANT_DIG 53\n#define DBL_DIG 15\n#define DBL_MIN_EXP (-1021)\n#define DBL_MAX_EXP 1024\n#define DBL_MIN_10_EXP (-307)\n#define DBL_MAX_10_EXP 308\n"
   "#define DBL_MAX 1.7976931348623157e+308\n#define DBL_MIN 2.2250738585072014e-308\n#define DBL_EPSILON 2.2204460492503131e-16\n"
   "#define LDBL_MANT_DIG 53\n#define LDBL_DIG 15\n#define LDBL_MIN_EXP (-1021)\n#define LDBL_MAX_EXP 1024\n#define LDBL_MIN_10_EXP (-307)\n#define LDBL_MAX_10_EXP 308\n"
   "#define LDBL_MAX 1.7976931348623157e+308\n#define LDBL_MIN 2.2250738585072014e-308\n#define LDBL_EPSILON 2.2204460492503131e-16\n"
   "#endif\n"))

(define *c99-builtin-assert-h*
  (string-append
   "#undef assert\n#ifdef NDEBUG\n#define assert(expr) ((void)0)\n#else\n"
   "#ifndef _ULISP_ASSERT_DECLARED\n#define _ULISP_ASSERT_DECLARED\nextern void abort(void);\n#endif\n"
   "#define assert(expr) ((expr) ? (void)0 : abort())\n#endif\n"))

(define *c99-builtin-errno-h*
  (string-append
   "#ifndef _ULISP_ERRNO_H\n#define _ULISP_ERRNO_H\n"
   "extern int *__errno_location(void);\n#define errno (*__errno_location())\n"
   "#define EPERM 1\n#define ENOENT 2\n#define ESRCH 3\n#define EINTR 4\n#define EIO 5\n#define EBADF 9\n"
   "#define ECHILD 10\n#define EAGAIN 11\n#define ENOMEM 12\n#define EACCES 13\n#define EEXIST 17\n"
   "#define ENOTDIR 20\n#define EISDIR 21\n#define EINVAL 22\n#define EMFILE 24\n#define ENOSPC 28\n"
   "#define EPIPE 32\n#define EDOM 33\n#define ERANGE 34\n#define EILSEQ 84\n#endif\n"))

(define *c99-builtin-ctype-h*
  (string-append
   "#ifndef _ULISP_CTYPE_H\n#define _ULISP_CTYPE_H\n"
   "int isalnum(int c);\nint isalpha(int c);\nint isblank(int c);\nint iscntrl(int c);\n"
   "int isdigit(int c);\nint isgraph(int c);\nint islower(int c);\nint isprint(int c);\n"
   "int ispunct(int c);\nint isspace(int c);\nint isupper(int c);\nint isxdigit(int c);\n"
   "int tolower(int c);\nint toupper(int c);\n#endif\n"))

(define *c99-builtin-string-h*
  (string-append
   "#ifndef _ULISP_STRING_H\n#define _ULISP_STRING_H\n#include <stddef.h>\n"
   "void *memcpy(void *dest, const void *src, size_t n);\nvoid *memmove(void *dest, const void *src, size_t n);\n"
   "void *memset(void *s, int c, size_t n);\nint memcmp(const void *s1, const void *s2, size_t n);\nvoid *memchr(const void *s, int c, size_t n);\n"
   "char *strcpy(char *dest, const char *src);\nchar *strncpy(char *dest, const char *src, size_t n);\n"
   "char *strcat(char *dest, const char *src);\nchar *strncat(char *dest, const char *src, size_t n);\n"
   "int strcmp(const char *s1, const char *s2);\nint strncmp(const char *s1, const char *s2, size_t n);\n"
   "int strcoll(const char *s1, const char *s2);\nsize_t strxfrm(char *dest, const char *src, size_t n);\n"
   "char *strchr(const char *s, int c);\nchar *strrchr(const char *s, int c);\n"
   "size_t strspn(const char *s, const char *accept);\nsize_t strcspn(const char *s, const char *reject);\n"
   "char *strpbrk(const char *s, const char *accept);\nchar *strstr(const char *haystack, const char *needle);\n"
   "char *strtok(char *str, const char *delim);\nsize_t strlen(const char *s);\nchar *strerror(int errnum);\n#endif\n"))

(define *c99-builtin-stdio-h*
  (string-append
   "#ifndef _ULISP_STDIO_H\n#define _ULISP_STDIO_H\n#include <stddef.h>\n"
   "typedef struct _IO_FILE FILE;\ntypedef long fpos_t;\n"
   "extern FILE *stdin;\nextern FILE *stdout;\nextern FILE *stderr;\n"
   "#define EOF (-1)\n#define BUFSIZ 8192\n#define FOPEN_MAX 16\n#define FILENAME_MAX 4096\n#define L_tmpnam 20\n#define TMP_MAX 238328\n"
   "#define SEEK_SET 0\n#define SEEK_CUR 1\n#define SEEK_END 2\n#define _IOFBF 0\n#define _IOLBF 1\n#define _IONBF 2\n"
   "int remove(const char *filename);\nint rename(const char *oldname, const char *newname);\nFILE *tmpfile(void);\nchar *tmpnam(char *s);\n"
   "int fclose(FILE *stream);\nint fflush(FILE *stream);\nFILE *fopen(const char *filename, const char *mode);\n"
   "FILE *freopen(const char *filename, const char *mode, FILE *stream);\nvoid setbuf(FILE *stream, char *buf);\nint setvbuf(FILE *stream, char *buf, int mode, size_t size);\n"
   "int fprintf(FILE *stream, const char *format, ...);\nint fscanf(FILE *stream, const char *format, ...);\nint printf(const char *format, ...);\n"
   "int scanf(const char *format, ...);\nint snprintf(char *s, size_t n, const char *format, ...);\nint sprintf(char *s, const char *format, ...);\nint sscanf(const char *s, const char *format, ...);\n"
   "int vfprintf(FILE *stream, const char *format, __builtin_va_list arg);\nint vprintf(const char *format, __builtin_va_list arg);\n"
   "int vsnprintf(char *s, size_t n, const char *format, __builtin_va_list arg);\nint vsprintf(char *s, const char *format, __builtin_va_list arg);\n"
   "int fgetc(FILE *stream);\nchar *fgets(char *s, int n, FILE *stream);\nint fputc(int c, FILE *stream);\nint fputs(const char *s, FILE *stream);\n"
   "int getc(FILE *stream);\nint getchar(void);\nint putc(int c, FILE *stream);\nint putchar(int c);\nint puts(const char *s);\nint ungetc(int c, FILE *stream);\n"
   "size_t fread(void *ptr, size_t size, size_t nmemb, FILE *stream);\nsize_t fwrite(const void *ptr, size_t size, size_t nmemb, FILE *stream);\n"
   "int fgetpos(FILE *stream, fpos_t *pos);\nint fseek(FILE *stream, long offset, int whence);\nint fsetpos(FILE *stream, const fpos_t *pos);\nlong ftell(FILE *stream);\nvoid rewind(FILE *stream);\n"
   "void clearerr(FILE *stream);\nint feof(FILE *stream);\nint ferror(FILE *stream);\nvoid perror(const char *s);\n"
   "FILE *fdopen(int fd, const char *mode);\nint fileno(FILE *stream);\nFILE *popen(const char *command, const char *type);\nint pclose(FILE *stream);\n"
   "int fseeko(FILE *stream, long offset, int whence);\nlong ftello(FILE *stream);\nint getc_unlocked(FILE *stream);\nvoid flockfile(FILE *filehandle);\nvoid funlockfile(FILE *filehandle);\n#endif\n"))

(define *c99-builtin-stdlib-h*
  (string-append
   "#ifndef _ULISP_STDLIB_H\n#define _ULISP_STDLIB_H\n#include <stddef.h>\n"
   "#define EXIT_FAILURE 1\n#define EXIT_SUCCESS 0\n#define RAND_MAX 2147483647\n#define MB_CUR_MAX 1\n"
   "typedef struct { int quot; int rem; } div_t;\ntypedef struct { long quot; long rem; } ldiv_t;\ntypedef struct { long long quot; long long rem; } lldiv_t;\n"
   "double atof(const char *nptr);\nint atoi(const char *nptr);\nlong atol(const char *nptr);\nlong long atoll(const char *nptr);\n"
   "double strtod(const char *nptr, char **endptr);\nfloat strtof(const char *nptr, char **endptr);\nlong double strtold(const char *nptr, char **endptr);\n"
   "long strtol(const char *nptr, char **endptr, int base);\nlong long strtoll(const char *nptr, char **endptr, int base);\n"
   "unsigned long strtoul(const char *nptr, char **endptr, int base);\nunsigned long long strtoull(const char *nptr, char **endptr, int base);\n"
   "int rand(void);\nvoid srand(unsigned int seed);\nvoid *calloc(size_t nmemb, size_t size);\nvoid free(void *ptr);\nvoid *malloc(size_t size);\nvoid *realloc(void *ptr, size_t size);\n"
   "void abort(void);\nint atexit(void (*func)(void));\nvoid exit(int status);\nvoid _Exit(int status);\nchar *getenv(const char *name);\nint system(const char *string);\n"
   "void *bsearch(const void *key, const void *base, size_t nmemb, size_t size, int (*compar)(const void *, const void *));\n"
   "void qsort(void *base, size_t nmemb, size_t size, int (*compar)(const void *, const void *));\n"
   "int abs(int j);\nlong labs(long j);\nlong long llabs(long long j);\ndiv_t div(int numer, int denom);\nldiv_t ldiv(long numer, long denom);\nlldiv_t lldiv(long long numer, long long denom);\n"
   "int mkstemp(char *template_path);\n#endif\n"))

(define *c99-builtin-time-h*
  (string-append
   "#ifndef _ULISP_TIME_H\n#define _ULISP_TIME_H\n#include <stddef.h>\n"
   "#define CLOCKS_PER_SEC 1000000L\ntypedef long clock_t;\ntypedef long time_t;\n"
   "struct tm { int tm_sec; int tm_min; int tm_hour; int tm_mday; int tm_mon; int tm_year; int tm_wday; int tm_yday; int tm_isdst; long tm_gmtoff; const char *tm_zone; };\n"
   "clock_t clock(void);\ndouble difftime(time_t time1, time_t time0);\ntime_t mktime(struct tm *timeptr);\ntime_t time(time_t *timer);\n"
   "char *asctime(const struct tm *timeptr);\nchar *ctime(const time_t *timer);\nstruct tm *gmtime(const time_t *timer);\nstruct tm *localtime(const time_t *timer);\n"
   "size_t strftime(char *s, size_t maxsize, const char *format, const struct tm *timeptr);\nstruct tm *gmtime_r(const time_t *timer, struct tm *result);\nstruct tm *localtime_r(const time_t *timer, struct tm *result);\n#endif\n"))

(define *c99-builtin-locale-h*
  (string-append
   "#ifndef _ULISP_LOCALE_H\n#define _ULISP_LOCALE_H\n#ifndef NULL\n#define NULL ((void *)0)\n#endif\n"
   "#define LC_CTYPE 0\n#define LC_NUMERIC 1\n#define LC_TIME 2\n#define LC_COLLATE 3\n#define LC_MONETARY 4\n#define LC_MESSAGES 5\n#define LC_ALL 6\n"
   "struct lconv { char *decimal_point; char *thousands_sep; char *grouping; char *int_curr_symbol; char *currency_symbol; char *mon_decimal_point; char *mon_thousands_sep; char *mon_grouping; char *positive_sign; char *negative_sign; char int_frac_digits; char frac_digits; char p_cs_precedes; char p_sep_by_space; char n_cs_precedes; char n_sep_by_space; char p_sign_posn; char n_sign_posn; char int_p_cs_precedes; char int_p_sep_by_space; char int_n_cs_precedes; char int_n_sep_by_space; char int_p_sign_posn; char int_n_sign_posn; };\n"
   "char *setlocale(int category, const char *locale);\nstruct lconv *localeconv(void);\n#endif\n"))

(define *c99-builtin-signal-h*
  (string-append
   "#ifndef _ULISP_SIGNAL_H\n#define _ULISP_SIGNAL_H\n"
   "typedef int sig_atomic_t;\ntypedef void (*__sighandler_t)(int);\n"
   "#define SIGHUP 1\n#define SIGINT 2\n#define SIGQUIT 3\n#define SIGILL 4\n#define SIGABRT 6\n#define SIGFPE 8\n#define SIGKILL 9\n#define SIGSEGV 11\n#define SIGPIPE 13\n#define SIGALRM 14\n#define SIGTERM 15\n"
   "#define SIG_ERR ((void (*)(int))-1)\n#define SIG_DFL ((void (*)(int))0)\n#define SIG_IGN ((void (*)(int))1)\n"
   "#define SA_NOCLDSTOP 0x1\n#define SA_RESETHAND 0x80000000\n#define SA_RESTART 0x10000000\n"
   "typedef struct { unsigned long __val[16]; } sigset_t;\n"
   "struct sigaction { __sighandler_t sa_handler; sigset_t sa_mask; int sa_flags; void (*sa_restorer)(void); };\n"
   "__sighandler_t signal(int sig, __sighandler_t func);\nint raise(int sig);\nint sigemptyset(sigset_t *set);\nint sigfillset(sigset_t *set);\nint sigaddset(sigset_t *set, int signum);\nint sigaction(int sig, const struct sigaction *act, struct sigaction *oldact);\n#endif\n"))

(define *c99-builtin-sys-types-h*
  "#ifndef _ULISP_SYS_TYPES_H\n#define _ULISP_SYS_TYPES_H\n#include <stddef.h>\ntypedef long off_t;\ntypedef long ssize_t;\ntypedef int pid_t;\ntypedef unsigned int uid_t;\ntypedef unsigned int gid_t;\ntypedef unsigned int mode_t;\n#endif\n")

(define *c99-builtin-unistd-h*
  "#ifndef _ULISP_UNISTD_H\n#define _ULISP_UNISTD_H\n#include <stddef.h>\n#include <sys/types.h>\n#define STDIN_FILENO 0\n#define STDOUT_FILENO 1\n#define STDERR_FILENO 2\nint isatty(int fd);\nint close(int fd);\nint unlink(const char *pathname);\nssize_t read(int fd, void *buf, size_t count);\nssize_t write(int fd, const void *buf, size_t count);\nvoid _exit(int status);\n#endif\n")

(define *c99-builtin-sys-wait-h*
  "#ifndef _ULISP_SYS_WAIT_H\n#define _ULISP_SYS_WAIT_H\n#define WTERMSIG(status) ((status) & 0x7f)\n#define WEXITSTATUS(status) (((status) & 0xff00) >> 8)\n#define WSTOPSIG(status) WEXITSTATUS(status)\n#define WIFEXITED(status) (WTERMSIG(status) == 0)\n#define WIFSIGNALED(status) (((signed char)(((status) & 0x7f) + 1) >> 1) > 0)\n#define WIFSTOPPED(status) (((status) & 0xff) == 0x7f)\nint waitpid(int pid, int *wstatus, int options);\n#endif\n")

(define *c99-builtin-dlfcn-h*
  "#ifndef _ULISP_DLFCN_H\n#define _ULISP_DLFCN_H\n#define RTLD_LOCAL 0x0\n#define RTLD_LAZY 0x1\n#define RTLD_NOW 0x2\n#define RTLD_GLOBAL 0x100\nvoid *dlopen(const char *filename, int flags);\nint dlclose(void *handle);\nvoid *dlsym(void *handle, const char *symbol);\nchar *dlerror(void);\n#endif\n")

(define (make-default-cpp-context . maybe-include-paths)
  (let* ((inc-paths (if (pair? maybe-include-paths)
                        (map %cpp-normalize-path (car maybe-include-paths))
                        '()))
         (ctx (make-cpp-context inc-paths
                                (append *cpp-builtin-system-include-paths* '())
                                '() '() '()
                                0 *cpp-max-include-depth*
                                0 *cpp-max-expansion-steps*
                                '() '() (make-vector 128 '()))))
    (for-each
     (lambda (pair) (cpp-register-virtual-file! ctx (car pair) (cdr pair)))
     (list (cons "/__ulisp_builtin__/stdarg.h"    *c99-builtin-stdarg-h*)
           (cons "/__ulisp_builtin__/setjmp.h"    *c99-builtin-setjmp-h*)
           (cons "/__ulisp_builtin__/math.h"      *c99-builtin-math-h*)
           (cons "/__ulisp_builtin__/stddef.h"    *c99-builtin-stddef-h*)
           (cons "/__ulisp_builtin__/stdint.h"    *c99-builtin-stdint-h*)
           (cons "/__ulisp_builtin__/stdbool.h"   *c99-builtin-stdbool-h*)
           (cons "/__ulisp_builtin__/limits.h"    *c99-builtin-limits-h*)
           (cons "/__ulisp_builtin__/float.h"     *c99-builtin-float-h*)
           (cons "/__ulisp_builtin__/assert.h"    *c99-builtin-assert-h*)
           (cons "/__ulisp_builtin__/errno.h"     *c99-builtin-errno-h*)
           (cons "/__ulisp_builtin__/ctype.h"     *c99-builtin-ctype-h*)
           (cons "/__ulisp_builtin__/string.h"    *c99-builtin-string-h*)
           (cons "/__ulisp_builtin__/stdio.h"     *c99-builtin-stdio-h*)
           (cons "/__ulisp_builtin__/stdlib.h"    *c99-builtin-stdlib-h*)
           (cons "/__ulisp_builtin__/time.h"      *c99-builtin-time-h*)
           (cons "/__ulisp_builtin__/locale.h"    *c99-builtin-locale-h*)
           (cons "/__ulisp_builtin__/signal.h"    *c99-builtin-signal-h*)
           (cons "/__ulisp_builtin__/unistd.h"    *c99-builtin-unistd-h*)
           (cons "/__ulisp_builtin__/sys/types.h" *c99-builtin-sys-types-h*)
           (cons "/__ulisp_builtin__/sys/wait.h"  *c99-builtin-sys-wait-h*)
           (cons "/__ulisp_builtin__/dlfcn.h"     *c99-builtin-dlfcn-h*)))
    (%cpp-register-builtin!
     ctx '__FILE__
     (lambda (call-tok)
       (let* ((sp (c-token-span call-tok))
              (f  (span-file sp))
              (lex (string-append "\"" (%cpp-escape-c-string f) "\"")))
         (make-c-token 'string-lit lex f sp
                       (c-token-at-bol? call-tok)
                       (c-token-has-leading-space? call-tok)
                       (cons '__FILE__ (c-token-hide-set call-tok))))))
    (%cpp-register-builtin!
     ctx '__LINE__
     (lambda (call-tok)
       (let* ((sp (c-token-span call-tok))
              (ln (span-start-line sp))
              (lex (number->string ln)))
         (make-c-token 'int-lit lex ln sp
                       (c-token-at-bol? call-tok)
                       (c-token-has-leading-space? call-tok)
                       (cons '__LINE__ (c-token-hide-set call-tok))))))
    (cpp-define-string! ctx "__STDC__" "1")
    (cpp-define-string! ctx "__STDC_HOSTED__" "1")
    (cpp-define-string! ctx "__STDC_VERSION__" "199901L")
    (cpp-define-string! ctx "__linux__" "1")
    (cpp-define-string! ctx "__unix__" "1")
    (cpp-define-string! ctx "__ELF__" "1")
    (cpp-define-string! ctx "__x86_64__" "1")
    (cpp-define-string! ctx "__x86_64" "1")
    (cpp-define-string! ctx "__amd64__" "1")
    (cpp-define-string! ctx "__amd64" "1")
    (cpp-define-string! ctx "__LP64__" "1")
    (cpp-define-string! ctx "__BYTE_ORDER__" "1234")
    (cpp-define-string! ctx "__ORDER_LITTLE_ENDIAN__" "1234")
    (cpp-define-string! ctx "__ORDER_BIG_ENDIAN__" "4321")
    (cpp-define-string! ctx "__SIZEOF_POINTER__" "8")
    (cpp-define-string! ctx "__SIZEOF_LONG__" "8")
    (cpp-define-string! ctx "__SIZEOF_INT__" "4")
    (cpp-define-string! ctx "__SIZEOF_SHORT__" "2")
    (cpp-define-string! ctx "__SIZEOF_SIZE_T__" "8")
    (cpp-define-string! ctx "__SIZEOF_LONG_LONG__" "8")
    (cpp-define-string! ctx "__FLT_EVAL_METHOD__" "0")
    (cpp-define-string! ctx "__LONG_MAX__" "9223372036854775807L")
    (cpp-define-string! ctx "__INT_MAX__" "2147483647")
    (cpp-define-string! ctx "__SHRT_MAX__" "32767")
    (cpp-define-string! ctx "__CHAR_BIT__" "8")
    (cpp-define-string! ctx "__DBL_MANT_DIG__" "53")
    (cpp-define-string! ctx "__FLT_MANT_DIG__" "24")
    (cpp-define-string! ctx "__LDBL_MANT_DIG__" "53")
    ctx))

;;; -----------------------------------------------------------------------
;;; 4. Dave Prosser Blue-Painted (hide-set) Expander (#, ##, __VA_ARGS__)
;;; -----------------------------------------------------------------------

(define (%cpp-ident-token? tok)
  (let ((k (c-token-kind tok)))
    (or (eq? k 'ident) (eq? k 'keyword))))

(define (%hide-set-contains? hs sym)
  (if (memq sym hs) #t #f))

(define (%hide-set-add hs sym)
  (if (memq sym hs) hs (cons sym hs)))

(define (%hide-set-union hs1 hs2)
  (let loop ((xs hs1) (acc hs2))
    (if (null? xs)
        acc
        (if (memq (car xs) acc)
            (loop (cdr xs) acc)
            (loop (cdr xs) (cons (car xs) acc))))))

(define (%hide-set-intersection hs1 hs2)
  (let loop ((xs hs1) (acc '()))
    (if (null? xs)
        (reverse acc)
        (if (memq (car xs) hs2)
            (loop (cdr xs) (cons (car xs) acc))
            (loop (cdr xs) acc)))))

(define (%tokens-add-hide-set toks hs)
  (if (null? hs)
      toks
      (map (lambda (t)
             (c-token-clone-with-hide-set t (%hide-set-union (c-token-hide-set t) hs)))
           toks)))

(define (%cpp-inherit-leading-flags toks call-tok)
  (if (null? toks)
      toks
      (let ((first (car toks)))
        (cons (make-c-token (c-token-kind first)
                            (c-token-lexeme first)
                            (c-token-value first)
                            (c-token-span first)
                            (c-token-at-bol? call-tok)
                            (c-token-has-leading-space? call-tok)
                            (c-token-hide-set first))
              (cdr toks)))))

(define (%cpp-escape-string-for-stringify str)
  (let ((n (string-length str)))
    (let loop ((i 0) (parts '()))
      (if (>= i n)
          (apply string-append (reverse parts))
          (let ((ch (string-ref str i)))
            (cond
              ((char=? ch #\\) (loop (+ i 1) (cons "\\\\" parts)))
              ((char=? ch #\") (loop (+ i 1) (cons "\\\"" parts)))
              (else (loop (+ i 1) (cons (string ch) parts)))))))))

(define (%cpp-stringify-tokens arg-toks call-span call-tok)
  (let* ((raw-str
          (let loop ((xs arg-toks) (first? #t) (parts '()))
            (if (null? xs)
                (apply string-append (reverse parts))
                (let* ((t (car xs))
                       (need-sp? (and (not first?)
                                      (or (c-token-has-leading-space? t)
                                          (c-token-at-bol? t))))
                       (lex (c-token-lexeme t))
                       (parts2 (if need-sp? (cons " " parts) parts)))
                  (loop (cdr xs) #f (cons lex parts2))))))
         (lit-lex (string-append "\"" (%cpp-escape-string-for-stringify raw-str) "\"")))
    (make-c-token 'string-lit lit-lex raw-str call-span
                  (c-token-at-bol? call-tok)
                  (c-token-has-leading-space? call-tok)
                  '())))

(define (%cpp-paste-two-tokens tok1 tok2 call-span)
  (let* ((pasted-str (string-append (c-token-lexeme tok1) (c-token-lexeme tok2)))
         (fname (if (source-span? call-span) (span-file call-span) "<cpp-paste>"))
         (relexed
          (guard (ex (else
                      (%cpp-raise-error "C99-CPP-005" call-span
                                        (string-append "Invalid token pasting result: '" pasted-str "'"))))
            (%cpp-strip-eof (c-tokenize-string pasted-str fname)))))
    (if (not (= (length relexed) 1))
        (%cpp-raise-error "C99-CPP-005" call-span
                          (string-append "Token pasting '##' did not form a single valid token: '" pasted-str "'"))
        (let* ((res (car relexed))
               (hs (%hide-set-union (c-token-hide-set tok1) (c-token-hide-set tok2))))
          (make-c-token (c-token-kind res)
                        (c-token-lexeme res)
                        (c-token-value res)
                        call-span
                        (c-token-at-bol? tok1)
                        (c-token-has-leading-space? tok1)
                        hs)))))

;;; Paste items list where items are either <c-token>, '(%cpp-paste span), or '(%cpp-empty)
(define (%cpp-reduce-pastes items)
  (let loop ((rest items) (out '()))
    (if (null? rest)
        (reverse out)
        (let ((cur (car rest)))
          (if (and (pair? cur) (eq? (car cur) '%cpp-paste))
              (let ((sp (cadr cur)))
                (cond
                  ((null? out)
                   (%cpp-raise-error "C99-CPP-005" sp "'##' cannot appear at beginning of macro expansion"))
                  ((null? (cdr rest))
                   (%cpp-raise-error "C99-CPP-005" sp "'##' cannot appear at end of macro expansion"))
                  (else
                   (let ((lhs (car out))
                         (rhs (cadr rest)))
                     (cond
                       ;; Empty marker handling
                       ((and (pair? lhs) (eq? (car lhs) '%cpp-empty)
                             (pair? rhs) (eq? (car rhs) '%cpp-empty))
                        (loop (cddr rest) out))
                       ((and (pair? lhs) (eq? (car lhs) '%cpp-empty))
                        (loop (cddr rest) (cons rhs (cdr out))))
                       ((and (pair? rhs) (eq? (car rhs) '%cpp-empty))
                        (loop (cddr rest) out))
                       (else
                        (let ((merged (%cpp-paste-two-tokens lhs rhs sp)))
                          (loop (cddr rest) (cons merged (cdr out))))))))))
              (if (and (pair? cur) (eq? (car cur) '%cpp-empty))
                  (let ((next-is-paste? (and (pair? (cdr rest))
                                             (pair? (cadr rest))
                                             (eq? (caadr rest) '%cpp-paste))))
                    (if next-is-paste?
                        (loop (cdr rest) (cons cur out))
                        (loop (cdr rest) out)))
                  (loop (cdr rest) (cons cur out))))))))

(define (%cpp-is-paste-op? tok)
  (c-token-is-punct? tok "##"))

(define (%cpp-subst-body ctx body call-tok raw-env)
  (let ((call-span (c-token-span call-tok))
        (expanded-cache '()))
    (define (get-expanded sym raw-toks)
      (let ((slot (assq sym expanded-cache)))
        (if slot
            (cdr slot)
            (let ((exp (%cpp-expand-stream ctx raw-toks)))
              (set! expanded-cache (cons (cons sym exp) expanded-cache))
              exp))))
    (let loop ((rest body) (prev-paste? #f) (items '()))
      (if (null? rest)
          (%cpp-reduce-pastes (reverse items))
          (let ((tok (car rest))
                (tail (cdr rest)))
            (cond
              ;; Special extension: , ## __VA_ARGS__
              ((and (c-token-is-punct? tok ",")
                    (>= (length rest) 3)
                    (%cpp-is-paste-op? (cadr rest))
                    (%cpp-ident-token? (caddr rest))
                    (eq? (c-token-value (caddr rest)) '__VA_ARGS__)
                    (assq '__VA_ARGS__ raw-env))
               => (lambda (va-slot)
                    (let ((va-raw (cdr va-slot)))
                      (if (null? va-raw)
                          ;; Drop comma and ## __VA_ARGS__
                          (loop (cdddr rest) #f items)
                          ;; Preserve comma and emit expanded __VA_ARGS__
                          (let* ((va-exp (get-expanded '__VA_ARGS__ va-raw))
                                 (orig-tok (c-token-clone-with-span
                                            tok (%cpp-attach-origin (c-token-span tok) call-span)))
                                 (items1 (cons orig-tok items))
                                 (items2 (let append-rev ((xs va-exp) (acc items1))
                                           (if (null? xs)
                                               acc
                                               (append-rev (cdr xs)
                                                           (cons (c-token-clone-with-span
                                                                  (car xs)
                                                                  (%cpp-attach-origin (c-token-span (car xs)) call-span))
                                                                 acc))))))
                            (loop (cdddr rest) #f items2))))))

              ;; Stringification: #param
              ((and (c-token-is-punct? tok "#")
                    (pair? tail)
                    (%cpp-ident-token? (car tail))
                    (assq (c-token-value (car tail)) raw-env))
               => (lambda (p-slot)
                    (let ((s-tok (%cpp-stringify-tokens (cdr p-slot) call-span call-tok)))
                      (loop (cdr tail) #f (cons s-tok items)))))

              ;; Token paste operator ##
              ((%cpp-is-paste-op? tok)
               (if (or (null? items) (null? tail))
                   (%cpp-raise-error "C99-CPP-005" call-span
                                     "Misplaced '##' operator in macro body")
                   (loop tail #t (cons (list '%cpp-paste call-span) items))))

              ;; Parameter reference
              ((and (%cpp-ident-token? tok)
                    (assq (c-token-value tok) raw-env))
               => (lambda (p-slot)
                    (let* ((psym (car p-slot))
                           (raw-arg (cdr p-slot))
                           (next-paste? (and (pair? tail) (%cpp-is-paste-op? (car tail))))
                           (arg-raw (if (or prev-paste? next-paste?)
                                        (%cpp-tokens-attach-origin raw-arg call-span)
                                        (%cpp-tokens-attach-origin (get-expanded psym raw-arg) call-span)))
                           (arg-toks (if prev-paste?
                                         arg-raw
                                         (%cpp-inherit-leading-flags arg-raw tok))))
                      (if (null? arg-toks)
                          (if (or prev-paste? next-paste?)
                              (loop tail #f (cons (list '%cpp-empty) items))
                              (loop tail #f items))
                          (let ((items2
                                 (let append-rev ((xs arg-toks) (acc items))
                                   (if (null? xs)
                                       acc
                                       (append-rev (cdr xs) (cons (car xs) acc))))))
                            (loop tail #f items2))))))

              ;; Normal body token
              (else
               (let ((t-with-origin
                      (c-token-clone-with-span
                       tok (%cpp-attach-origin (c-token-span tok) call-span))))
                 (loop tail #f (cons t-with-origin items))))))))))

(define (%cpp-collect-macro-args ctx tokens-after-lparen macro-name call-span)
  (let loop ((rest tokens-after-lparen) (depth 0) (curr '()) (args '()))
    (cond
      ((null? rest)
       (%cpp-raise-error "C99-CPP-005" call-span
                         (string-append "Unterminated argument list in macro invocation: "
                                        (symbol->string macro-name))))
      (else
       (let ((t (car rest)))
         (cond
           ((eq? (c-token-kind t) 'eof)
            (%cpp-raise-error "C99-CPP-005" call-span
                              (string-append "Reached EOF inside argument list of macro: "
                                             (symbol->string macro-name))))
           ((and (= depth 0) (c-token-is-punct? t ")"))
            (let ((raw-args (if (and (null? args) (null? curr))
                                '()
                                (reverse (cons (reverse curr) args)))))
              (list raw-args t (cdr rest))))
           ((c-token-is-punct? t "(")
            (loop (cdr rest) (+ depth 1) (cons t curr) args))
           ((c-token-is-punct? t ")")
            (loop (cdr rest) (- depth 1) (cons t curr) args))
           ((and (= depth 0) (c-token-is-punct? t ","))
            (loop (cdr rest) depth '() (cons (reverse curr) args)))
           (else
            (loop (cdr rest) depth (cons t curr) args))))))))

(define (%cpp-bind-macro-params params variadic? raw-args macro-name call-span)
  (let* ((param-cnt (length params))
         (norm-args (if (and (null? raw-args)
                             (or (= param-cnt 1) (and (= param-cnt 0) variadic?)))
                        '(())
                        raw-args))
         (arg-cnt (length norm-args)))
    (if variadic?
        (if (< arg-cnt param-cnt)
            (%cpp-raise-error "C99-CPP-005" call-span
                              (string-append "Too few arguments in call to variadic macro "
                                             (symbol->string macro-name)))
            (let loop ((ps params) (as norm-args) (env '()))
              (if (null? ps)
                  ;; Join remaining variadic args with synthetic comma tokens
                  (let ((va-toks
                         (let join-va ((va-list as) (first? #t) (acc '()))
                           (if (null? va-list)
                               (reverse acc)
                               (let* ((acc1 (if first?
                                                acc
                                                (cons (make-c-token 'punct "," "," call-span #f #f '())
                                                      acc)))
                                      (acc2 (let rev-push ((ts (car va-list)) (a acc1))
                                              (if (null? ts) a (rev-push (cdr ts) (cons (car ts) a))))))
                                 (join-va (cdr va-list) #f acc2))))))
                    (cons (cons '__VA_ARGS__ va-toks) env))
                  (loop (cdr ps) (cdr as) (cons (cons (car ps) (car as)) env)))))
        (if (not (= arg-cnt param-cnt))
            (%cpp-raise-error "C99-CPP-005" call-span
                              (string-append "Macro " (symbol->string macro-name)
                                             " expected " (number->string param-cnt)
                                             " arguments, got " (number->string arg-cnt)))
            (let loop ((ps params) (as norm-args) (env '()))
              (if (null? ps)
                  env
                  (loop (cdr ps) (cdr as) (cons (cons (car ps) (car as)) env))))))))

(define (%cpp-inc-expansion-step! ctx call-span)
  (let ((next-step (+ (cpp-ctx-expansion-steps ctx) 1)))
    (if (> next-step (cpp-ctx-max-expansion-steps ctx))
        (%cpp-raise-error "C99-CPP-005" call-span
                          "Maximum preprocessor macro expansion steps exceeded")
        (cpp-ctx-expansion-steps-set! ctx next-step))))

(define (%cpp-expand-stream ctx tokens)
  (let loop ((rest tokens) (out '()))
    (if (null? rest)
        (reverse out)
        (let ((tok (car rest))
              (tail (cdr rest)))
          (if (not (%cpp-ident-token? tok))
              (loop tail (cons tok out))
              (let* ((sym (c-token-value tok))
                     (mac (cpp-lookup-macro ctx sym)))
                (cond
                  ((or (not mac) (%hide-set-contains? (c-token-hide-set tok) sym))
                   (loop tail (cons tok out)))
                  ((cpp-macro-builtin-proc mac)
                   => (lambda (bproc)
                        (%cpp-inc-expansion-step! ctx (c-token-span tok))
                        (loop tail (cons (bproc tok) out))))
                  ((not (cpp-macro-function-like? mac))
                   (%cpp-inc-expansion-step! ctx (c-token-span tok))
                   (let* ((new-hs (%hide-set-add (c-token-hide-set tok) sym))
                          (subst (%cpp-subst-body ctx (cpp-macro-body mac) tok '()))
                          (painted (%cpp-inherit-leading-flags (%tokens-add-hide-set subst new-hs) tok)))
                     (loop (append painted tail) out)))
                  (else
                   ;; Function-like macro: only expand if followed by '(' (skipping non-eof)
                   (if (and (pair? tail) (c-token-is-punct? (car tail) "("))
                       (begin
                         (%cpp-inc-expansion-step! ctx (c-token-span tok))
                         (let* ((call-info (%cpp-collect-macro-args
                                            ctx (cdr tail) sym (c-token-span tok)))
                                (raw-args   (car call-info))
                                (rparen-tok (cadr call-info))
                                (after-call (caddr call-info))
                                (raw-env (%cpp-bind-macro-params
                                          (cpp-macro-params mac)
                                          (cpp-macro-variadic? mac)
                                          raw-args sym (c-token-span tok)))
                                (call-hs (%hide-set-add
                                          (%hide-set-intersection
                                           (c-token-hide-set tok)
                                           (c-token-hide-set rparen-tok))
                                          sym))
                                (subst (%cpp-subst-body ctx (cpp-macro-body mac) tok raw-env))
                                (painted (%cpp-inherit-leading-flags
                                          (%tokens-add-hide-set subst call-hs) tok)))
                           (loop (append painted after-call) out)))
                       (loop tail (cons tok out)))))))))))

;;; -----------------------------------------------------------------------
;;; 5. #if / #elif Constant Integer Expression Evaluator (CTFE #825 / 64-bit #832)
;;; -----------------------------------------------------------------------

(define (%cpp-resolve-defined ctx toks)
  (let loop ((rest toks) (acc '()))
    (if (null? rest)
        (reverse acc)
        (let ((t (car rest)))
          (if (and (%cpp-ident-token? t) (eq? (c-token-value t) 'defined))
              (let ((tail (cdr rest)))
                (cond
                  ((and (pair? tail) (c-token-is-punct? (car tail) "(")
                        (pair? (cdr tail)) (%cpp-ident-token? (cadr tail))
                        (pair? (cddr tail)) (c-token-is-punct? (caddr tail) ")"))
                   (let* ((sym (c-token-value (cadr tail)))
                          (val (if (cpp-lookup-macro ctx sym) 1 0))
                          (itok (make-c-token 'int-lit (number->string val) val
                                              (c-token-span t) #f #t '())))
                     (loop (cdddr tail) (cons itok acc))))
                  ((and (pair? tail) (%cpp-ident-token? (car tail)))
                   (let* ((sym (c-token-value (car tail)))
                          (val (if (cpp-lookup-macro ctx sym) 1 0))
                          (itok (make-c-token 'int-lit (number->string val) val
                                              (c-token-span t) #f #t '())))
                     (loop (cdr tail) (cons itok acc))))
                  (else
                   (%cpp-raise-error "C99-CPP-004" (c-token-span t)
                                     "Invalid syntax for 'defined' operator in #if"))))
              (loop (cdr rest) (cons t acc)))))))

(define (%cpp-replace-unknown-idents-with-zero toks)
  (map (lambda (t)
         (if (%cpp-ident-token? t)
             (make-c-token 'int-lit "0" 0 (c-token-span t)
                           (c-token-at-bol? t) (c-token-has-leading-space? t) '())
             t))
       toks))

(define (%cpp-expr-primary toks eval? dir-span)
  (if (null? toks)
      (%cpp-raise-error "C99-CPP-004" dir-span "Unexpected end of #if constant expression")
      (let ((t (car toks))
            (k (c-token-kind (car toks))))
        (cond
          ((or (eq? k 'int-lit) (eq? k 'char-lit))
           (cons (c-token-value t) (cdr toks)))
          ((c-token-is-punct? t "(")
           (let* ((inner (%cpp-expr-ternary (cdr toks) eval? dir-span))
                  (val (car inner))
                  (rest (cdr inner)))
             (if (and (pair? rest) (c-token-is-punct? (car rest) ")"))
                 (cons val (cdr rest))
                 (%cpp-raise-error "C99-CPP-004" (c-token-span t)
                                   "Missing closing ')' in #if constant expression"))))
          (else
           (%cpp-raise-error "C99-CPP-004" (c-token-span t)
                             (string-append "Unexpected token in #if constant expression: "
                                            (c-token-lexeme t))))))))

(define (%cpp-expr-unary toks eval? dir-span)
  (if (null? toks)
      (%cpp-raise-error "C99-CPP-004" dir-span "Unexpected end of unary expression in #if")
      (let ((t (car toks)))
        (cond
          ((c-token-is-punct? t "+") (%cpp-expr-unary (cdr toks) eval? dir-span))
          ((c-token-is-punct? t "-")
           (let ((r (%cpp-expr-unary (cdr toks) eval? dir-span)))
             (cons (- 0 (car r)) (cdr r))))
          ((c-token-is-punct? t "~")
           (let ((r (%cpp-expr-unary (cdr toks) eval? dir-span)))
             (cons (ctfe-bitwise-not (car r)) (cdr r))))
          ((c-token-is-punct? t "!")
           (let ((r (%cpp-expr-unary (cdr toks) eval? dir-span)))
             (cons (if (= (car r) 0) 1 0) (cdr r))))
          (else
           (%cpp-expr-primary toks eval? dir-span))))))

(define (%cpp-expr-mul toks eval? dir-span)
  (let loop ((res (%cpp-expr-unary toks eval? dir-span)))
    (let ((lhs (car res))
          (rest (cdr res)))
      (cond
        ((and (pair? rest) (c-token-is-punct? (car rest) "*"))
         (let ((rhs (%cpp-expr-unary (cdr rest) eval? dir-span)))
           (loop (cons (if eval? (* lhs (car rhs)) 0) (cdr rhs)))))
        ((and (pair? rest)
              (or (c-token-is-punct? (car rest) "/")
                  (c-token-is-punct? (car rest) "%")))
         (let* ((op-tok (car rest))
                (is-div? (c-token-is-punct? op-tok "/"))
                (rhs (%cpp-expr-unary (cdr rest) eval? dir-span))
                (rval (car rhs)))
           (if eval?
               (if (= rval 0)
                   (%cpp-raise-error "C99-CPP-004" (c-token-span op-tok)
                                     "Division or modulo by zero in #if constant expression")
                   (loop (cons (if is-div? (quotient lhs rval) (remainder lhs rval))
                               (cdr rhs))))
               (loop (cons 0 (cdr rhs))))))
        (else res)))))

(define (%cpp-expr-add toks eval? dir-span)
  (let loop ((res (%cpp-expr-mul toks eval? dir-span)))
    (let ((lhs (car res))
          (rest (cdr res)))
      (cond
        ((and (pair? rest) (c-token-is-punct? (car rest) "+"))
         (let ((rhs (%cpp-expr-mul (cdr rest) eval? dir-span)))
           (loop (cons (if eval? (+ lhs (car rhs)) 0) (cdr rhs)))))
        ((and (pair? rest) (c-token-is-punct? (car rest) "-"))
         (let ((rhs (%cpp-expr-mul (cdr rest) eval? dir-span)))
           (loop (cons (if eval? (- lhs (car rhs)) 0) (cdr rhs)))))
        (else res)))))

(define (%cpp-expr-shift toks eval? dir-span)
  (let loop ((res (%cpp-expr-add toks eval? dir-span)))
    (let ((lhs (car res))
          (rest (cdr res)))
      (cond
        ((and (pair? rest) (c-token-is-punct? (car rest) "<<"))
         (let ((rhs (%cpp-expr-add (cdr rest) eval? dir-span)))
           (loop (cons (if eval? (ctfe-arithmetic-shift lhs (car rhs)) 0) (cdr rhs)))))
        ((and (pair? rest) (c-token-is-punct? (car rest) ">>"))
         (let ((rhs (%cpp-expr-add (cdr rest) eval? dir-span)))
           (loop (cons (if eval? (ctfe-arithmetic-shift lhs (- 0 (car rhs))) 0) (cdr rhs)))))
        (else res)))))

(define (%cpp-expr-rel toks eval? dir-span)
  (let loop ((res (%cpp-expr-shift toks eval? dir-span)))
    (let ((lhs (car res))
          (rest (cdr res)))
      (cond
        ((and (pair? rest) (c-token-is-punct? (car rest) "<"))
         (let ((rhs (%cpp-expr-shift (cdr rest) eval? dir-span)))
           (loop (cons (if (and eval? (< lhs (car rhs))) 1 0) (cdr rhs)))))
        ((and (pair? rest) (c-token-is-punct? (car rest) "<="))
         (let ((rhs (%cpp-expr-shift (cdr rest) eval? dir-span)))
           (loop (cons (if (and eval? (<= lhs (car rhs))) 1 0) (cdr rhs)))))
        ((and (pair? rest) (c-token-is-punct? (car rest) ">"))
         (let ((rhs (%cpp-expr-shift (cdr rest) eval? dir-span)))
           (loop (cons (if (and eval? (> lhs (car rhs))) 1 0) (cdr rhs)))))
        ((and (pair? rest) (c-token-is-punct? (car rest) ">="))
         (let ((rhs (%cpp-expr-shift (cdr rest) eval? dir-span)))
           (loop (cons (if (and eval? (>= lhs (car rhs))) 1 0) (cdr rhs)))))
        (else res)))))

(define (%cpp-expr-eq toks eval? dir-span)
  (let loop ((res (%cpp-expr-rel toks eval? dir-span)))
    (let ((lhs (car res))
          (rest (cdr res)))
      (cond
        ((and (pair? rest) (c-token-is-punct? (car rest) "=="))
         (let ((rhs (%cpp-expr-rel (cdr rest) eval? dir-span)))
           (loop (cons (if (and eval? (= lhs (car rhs))) 1 0) (cdr rhs)))))
        ((and (pair? rest) (c-token-is-punct? (car rest) "!="))
         (let ((rhs (%cpp-expr-rel (cdr rest) eval? dir-span)))
           (loop (cons (if (and eval? (not (= lhs (car rhs)))) 1 0) (cdr rhs)))))
        (else res)))))

(define (%cpp-expr-bitand toks eval? dir-span)
  (let loop ((res (%cpp-expr-eq toks eval? dir-span)))
    (let ((lhs (car res))
          (rest (cdr res)))
      (if (and (pair? rest) (c-token-is-punct? (car rest) "&"))
          (let ((rhs (%cpp-expr-eq (cdr rest) eval? dir-span)))
            (loop (cons (if eval? (ctfe-bitwise-and lhs (car rhs)) 0) (cdr rhs))))
          res))))

(define (%cpp-expr-bitxor toks eval? dir-span)
  (let loop ((res (%cpp-expr-bitand toks eval? dir-span)))
    (let ((lhs (car res))
          (rest (cdr res)))
      (if (and (pair? rest) (c-token-is-punct? (car rest) "^"))
          (let ((rhs (%cpp-expr-bitand (cdr rest) eval? dir-span)))
            (loop (cons (if eval? (ctfe-bitwise-xor lhs (car rhs)) 0) (cdr rhs))))
          res))))

(define (%cpp-expr-bitior toks eval? dir-span)
  (let loop ((res (%cpp-expr-bitxor toks eval? dir-span)))
    (let ((lhs (car res))
          (rest (cdr res)))
      (if (and (pair? rest) (c-token-is-punct? (car rest) "|"))
          (let ((rhs (%cpp-expr-bitxor (cdr rest) eval? dir-span)))
            (loop (cons (if eval? (ctfe-bitwise-ior lhs (car rhs)) 0) (cdr rhs))))
          res))))

(define (%cpp-expr-land toks eval? dir-span)
  (let loop ((res (%cpp-expr-bitior toks eval? dir-span)))
    (let ((lhs (car res))
          (rest (cdr res)))
      (if (and (pair? rest) (c-token-is-punct? (car rest) "&&"))
          (let* ((rhs-eval? (and eval? (not (= lhs 0))))
                 (rhs (%cpp-expr-bitior (cdr rest) rhs-eval? dir-span))
                 (val (if (and rhs-eval? (not (= (car rhs) 0))) 1 0)))
            (loop (cons val (cdr rhs))))
          res))))

(define (%cpp-expr-lor toks eval? dir-span)
  (let loop ((res (%cpp-expr-land toks eval? dir-span)))
    (let ((lhs (car res))
          (rest (cdr res)))
      (if (and (pair? rest) (c-token-is-punct? (car rest) "||"))
          (let* ((lhs-true? (and eval? (not (= lhs 0))))
                 (rhs-eval? (and eval? (not lhs-true?)))
                 (rhs (%cpp-expr-land (cdr rest) rhs-eval? dir-span))
                 (val (if (or lhs-true? (and rhs-eval? (not (= (car rhs) 0)))) 1 0)))
            (loop (cons val (cdr rhs))))
          res))))

(define (%cpp-expr-ternary toks eval? dir-span)
  (let* ((cond-res (%cpp-expr-lor toks eval? dir-span))
         (cond-val (car cond-res))
         (rest (cdr cond-res)))
    (if (and (pair? rest) (c-token-is-punct? (car rest) "?"))
        (let* ((then-eval? (and eval? (not (= cond-val 0))))
               (else-eval? (and eval? (= cond-val 0)))
               (then-res (%cpp-expr-ternary (cdr rest) then-eval? dir-span))
               (after-then (cdr then-res)))
          (if (not (and (pair? after-then) (c-token-is-punct? (car after-then) ":")))
              (%cpp-raise-error "C99-CPP-004" dir-span
                                "Expected ':' in ternary '?:' expression inside #if")
              (let* ((else-res (%cpp-expr-ternary (cdr after-then) else-eval? dir-span))
                     (final-val (if (= cond-val 0) (car else-res) (car then-res))))
                (cons final-val (cdr else-res)))))
        cond-res)))

(define (%cpp-eval-const-expr ctx raw-toks dir-span)
  (let* ((with-def1 (%cpp-resolve-defined ctx raw-toks))
         (expanded (%cpp-expand-stream ctx with-def1))
         (with-def2 (%cpp-resolve-defined ctx expanded))
         (ready (%cpp-replace-unknown-idents-with-zero with-def2)))
    (if (null? ready)
        (%cpp-raise-error "C99-CPP-004" dir-span "Empty constant expression in #if / #elif")
        (let* ((res (%cpp-expr-ternary ready #t dir-span))
               (val (car res))
               (leftover (cdr res)))
          (if (pair? leftover)
              (%cpp-raise-error "C99-CPP-004" (c-token-span (car leftover))
                                (string-append "Unexpected trailing token '"
                                               (c-token-lexeme (car leftover))
                                               "' in #if expression"))
              val)))))

;;; -----------------------------------------------------------------------
;;; 6. Logical Line Splitting, Include Guard Detection & Directive Processor
;;; -----------------------------------------------------------------------

(define (%cpp-split-logical-lines tokens)
  (let ((body (%cpp-strip-eof tokens)))
    (let loop ((rest body) (curr '()) (lines '()))
      (if (null? rest)
          (reverse (if (null? curr) lines (cons (reverse curr) lines)))
          (let ((t (car rest)))
            (if (and (c-token-at-bol? t) (pair? curr))
                (loop (cdr rest) (list t) (cons (reverse curr) lines))
                (loop (cdr rest) (cons t curr) lines)))))))

(define (%cpp-detect-include-guard lines)
  (if (< (length lines) 3)
      #f
      (let* ((l0 (car lines))
             (l1 (cadr lines))
             (last-line (list-ref lines (- (length lines) 1))))
        (if (and (= (length l0) 3)
                 (c-token-is-punct? (car l0) "#")
                 (%cpp-ident-token? (cadr l0))
                 (eq? (c-token-value (cadr l0)) 'ifndef)
                 (%cpp-ident-token? (caddr l0))
                 (>= (length l1) 3)
                 (c-token-is-punct? (car l1) "#")
                 (%cpp-ident-token? (cadr l1))
                 (eq? (c-token-value (cadr l1)) 'define)
                 (%cpp-ident-token? (caddr l1))
                 (eq? (c-token-value (caddr l0)) (c-token-value (caddr l1)))
                 (= (length last-line) 2)
                 (c-token-is-punct? (car last-line) "#")
                 (%cpp-ident-token? (cadr last-line))
                 (eq? (c-token-value (cadr last-line)) 'endif))
            ;; Verify conditional depth stays >= 1 across middle lines
            (let ((middle-ok?
                   (let check ((rest (cdr lines)) (depth 1))
                     (if (null? (cdr rest))
                         (= depth 1)
                         (let ((ln (car rest)))
                           (if (and (>= (length ln) 2) (c-token-is-punct? (car ln) "#")
                                    (%cpp-ident-token? (cadr ln)))
                               (let ((d (c-token-value (cadr ln))))
                                 (cond
                                   ((memq d '(if ifdef ifndef))
                                    (check (cdr rest) (+ depth 1)))
                                   ((eq? d 'endif)
                                    (if (<= (- depth 1) 0)
                                        #f
                                        (check (cdr rest) (- depth 1))))
                                   (else (check (cdr rest) depth))))
                               (check (cdr rest) depth)))))))
              (if middle-ok? (c-token-value (caddr l0)) #f))
            #f))))

(define (%cpp-resolve-include-file ctx target-name is-system? current-file call-span)
  (let* ((candidates
          (if is-system?
              (append (cpp-ctx-include-paths ctx)
                      (cpp-ctx-system-include-paths ctx))
              (cons (%cpp-path-dirname current-file)
                    (append (cpp-ctx-include-paths ctx)
                            (cpp-ctx-system-include-paths ctx)))))
         (found
          (let loop ((dirs candidates))
            (if (null? dirs)
                #f
                (let ((cand (%cpp-path-join (car dirs) target-name)))
                  (cond
                    ((%cpp-lookup-virtual-file ctx cand)
                     => (lambda (vtxt) (cons cand vtxt)))
                    ((file-exists? cand)
                     (cpp-record-included-file! ctx cand)
                     (cons cand (read-all-file-text cand)))
                    (else (loop (cdr dirs)))))))))
    (or found
        (let ((direct-v (%cpp-lookup-virtual-file ctx target-name)))
          (cond
            (direct-v (cons (%cpp-normalize-path target-name) direct-v))
            ((file-exists? target-name)
             (let ((np (%cpp-normalize-path target-name)))
               (cpp-record-included-file! ctx np)
               (cons np (read-all-file-text np))))
            (else
             (%cpp-raise-error "C99-CPP-001" call-span
                               (string-append "Include file not found: '" target-name "'"))))))))

(define (%cpp-parse-include-target ctx rest-toks call-span)
  (define (extract-target toks)
    (cond
      ((null? toks) #f)
      ((eq? (c-token-kind (car toks)) 'string-lit)
       (cons (c-token-value (car toks)) #f))
      ((c-token-is-punct? (car toks) "<")
       (let loop ((xs (cdr toks)) (parts '()))
         (cond
           ((null? xs) #f)
           ((c-token-is-punct? (car xs) ">")
            (cons (apply string-append (reverse parts)) #t))
           (else
            (loop (cdr xs) (cons (c-token-lexeme (car xs)) parts))))))
      (else #f)))
  (or (extract-target rest-toks)
      (extract-target (%cpp-expand-stream ctx rest-toks))
      (%cpp-raise-error "C99-CPP-001" call-span
                        "Invalid #include filename specification")))

(define (%cpp-parse-define! ctx args dir-span)
  (if (or (null? args) (not (%cpp-ident-token? (car args))))
      (%cpp-raise-error "C99-CPP-003" dir-span "#define requires a macro identifier name")
      (let* ((name-tok (car args))
             (name-sym (c-token-value name-tok))
             (after-name (cdr args)))
        (if (and (pair? after-name)
                 (c-token-is-punct? (car after-name) "(")
                 (not (c-token-has-leading-space? (car after-name))))
            ;; Function-like macro definition
            (let loop ((ps (cdr after-name)) (params '()) (expect-param? #t))
              (cond
                ((null? ps)
                 (%cpp-raise-error "C99-CPP-003" dir-span
                                   "Unterminated parameter list in #define"))
                ((c-token-is-punct? (car ps) ")")
                 (if (and (pair? params) expect-param?)
                     (%cpp-raise-error "C99-CPP-003" (c-token-span (car ps))
                                       "Trailing comma in macro parameter list")
                     (cpp-define-function! ctx name-sym (reverse params) #f (cdr ps) dir-span)))
                ((and expect-param? (c-token-is-punct? (car ps) "..."))
                 (if (and (pair? (cdr ps)) (c-token-is-punct? (cadr ps) ")"))
                     (cpp-define-function! ctx name-sym (reverse params) #t (cddr ps) dir-span)
                     (%cpp-raise-error "C99-CPP-003" (c-token-span (car ps))
                                       "'...' must be the last parameter in #define")))
                ((and expect-param? (%cpp-ident-token? (car ps)))
                 (let ((pname (c-token-value (car ps)))
                       (after-p (cdr ps)))
                   (cond
                     ((null? after-p)
                      (%cpp-raise-error "C99-CPP-003" dir-span
                                        "Unterminated parameter list in #define"))
                     ((c-token-is-punct? (car after-p) ")")
                      (cpp-define-function! ctx name-sym (reverse (cons pname params)) #f (cdr after-p) dir-span))
                     ((c-token-is-punct? (car after-p) ",")
                      (loop (cdr after-p) (cons pname params) #t))
                     (else
                      (%cpp-raise-error "C99-CPP-003" (c-token-span (car after-p))
                                        "Expected ',' or ')' in macro parameter list")))))
                (else
                 (%cpp-raise-error "C99-CPP-003" (c-token-span (car ps))
                                   "Invalid token in #define parameter list"))))
            ;; Object-like macro definition
            (cpp-define-object! ctx name-sym after-name dir-span)))))

(define (%cpp-active? cond-stack)
  (or (null? cond-stack)
      (caddr (car cond-stack))))

(define (%cpp-process-lines ctx lines current-file)
  (let* ((norm-cur (%cpp-normalize-path current-file))
         (flush-normal
          (lambda (pending out)
            (if (null? pending)
                out
                (let ((exp (%cpp-expand-stream ctx (reverse pending))))
                  (let push-rev ((xs exp) (acc out))
                    (if (null? xs) acc (push-rev (cdr xs) (cons (car xs) acc)))))))))
    (let loop ((rest-lines lines) (cond-stack '()) (pending '()) (out '()))
      (if (null? rest-lines)
          (if (pair? cond-stack)
              (%cpp-raise-error "C99-CPP-003" (list-ref (car cond-stack) 4)
                                "Unterminated #if / #ifdef / #ifndef directive before EOF")
              (reverse (flush-normal pending out)))
          (let* ((ln (car rest-lines))
                 (next-lines (cdr rest-lines))
                 (active? (%cpp-active? cond-stack)))
            (if (and (pair? ln)
                     (c-token-at-bol? (car ln))
                     (c-token-is-punct? (car ln) "#"))
                ;; Preprocessing directive line
                (let* ((out1 (flush-normal pending out))
                       (hash-tok (car ln))
                       (after-hash (cdr ln)))
                  (if (null? after-hash)
                      ;; Null directive '#'
                      (loop next-lines cond-stack '() out1)
                      (let* ((dir-tok (car after-hash))
                             (dir-args (cdr after-hash))
                             (dir-sp (c-token-span hash-tok))
                             (dir-sym (if (%cpp-ident-token? dir-tok)
                                          (c-token-value dir-tok)
                                          #f)))
                        (cond
                          ;; Conditional directives run in both active & inactive modes
                          ((memq dir-sym '(if ifdef ifndef))
                           (if (not active?)
                               (loop next-lines (cons (list #f #t #f #f dir-sp) cond-stack) '() out1)
                               (let ((taken?
                                      (case dir-sym
                                        ((ifdef)
                                         (if (and (= (length dir-args) 1) (%cpp-ident-token? (car dir-args)))
                                             (if (cpp-lookup-macro ctx (c-token-value (car dir-args))) #t #f)
                                             (%cpp-raise-error "C99-CPP-003" dir-sp "#ifdef expects a single identifier")))
                                        ((ifndef)
                                         (if (and (= (length dir-args) 1) (%cpp-ident-token? (car dir-args)))
                                             (if (cpp-lookup-macro ctx (c-token-value (car dir-args))) #f #t)
                                             (%cpp-raise-error "C99-CPP-003" dir-sp "#ifndef expects a single identifier")))
                                        ((if)
                                         (not (= (%cpp-eval-const-expr ctx dir-args dir-sp) 0))))))
                                 (loop next-lines (cons (list #t taken? taken? #f dir-sp) cond-stack) '() out1))))

                          ((eq? dir-sym 'elif)
                           (if (null? cond-stack)
                               (%cpp-raise-error "C99-CPP-003" dir-sp "Unexpected #elif without matching #if")
                               (let* ((frame (car cond-stack))
                                      (parent-act? (list-ref frame 0))
                                      (any-taken?  (list-ref frame 1))
                                      (saw-else?   (list-ref frame 3)))
                                 (if saw-else?
                                     (%cpp-raise-error "C99-CPP-003" dir-sp "#elif directive after #else")
                                     (if (or (not parent-act?) any-taken?)
                                         (loop next-lines (cons (list parent-act? any-taken? #f #f dir-sp)
                                                                (cdr cond-stack)) '() out1)
                                         (let ((taken? (not (= (%cpp-eval-const-expr ctx dir-args dir-sp) 0))))
                                           (loop next-lines (cons (list #t taken? taken? #f dir-sp)
                                                                  (cdr cond-stack)) '() out1)))))))

                          ((eq? dir-sym 'else)
                           (if (null? cond-stack)
                               (%cpp-raise-error "C99-CPP-003" dir-sp "Unexpected #else without matching #if")
                               (let* ((frame (car cond-stack))
                                      (parent-act? (list-ref frame 0))
                                      (any-taken?  (list-ref frame 1))
                                      (saw-else?   (list-ref frame 3)))
                                 (if saw-else?
                                     (%cpp-raise-error "C99-CPP-003" dir-sp "Duplicate #else directive")
                                     (let ((cur-act? (and parent-act? (not any-taken?))))
                                       (loop next-lines (cons (list parent-act? #t cur-act? #t dir-sp)
                                                              (cdr cond-stack)) '() out1))))))

                          ((eq? dir-sym 'endif)
                           (if (null? cond-stack)
                               (%cpp-raise-error "C99-CPP-003" dir-sp "Unexpected #endif without matching #if")
                               (loop next-lines (cdr cond-stack) '() out1)))

                          ;; All other directives are skipped if inactive
                          ((not active?)
                           (loop next-lines cond-stack '() out1))

                          ((eq? dir-sym 'define)
                           (%cpp-parse-define! ctx dir-args dir-sp)
                           (loop next-lines cond-stack '() out1))

                          ((eq? dir-sym 'undef)
                           (if (and (= (length dir-args) 1) (%cpp-ident-token? (car dir-args)))
                               (begin
                                 (cpp-undef! ctx (c-token-value (car dir-args)))
                                 (loop next-lines cond-stack '() out1))
                               (%cpp-raise-error "C99-CPP-003" dir-sp "#undef requires an identifier")))

                          ((eq? dir-sym 'error)
                           (let ((msg (apply string-append
                                             (map (lambda (t) (string-append (c-token-lexeme t) " ")) dir-args))))
                             (%cpp-raise-error "C99-CPP-002" dir-sp
                                               (string-append "#error " msg))))

                          ((eq? dir-sym 'pragma)
                           (if (and (pair? dir-args) (%cpp-ident-token? (car dir-args))
                                    (eq? (c-token-value (car dir-args)) 'once))
                               (if (not (member norm-cur (cpp-ctx-pragma-once-files ctx)))
                                   (cpp-ctx-pragma-once-files-set!
                                    ctx (cons norm-cur (cpp-ctx-pragma-once-files ctx)))))
                           (loop next-lines cond-stack '() out1))

                          ((eq? dir-sym 'line)
                           (loop next-lines cond-stack '() out1))

                          ((eq? dir-sym 'include)
                           (if (>= (cpp-ctx-include-depth ctx) (cpp-ctx-max-include-depth ctx))
                               (%cpp-raise-error "C99-CPP-001" dir-sp
                                                 "Maximum #include nesting depth exceeded")
                               (let* ((tgt (%cpp-parse-include-target ctx dir-args dir-sp))
                                      (tgt-name (car tgt))
                                      (is-sys?  (cdr tgt))
                                      (resolved (%cpp-resolve-include-file
                                                 ctx tgt-name is-sys? norm-cur dir-sp))
                                      (inc-path (car resolved))
                                      (inc-text (cdr resolved))
                                      (guard-entry (assoc inc-path (cpp-ctx-include-guard-cache ctx))))
                                 (cond
                                   ((member inc-path (cpp-ctx-pragma-once-files ctx))
                                    (%cpp-inc-skip-count!)
                                    (loop next-lines cond-stack '() out1))
                                   ((and guard-entry (cpp-lookup-macro ctx (cdr guard-entry)))
                                    (%cpp-inc-skip-count!)
                                    (loop next-lines cond-stack '() out1))
                                   (else
                                    (let* ((inc-toks (c-tokenize-string inc-text inc-path))
                                           (inc-lines (%cpp-split-logical-lines inc-toks))
                                           (detected-guard (%cpp-detect-include-guard inc-lines)))
                                      (if detected-guard
                                          (cpp-ctx-include-guard-cache-set!
                                           ctx (cons (cons inc-path detected-guard)
                                                     (cpp-ctx-include-guard-cache ctx))))
                                      (cpp-ctx-include-depth-set! ctx (+ (cpp-ctx-include-depth ctx) 1))
                                      (let ((inc-out
                                             (guard (ex (else
                                                         (cpp-ctx-include-depth-set!
                                                          ctx (- (cpp-ctx-include-depth ctx) 1))
                                                         (raise ex)))
                                               (let ((r (%cpp-process-lines ctx inc-lines inc-path)))
                                                 (cpp-ctx-include-depth-set!
                                                  ctx (- (cpp-ctx-include-depth ctx) 1))
                                                 r))))
                                        (let ((out2 (let push-rev ((xs inc-out) (acc out1))
                                                      (if (null? xs) acc (push-rev (cdr xs) (cons (car xs) acc))))))
                                          (loop next-lines cond-stack '() out2)))))))))

                          (else
                           (%cpp-raise-error "C99-CPP-003" dir-sp
                                             (string-append "Unknown preprocessor directive #"
                                                            (c-token-lexeme dir-tok))))))))
                ;; Non-directive line: buffer onto pending when active
                (if active?
                    (let ((pending2 (let push-rev ((xs ln) (acc pending))
                                      (if (null? xs) acc (push-rev (cdr xs) (cons (car xs) acc))))))
                      (loop next-lines cond-stack pending2 out))
                    (loop next-lines cond-stack pending out))))))))

;;; -----------------------------------------------------------------------
;;; 7. Public Top-Level Preprocessor Entry Points
;;; -----------------------------------------------------------------------

(define (%cpp-last-or-synth-eof tokens fname)
  (let loop ((xs tokens) (last-eof #f))
    (if (null? xs)
        (or last-eof
            (let ((sp (make-source-span fname 1 1 1 1 #f (next-source-span-id!))))
              (make-c-token 'eof "" 'eof sp #t #f '())))
        (loop (cdr xs)
              (if (eq? (c-token-kind (car xs)) 'eof) (car xs) last-eof)))))

(define (cpp-preprocess-tokens ctx tokens . maybe-filename)
  (let* ((fname (if (pair? maybe-filename)
                    (car maybe-filename)
                    (if (pair? tokens)
                        (span-file (c-token-span (car tokens)))
                        "<c99-input>")))
         (lines (%cpp-split-logical-lines tokens))
         (expanded (%cpp-process-lines ctx lines fname))
         (eof-tok (%cpp-last-or-synth-eof tokens fname)))
    (append expanded (list eof-tok))))

(define (cpp-preprocess-string src-text . rest)
  (let* ((fname (if (pair? rest) (car rest) "<c99-input>"))
         (ctx   (if (and (pair? rest) (pair? (cdr rest)))
                    (cadr rest)
                    (make-default-cpp-context)))
         (raw-toks (c-tokenize-string src-text fname))
         (pp-toks  (cpp-preprocess-tokens ctx raw-toks fname)))
    (c-concat-adjacent-string-tokens pp-toks)))

(define (cpp-preprocess-to-string src-text . rest)
  (let ((toks (apply cpp-preprocess-string (cons src-text rest))))
    (c-tokens->source-string toks)))

(define (cpp-preprocess-file filepath . maybe-ctx)
  (let* ((ctx (if (pair? maybe-ctx) (car maybe-ctx) (make-default-cpp-context)))
         (norm (%cpp-normalize-path filepath))
         (src (read-all-file-text norm)))
    (if (file-exists? norm)
        (cpp-record-included-file! ctx norm))
    (cpp-preprocess-string src norm ctx)))

;;; -----------------------------------------------------------------------
;;; 8. PCH Snapshot Serialization / Deserialization Codec (<cpp-context>)
;;; -----------------------------------------------------------------------

(define *cpp-default-builtin-macros-cache* (cons #f '()))

(define (%cpp-default-builtin-macros)
  (or (car *cpp-default-builtin-macros-cache*)
      (let* ((fresh (make-default-cpp-context))
             (builtins
              (let loop ((ms (cpp-ctx-macros fresh)) (acc '()))
                (cond
                  ((null? ms) (reverse acc))
                  ((cpp-macro-builtin-proc (cdar ms))
                   (loop (cdr ms) (cons (car ms) acc)))
                  (else (loop (cdr ms) acc))))))
        (set-car! *cpp-default-builtin-macros-cache* builtins)
        builtins)))

(define (c-token->sexpr tok)
  (list 'c-tok
        (c-token-kind tok)
        (c-token-lexeme tok)
        (c-token-value tok)
        (c-token-span tok)
        (c-token-at-bol? tok)
        (c-token-has-leading-space? tok)
        (map (lambda (s) s) (c-token-hide-set tok))))

(define (sexpr->c-token sx)
  (if (or (not (pair? sx)) (not (eq? (car sx) 'c-tok)))
      (error "Invalid serialized <c-token> in PCH" sx))
  (make-c-token (list-ref sx 1)
                (list-ref sx 2)
                (list-ref sx 3)
                (list-ref sx 4)
                (list-ref sx 5)
                (list-ref sx 6)
                (map (lambda (s) s) (list-ref sx 7))))

(define (cpp-macro->sexpr name mac)
  (if (cpp-macro-builtin-proc mac)
      (list 'cpp-builtin name)
      (list 'cpp-user
            name
            (cpp-macro-function-like? mac)
            (map (lambda (p) p) (cpp-macro-params mac))
            (cpp-macro-variadic? mac)
            (map c-token->sexpr (cpp-macro-body mac))
            (cpp-macro-def-span mac))))

(define (sexpr->cpp-macro sx)
  (cond
    ((and (pair? sx) (eq? (car sx) 'cpp-builtin))
     (let* ((name (cadr sx))
            (slot (assq name (%cpp-default-builtin-macros))))
       (if slot
           (cons name (cdr slot))
           (error "Unknown builtin CPP macro in PCH" name))))
    ((and (pair? sx) (eq? (car sx) 'cpp-user))
     (let ((name (list-ref sx 1))
           (fn-like? (list-ref sx 2))
           (params (map (lambda (p) p) (list-ref sx 3)))
           (variadic? (list-ref sx 4))
           (body (map sexpr->c-token (list-ref sx 5)))
           (def-span (list-ref sx 6)))
       (cons name (make-cpp-macro name fn-like? params variadic? body def-span #f))))
    (else
     (error "Invalid serialized <cpp-macro> in PCH" sx))))

(define (cpp-context->pch-sexpr ctx . maybe-root-header)
  (let* ((root-raw (and (pair? maybe-root-header) (car maybe-root-header)))
         (root-norm (and (string? root-raw) (> (string-length root-raw) 0)
                         (%cpp-normalize-path root-raw)))
         (po-files (let ((cur (cpp-ctx-pragma-once-files ctx)))
                     (if (and root-norm (not (member root-norm cur)))
                         (cons root-norm (map (lambda (s) s) cur))
                         (map (lambda (s) s) cur))))
         (inc-files (let ((cur (cpp-ctx-included-files ctx)))
                      (if (and root-norm (file-exists? root-norm) (not (member root-norm cur)))
                          (cons root-norm (map (lambda (s) s) cur))
                          (map (lambda (s) s) cur)))))
    (list 'cpp-pch-v1
          (cons 'macros
                (map (lambda (e) (cpp-macro->sexpr (car e) (cdr e)))
                     (cpp-ctx-macros ctx)))
          (cons 'pragma-once-files po-files)
          (cons 'include-guard-cache
                (map (lambda (e) (cons (car e) (cdr e)))
                     (cpp-ctx-include-guard-cache ctx)))
          (cons 'included-files inc-files))))

(define (cpp-restore-context-from-pch! ctx pch-sx)
  (if (or (not (pair? pch-sx)) (not (eq? (car pch-sx) 'cpp-pch-v1)))
      (error "Invalid serialized <cpp-context> PCH snapshot" pch-sx))
  (let* ((alist (cdr pch-sx))
         (macs-raw (cdr (assq 'macros alist)))
         (po-raw (cdr (assq 'pragma-once-files alist)))
         (guards-raw (cdr (assq 'include-guard-cache alist)))
         (inc-raw (cdr (assq 'included-files alist))))
    (cpp-ctx-macros-set! ctx (map sexpr->cpp-macro macs-raw))
    (%cpp-rebuild-macro-buckets! ctx)
    (cpp-ctx-pragma-once-files-set! ctx (map (lambda (s) s) po-raw))
    (cpp-ctx-include-guard-cache-set! ctx (map (lambda (e) (cons (car e) (cdr e))) guards-raw))
    (cpp-ctx-included-files-set! ctx (map (lambda (s) s) inc-raw))
    (cpp-ctx-include-depth-set! ctx 0)
    (cpp-ctx-expansion-steps-set! ctx 0)
    ctx))
