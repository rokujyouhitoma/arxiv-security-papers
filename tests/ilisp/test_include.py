"""Unit tests for R7RS include, include-ci, and include-library-declarations."""

from typing import Any

import pytest

from ilisp import eval_expr, make_initial_env, read_all, read_all_from_file
from ilisp.backend.py_codegen.compiler import compile_ilisp
from ilisp.module import GLOBAL_LIBRARY_REGISTRY
from ilisp.types import SchemeException, Symbol


class TestReadAllFromFile:
    """Tests for reader's read_all_from_file utility."""

    def test_read_all_from_file_valid(self, tmp_path: Any) -> None:
        p = tmp_path / "simple.scm"
        p.write_text("(define x 42) (+ x 8)", encoding="utf-8")
        exprs = read_all_from_file(str(p))
        assert len(exprs) == 2

    def test_read_all_from_file_missing(self, tmp_path: Any) -> None:
        p = tmp_path / "nonexistent.scm"
        with pytest.raises(SchemeException) as exc_info:
            read_all_from_file(str(p))
        assert "cannot read file" in str(exc_info.value)
        assert exc_info.value.datum.kind == "file"

    def test_read_all_from_file_fold_case(self, tmp_path: Any) -> None:
        p = tmp_path / "case.scm"
        p.write_text("(FOO Bar BAZ-QUX)", encoding="utf-8")
        exprs = read_all_from_file(str(p), fold_case=True)
        assert len(exprs) == 1
        syms = [s.name for s in exprs[0]]
        assert syms == ["foo", "bar", "baz-qux"]


class TestIncludeExpression:
    """Tests for (include ...) expression-level form."""

    def test_include_basic_definition_and_splicing(self, tmp_path: Any) -> None:
        inc_file = tmp_path / "inc.scm"
        inc_file.write_text(
            "(define my-val 100) (define (get-my-val) my-val)", encoding="utf-8"
        )

        main_file = tmp_path / "main.scm"
        main_file.write_text(
            f'(include "{inc_file.name}") (get-my-val)', encoding="utf-8"
        )

        env = make_initial_env()
        exprs = read_all_from_file(str(main_file))
        res = None
        for e in exprs:
            res = eval_expr(e, env)

        assert res == 100
        assert env.lookup(Symbol.intern("my-val")) == 100

    def test_include_multiple_files_sequential(self, tmp_path: Any) -> None:
        f1 = tmp_path / "f1.scm"
        f1.write_text("(define a 10)", encoding="utf-8")
        f2 = tmp_path / "f2.scm"
        f2.write_text("(define b (+ a 5)) (* a b)", encoding="utf-8")

        main_file = tmp_path / "main.scm"
        main_file.write_text(f'(include "{f1.name}" "{f2.name}")', encoding="utf-8")

        env = make_initial_env()
        exprs = read_all_from_file(str(main_file))
        res = None
        for e in exprs:
            res = eval_expr(e, env)

        assert res == 150
        assert env.lookup(Symbol.intern("a")) == 10
        assert env.lookup(Symbol.intern("b")) == 15

    def test_include_empty_file(self, tmp_path: Any) -> None:
        empty = tmp_path / "empty.scm"
        empty.write_text("", encoding="utf-8")

        main = tmp_path / "main.scm"
        main.write_text(f'(include "{empty.name}")', encoding="utf-8")

        env = make_initial_env()
        exprs = read_all_from_file(str(main))
        res = eval_expr(exprs[0], env)
        from ilisp.types import NIL

        assert res is NIL

    def test_include_relative_path_resolution(self, tmp_path: Any) -> None:
        sub = tmp_path / "subdir"
        sub.mkdir()
        h = sub / "helper.scm"
        h.write_text("(define sub-res 77)", encoding="utf-8")

        caller = sub / "caller.scm"
        caller.write_text('(include "helper.scm") sub-res', encoding="utf-8")

        env = make_initial_env()
        exprs = read_all_from_file(str(caller))
        res = None
        for e in exprs:
            res = eval_expr(e, env)
        assert res == 77

    def test_include_load_path_resolution(
        self, tmp_path: Any, monkeypatch: Any
    ) -> None:
        lib_dir = tmp_path / "custom_lib"
        lib_dir.mkdir()
        h = lib_dir / "lp_helper.scm"
        h.write_text("(define lp-val 888)", encoding="utf-8")

        monkeypatch.setenv("ILISP_LOAD_PATH", str(lib_dir))

        env = make_initial_env()
        code = '(include "lp_helper.scm") lp-val'
        res = None
        for e in read_all(code):
            res = eval_expr(e, env)
        assert res == 888

    def test_include_missing_file_raises_file_error(self, tmp_path: Any) -> None:
        env = make_initial_env()
        code = '(include "no_such_file_xyz_123.scm")'
        with pytest.raises(SchemeException) as exc_info:
            for e in read_all(code):
                eval_expr(e, env)
        assert "cannot find or open file" in str(exc_info.value)
        assert exc_info.value.datum.kind == "file"

    def test_include_no_arguments_raises_error(self) -> None:
        env = make_initial_env()
        code = "(include)"
        with pytest.raises(SchemeException) as exc_info:
            for e in read_all(code):
                eval_expr(e, env)
        assert "requires at least one filename" in str(exc_info.value)

    def test_include_non_string_argument_raises_error(self) -> None:
        env = make_initial_env()
        code = "(include 12345)"
        with pytest.raises(SchemeException) as exc_info:
            for e in read_all(code):
                eval_expr(e, env)
        assert "argument must be a string" in str(exc_info.value)


