"""Test Suite for R7RS Record Types (define-record-type and primitives).

Tests generative record type descriptor creation, constructors, predicates,
accessors, modifiers, field isolation, equality, and Python interop.
"""

from __future__ import annotations

from typing import Any

import pytest

from ilisp.backend.py_codegen.compiler import compile_ilisp
from ilisp.env import make_initial_env
from ilisp.evaluator import eval_expr
from ilisp.reader import read_all
from ilisp.types import Record, RecordType, Symbol


def run_code(code: str) -> Any:
    env = make_initial_env()
    res = None
    for expr in read_all(code):
        res = eval_expr(expr, env)
    return res


class TestRecordTypeBasics:
    """Tests basic define-record-type syntax, accessors, and mutators."""

    def test_basic_point_record(self) -> None:
        code = """
        (define-record-type <point>
          (make-point x y)
          point?
          (x point-x point-x-set!)
          (y point-y))

        (define p (make-point 10 20))
        (list (point? p) (point-x p) (point-y p))
        """
        res = run_code(code)
        assert hasattr(res, "car")
        assert res.car is True  # point?
        assert res.cdr.car == 10  # point-x
        assert res.cdr.cdr.car == 20  # point-y

    def test_record_mutation(self) -> None:
        code = """
        (define-record-type <point>
          (make-point x y)
          point?
          (x point-x point-x-set!)
          (y point-y point-y-set!))

        (define p (make-point 1 2))
        (point-x-set! p 42)
        (point-y-set! p 99)
        (list (point-x p) (point-y p))
        """
        res = run_code(code)
        assert res.car == 42
        assert res.cdr.car == 99

    def test_immutable_field_has_no_setter(self) -> None:
        code = """
        (define-record-type <kons>
          (kons kar kdr)
          kons?
          (kar get-kar)
          (kdr get-kdr set-kdr!))

        (define k (kons 100 200))
        (list (get-kar k) (get-kdr k))
        """
        res = run_code(code)
        assert res.car == 100
        assert res.cdr.car == 200

    def test_partial_constructor_fields(self) -> None:
        code = """
        (define-record-type <person>
          (make-person name)
          person?
          (name person-name)
          (age person-age person-age-set!))

        (define alice (make-person "Alice"))
        (list (person-name alice) (person-age alice))
        """
        res = run_code(code)
        assert res.car == "Alice"
        assert res.cdr.car is False  # uninitialized fields default to #f


class TestRecordTypeDisjointnessAndSafety:
    """Tests generativity, type isolation, and error handling."""

    def test_disjoint_types_with_same_structure(self) -> None:
        code = """
        (define-record-type <type-a>
          (make-a val)
          a?
          (val a-val))

        (define-record-type <type-b>
          (make-b val)
          b?
          (val b-val))

        (define obj-a (make-a 10))
        (define obj-b (make-b 10))

        (list (a? obj-a) (a? obj-b) (b? obj-a) (b? obj-b))
        """
        res = run_code(code)
        assert res.car is True
        assert res.cdr.car is False
        assert res.cdr.cdr.car is False
        assert res.cdr.cdr.cdr.car is True

    def test_accessor_type_mismatch_raises(self) -> None:
        code = """
        (define-record-type <cat>
          (make-cat name)
          cat?
          (name cat-name))

        (define-record-type <dog>
          (make-dog name)
          dog?
          (name dog-name))

        (define d (make-dog "Fido"))
        (cat-name d)
        """
        with pytest.raises(TypeError, match="cat"):
            run_code(code)

    def test_predicate_on_non_records(self) -> None:
        code = """
        (define-record-type <box>
          (make-box x)
          box?
          (x unbox))

        (list (box? 123) (box? "hello") (box? '(1 2)) (box? #(1 2)) (box? '()))
        """
        res = run_code(code)
        while hasattr(res, "car"):
            assert res.car is False
            res = res.cdr


class TestRecordEquality:
    """Tests eq?, eqv?, and equal? on records."""

    def test_record_equal_p(self) -> None:
        code = """
        (define-record-type <node>
          (make-node val left right)
          node?
          (val node-val)
          (left node-left)
          (right node-right))

        (define n1 (make-node 10 "leaf" #f))
        (define n2 (make-node 10 "leaf" #f))
        (define n3 (make-node 20 "leaf" #f))

        (list (equal? n1 n2) (equal? n1 n3) (eqv? n1 n2) (eq? n1 n1))
        """
        res = run_code(code)
        assert res.car is True  # equal? n1 n2
        assert res.cdr.car is False  # equal? n1 n3
        assert res.cdr.cdr.car is False  # eqv? n1 n2 (distinct instances)
        assert res.cdr.cdr.cdr.car is True  # eq? n1 n1 (same instance)


class TestRecordLowLevelPrimitives:
    """Tests low-level primitives: make-record-type, record-ref, record-set!, etc."""

    def test_low_level_api(self) -> None:
        code = """
        (define rtd (make-record-type 'coord '(x y z)))
        (define rec (make-record rtd 1 2 3))
        (record-set! rec 'y 200)

        (list (record-type? rtd)
              (record? rec)
              (record-type-name rtd)
              (record-ref rec 'x)
              (record-ref rec 'y)
              (record-ref rec 'z))
        """
        res = run_code(code)
        items = []
        curr = res
        while hasattr(curr, "car"):
            items.append(curr.car)
            curr = curr.cdr

        assert items[0] is True  # record-type?
        assert items[1] is True  # record?
        assert items[2] == Symbol.intern("coord")  # record-type-name
        assert items[3] == 1  # record-ref x
        assert items[4] == 200  # record-ref y
        assert items[5] == 3  # record-ref z

    def test_python_attribute_interop(self) -> None:
        code = """
        (define-record-type <person>
          (make-person name age)
          person?
          (name person-name person-name-set!)
          (age person-age person-age-set!))

        (make-person "Alice" 30)
        """
        rec = run_code(code)
        assert isinstance(rec, Record)
        assert isinstance(rec.record_type, RecordType)
        # Direct Python attribute access
        assert rec.name == "Alice"
        assert rec.age == 30
        # Python mutation
        rec.age = 31
        assert rec.age == 31


class TestBackendARecordIntegration:
    """Tests that Backend A (Python AST transpiler) compiles and executes record types."""

    def test_py_codegen_records(self) -> None:
        code = """
        (define-record-type <vector2d>
          (make-v2d x y)
          v2d?
          (x v2d-x v2d-x-set!)
          (y v2d-y))

        (define v (make-v2d 3 4))
        (v2d-x-set! v 30)
        (list (v2d? v) (v2d-x v) (v2d-y v))
        """
        res = compile_ilisp(code)
        assert hasattr(res, "car")
        assert res.car is True
        assert res.cdr.car == 30
        assert res.cdr.cdr.car == 4
