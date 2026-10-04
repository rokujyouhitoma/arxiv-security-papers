"""Tests for R7RS 6.11 Exception and Condition Primitives in ILISP."""

from typing import Any

import pytest

from ilisp.backend.py_codegen.compiler import compile_ilisp
from ilisp.env import make_initial_env
from ilisp.evaluator import eval_expr
from ilisp.reader import read_all
from ilisp.types import Symbol, to_py_list


def run_code(code: str) -> Any:
    """Helper to evaluate ILISP code with standard environment."""
    env = make_initial_env(preload_stdlib=True)
    exprs = read_all(code)
    res = None
    for e in exprs:
        res = eval_expr(e, env)
    return res


class TestErrorObjectBasics:
    """Test error-object?, message, irritants and error procedure."""

    def test_error_object_predicate_on_non_errors(self) -> None:
        code = """
        (list (error-object? 123)
              (error-object? "error")
              (error-object? 'error)
              (error-object? '(1 2 3))
              (error-object? #f))
        """
        res = run_code(code)
        assert to_py_list(res) == [False, False, False, False, False]

    def test_error_procedure_and_guard(self) -> None:
        code = """
        (guard (e ((error-object? e)
                   (list (error-object-message e)
                         (error-object-irritants e))))
          (error "Something went wrong" 10 20))
        """
        res = run_code(code)
        items = to_py_list(res)
        assert items[0] == "Something went wrong"
        assert to_py_list(items[1]) == [10, 20]

    def test_error_without_irritants(self) -> None:
        code = """
        (guard (e ((error-object? e)
                   (list (error-object-message e)
                         (null? (error-object-irritants e)))))
          (error "Simple error"))
        """
        res = run_code(code)
        items = to_py_list(res)
        assert items[0] == "Simple error"
        assert items[1] is True

    def test_error_object_accessors_type_error(self) -> None:
        with pytest.raises(
            TypeError, match="error-object-message: expected error-object"
        ):
            run_code('(error-object-message "not an error")')

        with pytest.raises(
            TypeError, match="error-object-irritants: expected error-object"
        ):
            run_code("(error-object-irritants 42)")


class TestReadAndFileErrors:
    """Test read-error? and file-error? predicates."""

    def test_file_error_explicit(self) -> None:
        code = """
        (guard (e ((file-error? e) 'caught-file-error)
                  ((read-error? e) 'caught-read-error)
                  (else 'caught-other))
          (file-error "Cannot open file" "test.txt"))
        """
        res = run_code(code)
        assert res == Symbol.intern("caught-file-error")

    def test_read_error_explicit(self) -> None:
        code = """
        (guard (e ((file-error? e) 'caught-file-error)
                  ((read-error? e) 'caught-read-error)
                  (else 'caught-other))
          (read-error "Unexpected EOF" 42))
        """
        res = run_code(code)
        assert res == Symbol.intern("caught-read-error")

    def test_file_error_on_missing_file_io(self) -> None:
        code = """
        (guard (e ((file-error? e)
                   (list 'file-error-detected (error-object? e)))
                  (else 'other-error))
          (open-input-file "non_existent_file_123456789.scm"))
        """
        res = run_code(code)
        items = to_py_list(res)
        assert items[0] == Symbol.intern("file-error-detected")
        assert items[1] is True

    def test_read_error_on_bad_syntax_read(self) -> None:
        code = """
        (guard (e ((read-error? e) 'read-error-detected)
                  (else 'other-error))
          (read (open-input-string "(unclosed list 1 2 3")))
        """
        res = run_code(code)
        assert res == Symbol.intern("read-error-detected")


class TestGuardAdvancedClauses:
    """Test guard with => arrow syntax and multi-condition dispatch."""

    def test_guard_arrow_syntax_with_error_object(self) -> None:
        code = """
        (guard (e (((lambda (obj) (if (error-object? obj) obj #f)) e) => error-object-message)
                  (else "unknown"))
          (error "arrow syntax test" 'val))
        """
        res = run_code(code)
        assert res == "arrow syntax test"

    def test_guard_fallthrough_to_else(self) -> None:
        code = """
        (guard (e ((read-error? e) 'read)
                  ((file-error? e) 'file)
                  (else (error-object-message e)))
          (error "fallback to else"))
        """
        res = run_code(code)
        assert res == "fallback to else"

    def test_reraise_when_no_clause_matches(self) -> None:
        code = """
        (guard (outer ((error-object? outer) 'caught-outer))
          (guard (inner ((read-error? inner) 'read))
            (error "unhandled in inner")))
        """
        res = run_code(code)
        assert res == Symbol.intern("caught-outer")


class TestBackendAExceptionIntegration:
    """Test Python AST transpiler code generation for error and guard."""

    def test_compile_error_and_guard(self) -> None:
        code = """
        (guard (e ((error-object? e) (error-object-message e))
                  (else "other"))
          (error "compiled error" 123))
        """
        res = compile_ilisp(code)
        assert res == "compiled error"

    def test_compile_file_error_catch(self) -> None:
        code = """
        (guard (e ((file-error? e) 'file-ok)
                  (else 'other))
          (file-error "cannot open" "foo.scm"))
        """
        res = compile_ilisp(code)
        assert res == Symbol.intern("file-ok")
