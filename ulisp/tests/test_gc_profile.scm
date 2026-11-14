;;; =======================================================================
;;; ULisp Test Suite: Generational GC Execution Profiles (Issue #567)
;;; =======================================================================

(test-begin "gc-profile")

(define-syntax assert-true
  (syntax-rules ()
    ((assert-true val msg)
     (test-assert msg val))))

(define-syntax assert-equal
  (syntax-rules ()
    ((assert-equal actual expected msg)
     (test-equal msg expected actual))))

(flush-output-port)

;; 1. Check current runtime profile (detected from boot environment or default)
(let ((cur-prof (gc-current-profile)))
  (cond
    ((eq? cur-prof 'compiler)
     (write-string "Detected Profile: COMPILER (via ULISP_GC_PROFILE)\n")
     (assert-equal (gc-profile-id) 1 "Compiler profile ID is 1")
     (let ((expected-arena (if (equal? (get-environment-variable "ULISP_COMPILER_ARENA_MB") "1024")
                               1073741824
                               2147483648)))
       (assert-equal (gc-nursery-size) expected-arena "Compiler profile nursery size matches arena setting")
       (assert-equal (gc-mature-size) expected-arena "Compiler profile mature size matches arena setting"))
     (assert-equal (gc-max-size) 8589934592 "Compiler profile max mature size is 8GB"))
    ((eq? cur-prof 'server)
     (write-string "Detected Profile: SERVER (via ULISP_GC_PROFILE)\n")
     (assert-equal (gc-profile-id) 2 "Server profile ID is 2")
     (assert-equal (gc-nursery-size) 16777216 "Server profile nursery size is 16MB")
     (assert-equal (gc-mature-size) 268435456 "Server profile mature size is 256MB")
     (assert-equal (gc-max-size) 4294967296 "Server profile max mature size is 4GB"))
    (else
     (write-string "Detected Profile: STANDARD (Default)\n")
     (assert-equal (gc-profile-id) 0 "Standard profile ID is 0")
     (assert-equal (gc-nursery-size) 4194304 "Standard profile nursery size is 4MB")
     (assert-equal (gc-mature-size) 67108864 "Standard profile mature size is 64MB")
     (assert-equal (gc-max-size) 1073741824 "Standard profile max mature size is 1GB")))
  (flush-output-port))

;; 2. Allocate and promote objects under active profile
(let ((p (cons 100 200))
      (v (vector 1 2 3 4 5)))
  (gc-minor-collect! (%get-rsp))
  (assert-equal (car p) 100 "Promoted pair car preserved")
  (assert-equal (cdr p) 200 "Promoted pair cdr preserved")
  (assert-equal (vector-ref v 2) 3 "Promoted vector element preserved"))

;; 3. Test dynamic profile initialization: 'compiler profile
(write-string "--- Testing Dynamic Compiler Profile Switching ---\n")
(flush-output-port)
(gc-init-profile! 'compiler)
(assert-equal (gc-current-profile) 'compiler "Switched profile is 'compiler")
(assert-equal (gc-profile-id) 1 "Profile ID is 1")
(assert-equal (gc-nursery-size) 2147483648 "Compiler nursery size is 2GB")
(assert-equal (gc-mature-size) 2147483648 "Compiler mature size is 2GB")
(assert-equal (gc-max-size) 8589934592 "Compiler max mature size is 8GB")

(let ((cp (cons 111 222)))
  (gc-minor-collect! (%get-rsp))
  (assert-equal (car cp) 111 "Compiler promoted pair preserved"))

;; 4. Test dynamic profile initialization: 'server profile
(write-string "--- Testing Dynamic Server Profile Switching ---\n")
(flush-output-port)
(gc-init-profile! 'server)
(assert-equal (gc-current-profile) 'server "Switched profile is 'server")
(assert-equal (gc-profile-id) 2 "Profile ID is 2")
(assert-equal (gc-nursery-size) 16777216 "Server nursery size is 16MB")
(assert-equal (gc-mature-size) 268435456 "Server mature size is 256MB")
(assert-equal (gc-max-size) 4294967296 "Server max mature size is 4GB")

(let ((sp (cons 333 444)))
  (gc-minor-collect! (%get-rsp))
  (assert-equal (car sp) 333 "Server promoted pair preserved"))

;; 5. Test dynamic profile initialization: 'standard profile
(write-string "--- Testing Dynamic Standard Profile Switching ---\n")
(flush-output-port)
(gc-init-profile! 'standard)
(assert-equal (gc-current-profile) 'standard "Switched profile is 'standard")
(assert-equal (gc-profile-id) 0 "Profile ID is 0")
(assert-equal (gc-nursery-size) 4194304 "Standard nursery size is 4MB")
(assert-equal (gc-mature-size) 67108864 "Standard mature size is 64MB")
(assert-equal (gc-max-size) 1073741824 "Standard max mature size is 1GB")

(let ((stdp (cons 555 666)))
  (gc-minor-collect! (%get-rsp))
  (assert-equal (car stdp) 555 "Standard promoted pair preserved"))

;; 6. Final exit check
(test-end "gc-profile")
