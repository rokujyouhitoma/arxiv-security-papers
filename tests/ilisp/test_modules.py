"""Unit tests for R7RS Module & Library System (define-library, import, export)."""

import pytest

from ilisp.backend.py_codegen.compiler import compile_ilisp
from ilisp.env import Environment, make_initial_env
from ilisp.evaluator import eval_expr
from ilisp.module import GLOBAL_LIBRARY_REGISTRY, parse_library_name
from ilisp.reader import read_all, read_one
from ilisp.types import Symbol


class TestModuleBasicsAndBuiltins:
    """Test library name parsing and standard built-in library exports."""

    def test_parse_library_name(self) -> None:
        expr = read_one("(scheme base)")
        assert parse_library_name(expr) == ("scheme", "base")

        expr_num = read_one("(foo bar 1 2)")
        assert parse_library_name(expr_num) == ("foo", "bar", "1", "2")

    def test_builtin_libraries_registered(self) -> None:
        assert GLOBAL_LIBRARY_REGISTRY.has(("scheme", "base"))
        assert GLOBAL_LIBRARY_REGISTRY.has(("scheme", "write"))
        assert GLOBAL_LIBRARY_REGISTRY.has(("scheme", "load"))
        assert GLOBAL_LIBRARY_REGISTRY.has(("ilisp", "python"))

    def test_import_builtin_scheme_base(self) -> None:
        env = Environment()  # Completely clean empty environment
        code = """
        (import (scheme base))
        (+ 10 20)
        """
        exprs = read_all(code)
        res = None
        for e in exprs:
            res = eval_expr(e, env)
        assert res == 30


class TestImportModifiers:
    """Test only, except, prefix, and rename import set modifiers."""

    def test_import_only(self) -> None:
        env = Environment()
        code = """
        (import (only (scheme base) + *))
        (+ 2 (* 3 4))
        """
        for e in read_all(code):
            eval_expr(e, env)

        # '+' and '*' should exist
        assert env.lookup(Symbol.intern("+")) is not None
        assert env.lookup(Symbol.intern("*")) is not None

        # 'cons' should NOT exist
        with pytest.raises(NameError):
            env.lookup(Symbol.intern("cons"))

    def test_import_except(self) -> None:
        env = Environment()
        code = """
        (import (except (scheme base) +))
        """
        for e in read_all(code):
            eval_expr(e, env)

        # '*' and 'cons' exist
        assert env.lookup(Symbol.intern("*")) is not None
        assert env.lookup(Symbol.intern("cons")) is not None

        # '+' was excluded
        with pytest.raises(NameError):
            env.lookup(Symbol.intern("+"))

    def test_import_prefix(self) -> None:
        env = Environment()
        code = """
        (import (prefix (only (scheme base) + *) my:))
        (my:+ 10 (my:* 2 3))
        """
        res = None
        for e in read_all(code):
            res = eval_expr(e, env)
        assert res == 16

    def test_import_rename(self) -> None:
        env = Environment()
        code = """
        (import (rename (only (scheme base) + *) (+ add) (* multiply)))
        (add 5 (multiply 4 2))
        """
        res = None
        for e in read_all(code):
            res = eval_expr(e, env)
        assert res == 13


class TestDefineLibraryAndEncapsulation:
    """Test user-defined define-library, exports, and private encapsulation."""

    def test_custom_library_definition_and_isolation(self) -> None:
        code = """
        (define-library (example math)
          (import (scheme base))
          (export square add-squares (rename cube pow3))
          (begin
            ;; Private helper not exported
            (define (internal-mult x y) (* x y))

            (define (square x) (internal-mult x x))
            (define (cube x) (* x (square x)))
            (define (add-squares a b) (+ (square a) (square b)))))

        (import (example math))
        (add-squares 3 4)
        """
        env = Environment()
        res = None
        for e in read_all(code):
            res = eval_expr(e, env)
        assert res == 25

        # Check renamed export
        res_pow3 = eval_expr(read_one("(pow3 3)"), env)
        assert res_pow3 == 27

        # Private helper must not be leaked into caller env
        with pytest.raises(NameError):
            env.lookup(Symbol.intern("internal-mult"))


class TestBackendAModuleIntegration:
    """Verify that define-library and import compile cleanly under Backend A."""

    def test_py_codegen_library_and_import(self) -> None:
        code = """
        (define-library (app geometry)
          (import (scheme base))
          (export area)
          (begin
            (define (area w h) (* w h))))

        (import (app geometry))
        (area 6 7)
        """
        env = make_initial_env()
        res = compile_ilisp(code, env=env)
        assert res == 42


class TestImportPythonInterop:
    """Test (import-python ...) syntax and seamless Python interoperability."""

    def test_import_python_alias(self) -> None:
        code = """
        (import-python (math :as m))
        (py-call m 'sqrt 16)
        """
        env = make_initial_env()
        res = None
        for e in read_all(code):
            res = eval_expr(e, env)
        assert res == 4.0

    def test_import_python_members(self) -> None:
        code = """
        (import-python (math sqrt (pi :as py-pi)))
        (list (py-call sqrt 25) py-pi)
        """
        env = make_initial_env()
        res = None
        for e in read_all(code):
            res = eval_expr(e, env)
        import math

        assert res.car == 5.0
        assert res.cdr.car == math.pi

    def test_import_python_direct_and_list_module(self) -> None:
        code = """
        (import-python (json) os)
        (list (py-call json 'dumps '(1 2 3)) (py-get os 'name))
        """
        env = make_initial_env()
        res = None
        for e in read_all(code):
            res = eval_expr(e, env)
        import os

        assert res.car == "[1, 2, 3]"
        assert res.cdr.car == os.name

    def test_import_python_missing_module_error(self) -> None:
        from ilisp.types import SchemeException

        code = """
        (import-python (torch :as th)(transformers AutoTokenizer))
        """
        env = make_initial_env()
        with pytest.raises(SchemeException) as exc_info:
            for e in read_all(code):
                eval_expr(e, env)
        assert "import-python: failed to import module 'torch'" in str(exc_info.value)

    def test_import_python_in_define_library(self) -> None:
        code = """
        (define-library (app pymath)
          (import (scheme base)
                  (ilisp python))
          (export calc-root)
          (begin
            (import-python (math sqrt))
            (define (calc-root x) (py-call sqrt x))))

        (import (app pymath))
        (calc-root 49)
        """
        env = make_initial_env()
        res = None
        for e in read_all(code):
            res = eval_expr(e, env)
        assert res == 7.0

    def test_import_python_backend_a(self) -> None:
        code = """
        (import-python (math sqrt))
        (py-call sqrt 64)
        """
        env = make_initial_env()
        res = compile_ilisp(code, env=env)
        assert res == 8.0

    def test_threading_macro(self) -> None:
        code = """
        (->> 10
             (+ 5)
             (* 2))
        """
        env = make_initial_env()
        res = None
        for e in read_all(code):
            res = eval_expr(e, env)
        assert res == 30
