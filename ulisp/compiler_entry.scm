;;; =======================================================================
;;; ULisp Compiler Entry Point: compiler_entry.scm
;;; Conforms to DSN-33 Architecture Specification & Issue #606
;;; Loads all compiler infrastructure, frontend, LIR, and backend passes via R7RS include
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

;; Compiler Base Infrastructure
(include "compiler/helpers.scm")
(include "compiler/primitives.scm")
(include "compiler/nanopass_meta.scm")
(include "compiler/nanopass.scm")
(include "compiler/verifier.scm")
(include "compiler/pass_manager.scm")
(include "compiler/dataflow.scm")
(include "compiler/scope.scm")

;; Frontend Passes
(include "frontend/frontend_lang.scm")
(include "frontend/010_library.scm")
(include "frontend/015_dsl_expander.scm")
(include "frontend/020_macro_expander.scm")
(include "frontend/025_top_level.scm")
(include "frontend/026_desugar_constructors.scm")
(include "frontend/027_desugar_conditionals.scm")
(include "frontend/028_desugar_bindings.scm")
(include "frontend/029_desugar_dynamic.scm")
(include "frontend/030_desugar.scm")
(include "frontend/040_analysis.scm")
(include "frontend/050_cp0.scm")
(include "frontend/060_lvn.scm")
(include "frontend/070_anf.scm")
(include "frontend/080_annotator.scm")
(include "frontend/090_rtyper.scm")
(include "frontend/100_contify.scm")
(include "frontend/110_closure_convert.scm")
(include "frontend/120_alias_escape.scm")

;; LIR Passes
(include "lir/lir_lang.scm")
(include "lir/lir_verifier.scm")
(include "lir/123_lir_closures.scm")
(include "lir/124_lir_call_abi.scm")
(include "lir/125_lir_continuation.scm")
(include "lir/126_lir_control.scm")
(include "lir/127_lir_runtime.scm")
(include "lir/128_lir_branch_fusion.scm")
(include "lir/129_lir_primitives.scm")
(include "lir/130_lir.scm")
(include "lir/131_lir_safepoint.scm")
(include "lir/132_lir_braun_ssa.scm")
(include "lir/133_lir_peephole.scm")

;; Backend Passes
(include "backend/backend_lang.scm")
(include "backend/140_backend_x86_64.scm")
(include "backend/141_backend_x86_gc.scm")
(include "backend/142_backend_x86_freestanding.scm")
(include "backend/143_backend_x86_peephole.scm")
(include "backend/elf64_builder.scm")
(include "backend/144a_x86_assembler.scm")
(include "backend/144_backend_x86_elf.scm")
(include "backend/150_backend_aarch64.scm")
(include "backend/160_backend_c.scm")

;; Driver & CLI
(include "compiler/driver.scm")