class TestIncludeCi:
    """Tests for (include-ci ...) case-insensitive inclusion."""

    def test_include_ci_folds_symbols(self, tmp_path: Any) -> None:
        f = tmp_path / "ci_code.scm"
        f.write_text(
            "(define MY-VAR 999) (define (COMPUTE X) (* MY-VAR X))", encoding="utf-8"
        )

        main = tmp_path / "main.scm"
        main.write_text(f'(include-ci "{f.name}") (compute 2)', encoding="utf-8")

        env = make_initial_env()
        exprs = read_all_from_file(str(main))
        res = None
        for e in exprs:
            res = eval_expr(e, env)
        assert res == 1998
        assert env.lookup(Symbol.intern("my-var")) == 999


class TestCircularIncludeDetection:
    """Tests for circular include detection and recursion prevention."""

    def test_circular_include_self(self, tmp_path: Any) -> None:
        f = tmp_path / "self_rec.scm"
        f.write_text(f'(include "{f.name}")', encoding="utf-8")

        env = make_initial_env()
        exprs = read_all_from_file(str(f))
        with pytest.raises(SchemeException) as exc_info:
            for e in exprs:
                eval_expr(e, env)
        assert "circular dependency detected" in str(exc_info.value)
        assert exc_info.value.datum.kind == "file"

    def test_circular_include_indirect(self, tmp_path: Any) -> None:
        fa = tmp_path / "a.scm"
        fb = tmp_path / "b.scm"
        fc = tmp_path / "c.scm"

        fa.write_text(f'(include "{fb.name}")', encoding="utf-8")
        fb.write_text(f'(include "{fc.name}")', encoding="utf-8")
        fc.write_text(f'(include "{fa.name}")', encoding="utf-8")

        env = make_initial_env()
        exprs = read_all_from_file(str(fa))
        with pytest.raises(SchemeException) as exc_info:
            for e in exprs:
                eval_expr(e, env)
        assert "circular dependency detected" in str(exc_info.value)
        err_msg = str(exc_info.value)
        assert "a.scm" in err_msg and "b.scm" in err_msg and "c.scm" in err_msg


