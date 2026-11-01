;;; =======================================================================
;;; R7RS Library: (ulisp concurrency eval-adapter)
;;; Conforms to DSN-37 Section 13 & Phase 5 Task 5.3 (Issue #644)
;;; =======================================================================

(define-library (ulisp concurrency eval-adapter)
  (export
    ;; Affine syntax linter
    lint-affine-syntax
    affine-syntax-valid?

    ;; Dynamic task arena scoping
    current-task-arena
    with-task-arena

    ;; Scope environment
    <eval-env>
    eval-env?
    make-eval-env
    eval-env-bind!
    eval-env-lookup
    eval-env-bound?

    ;; Closure
    <eval-closure>
    eval-closure?
    make-eval-closure
    eval-closure-params
    eval-closure-body
    eval-closure-env

    ;; Tree-walk evaluator & factory
    eval-in-task
    make-default-eval-env
    set-eval-yield-hook!
    eval-yield-hook)
  (import (scheme base))
  (include "../../../runtime/concurrency/eval_adapter.scm"))