class TestModuleIncludes:
    """Tests for include, include-ci, and include-library-declarations inside define-library."""

    def test_define_library_with_include(self, tmp_path: Any) -> None:
        body = tmp_path / "lib_body.scm"
        body.write_text(
            "(define (lib-square x) (* x x)) (define secret 123)", encoding="utf-8"
        )

        lib_file = tmp_path / "math_lib.sld"
        lib_file.write_text(
            f"""
            (define-library (test math)
              (export lib-square)
              (import (scheme base))
              (include "{body.name}"))
            """,
            encoding="utf-8",
        )

        env = make_initial_env()
        exprs = read_all_from_file(str(lib_file))
        for e in exprs:
            eval_expr(e, env)

        assert GLOBAL_LIBRARY_REGISTRY.has(("test", "math"))

        # Test importing from the library
        test_env = make_initial_env()
        import_code = """
        (import (test math))
        (lib-square 6)
        """
        res = None
        for e in read_all(import_code):
            res = eval_expr(e, test_env)
        assert res == 36

        # Check encapsulation: secret should not be exported
        with pytest.raises(NameError):
            test_env.lookup(Symbol.intern("secret"))

    def test_define_library_with_include_ci(self, tmp_path: Any) -> None:
        body = tmp_path / "ci_body.scm"
        body.write_text("(define (ADD-TEN N) (+ N 10))", encoding="utf-8")

        lib_file = tmp_path / "ci_lib.sld"
        lib_file.write_text(
            f"""
            (define-library (test ci-lib)
              (export add-ten)
              (import (scheme base))
              (include-ci "{body.name}"))
            """,
            encoding="utf-8",
        )

        env = make_initial_env()
        exprs = read_all_from_file(str(lib_file))
        for e in exprs:
            eval_expr(e, env)

        assert GLOBAL_LIBRARY_REGISTRY.has(("test", "ci-lib"))

        test_env = make_initial_env()
        import_code = "(import (test ci-lib)) (add-ten 25)"
        res = None
        for e in read_all(import_code):
            res = eval_expr(e, test_env)
        assert res == 35

    def test_define_library_include_library_declarations(self, tmp_path: Any) -> None:
        decls = tmp_path / "decls.sld"
        decls.write_text(
            """
            (export shared-fn)
            (import (scheme base))
            (begin
              (define (shared-fn a b) (- a b)))
            """,
            encoding="utf-8",
        )

        lib_file = tmp_path / "decls_lib.sld"
        lib_file.write_text(
            f"""
            (define-library (test decls-lib)
              (include-library-declarations "{decls.name}"))
            """,
            encoding="utf-8",
        )

        env = make_initial_env()
        exprs = read_all_from_file(str(lib_file))
        for e in exprs:
            eval_expr(e, env)

        assert GLOBAL_LIBRARY_REGISTRY.has(("test", "decls-lib"))

        test_env = make_initial_env()
        import_code = "(import (test decls-lib)) (shared-fn 50 15)"
        res = None
        for e in read_all(import_code):
            res = eval_expr(e, test_env)
        assert res == 35

    def test_define_library_circular_declarations(self, tmp_path: Any) -> None:
        d1 = tmp_path / "d1.sld"
        d2 = tmp_path / "d2.sld"
        d1.write_text(f'(include-library-declarations "{d2.name}")', encoding="utf-8")
        d2.write_text(f'(include-library-declarations "{d1.name}")', encoding="utf-8")

        lib_file = tmp_path / "circ_lib.sld"
        lib_file.write_text(
            f"""
            (define-library (test circ-lib)
              (include-library-declarations "{d1.name}"))
            """,
            encoding="utf-8",
        )

        env = make_initial_env()
        exprs = read_all_from_file(str(lib_file))
        with pytest.raises(SchemeException) as exc_info:
            for e in exprs:
                eval_expr(e, env)
        assert "circular dependency detected" in str(exc_info.value)


class TestPyCodegenInclude:
    """Tests for compiler backend A (py_codegen) with include."""

    def test_py_codegen_include_expansion(self, tmp_path: Any) -> None:
        inc = tmp_path / "helper_codegen.scm"
        inc.write_text(
            "(define x-codegen 123) (define (get-x) x-codegen)", encoding="utf-8"
        )

        main = tmp_path / "main_codegen.scm"
        main.write_text(f'(include "{inc.name}") (+ (get-x) 7)', encoding="utf-8")

        code = main.read_text(encoding="utf-8")
        env = make_initial_env()
        res = compile_ilisp(code, env=env, filename=str(main))
        assert res == 130
