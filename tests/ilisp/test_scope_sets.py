from ilisp.backend.py_codegen.compiler import compile_ilisp
from ilisp.env import make_initial_env
from ilisp.evaluator import eval_expr
from ilisp.reader import read_all, read_one
from ilisp.syntax import Scope, Syntax, SyntaxRulesTransformer, datum_to_syntax
from ilisp.types import Symbol


class TestScopeSetsBasics:
    """Test fundamental Scope and Syntax object behaviors."""

    def test_scope_equality_and_hashing(self) -> None:
        s1 = Scope("a")
        s2 = Scope("b")
        s3 = Scope("a")
        assert s1 != s2
        assert s1 != s3
        assert s1 == s1
        scope_set = {s1, s2}
        assert s1 in scope_set
        assert s3 not in scope_set

    def test_syntax_wrapping_and_scopes(self) -> None:
        sym = Symbol.intern("foo")
        stx = datum_to_syntax(sym)
        assert isinstance(stx, Syntax)
        assert stx.datum == sym
        assert len(stx.scopes) == 0

        sc = Scope("test")
        stx2 = stx.add_scope(sc)
        assert sc in stx2.scopes
        assert sc not in stx.scopes  # Immutability of original


class TestSyntaxRulesTransformation:
    """Test Pattern Matching, Ellipsis Expansion, and hygienic transformation."""

    def test_basic_syntax_rules_pattern(self) -> None:
        # (define-syntax my-when
        #   (syntax-rules ()
        #     ((my-when test body)
        #      (if test body '()))))
        rule_pat = read_one("(my-when test body)")
        rule_tmpl = read_one("(if test body '())")
        transformer = SyntaxRulesTransformer("my-when", [], [(rule_pat, rule_tmpl)])

        input_call = read_one("(my-when (> 3 2) (+ 10 20))")
        expanded = transformer.transform(input_call)

        env = make_initial_env()
        res = eval_expr(expanded, env)
        assert res == 30

    def test_ellipsis_expansion(self) -> None:
        # (define-syntax my-seq
        #   (syntax-rules ()
        #     ((my-seq e ...)
        #      (begin e ...))))
        rule_pat = read_one("(my-seq e ...)")
        rule_tmpl = read_one("(begin e ...)")
        transformer = SyntaxRulesTransformer("my-seq", [], [(rule_pat, rule_tmpl)])

        input_call = read_one("(my-seq 1 2 3 4)")
        expanded = transformer.transform(input_call)

        env = make_initial_env()
        res = eval_expr(expanded, env)
        assert res == 4

    def test_literals_matching(self) -> None:
        # (define-syntax my-cond
        #   (syntax-rules (else)
        #     ((my-cond (else expr)) expr)
        #     ((my-cond (test expr)) (if test expr #f))))
        rules = [
            (read_one("(my-cond (else expr))"), read_one("expr")),
            (read_one("(my-cond (test expr))"), read_one("(if test expr #f)")),
        ]
        transformer = SyntaxRulesTransformer("my-cond", ["else"], rules)

        # Match else
        res_else = transformer.transform(read_one("(my-cond (else 42))"))
        env = make_initial_env()
        assert eval_expr(res_else, env) == 42

        # Match non-else
        res_test = transformer.transform(read_one("(my-cond ((> 5 1) 100))"))
        assert eval_expr(res_test, env) == 100


class TestHygienicAntiCapture:
    """Verify that Scope Sets prevents variable capture."""

    def test_variable_capture_prevention_swap(self) -> None:
        # Classic variable capture dilemma:
        # A macro introducing 'temp' must NOT capture a caller variable also named 'temp'.
        # (define-syntax my-swap
        #   (syntax-rules ()
        #     ((my-swap a b)
        #      (let ((temp a))
        #        (set! a b)
        #        (set! b temp)))))
        code = """
        (define-syntax my-swap
          (syntax-rules ()
            ((my-swap a b)
             (let ((temp a))
               (begin
                 (set! a b)
                 (set! b temp))))))

        (let ((temp 10) (x 20))
          (begin
            (my-swap temp x)
            temp))
        """
        env = make_initial_env()
        exprs = read_all(code)
        res = None
        for e in exprs:
            res = eval_expr(e, env)
        # In a hygienic system, 'temp' was 10 and 'x' was 20.
        # After my-swap, 'temp' should be 20!
        # If unhygienic capture occurred, (let ((temp temp))) would break or corrupt values.
        assert res == 20

    def test_macro_introduced_helper_variable_independence(self) -> None:
        code = """
        (define-syntax inc-with-shadow
          (syntax-rules ()
            ((inc-with-shadow val)
             (let ((x 100))
               (+ val x)))))

        (let ((x 5))
          (inc-with-shadow x))
        """
        env = make_initial_env()
        exprs = read_all(code)
        res = None
        for e in exprs:
            res = eval_expr(e, env)
        # Macro's internal 'x' is 100, passed caller's 'x' is 5 -> result is 105
        assert res == 105


class TestBackendAIntegration:
    """Verify that syntax-rules works transparently under Backend A (Python AST compiler)."""

    def test_py_codegen_hygienic_swap(self) -> None:
        code = """
        (define-syntax my-swap
          (syntax-rules ()
            ((my-swap a b)
             (let ((temp a))
               (begin
                 (set! a b)
                 (set! b temp))))))

        (let ((temp 100) (y 200))
          (begin
            (my-swap temp y)
            temp))
        """
        env = make_initial_env()
        res = compile_ilisp(code, env=env)
        assert res == 200

    def test_py_codegen_ellipsis_macro(self) -> None:
        code = """
        (define-syntax my-sum
          (syntax-rules ()
            ((my-sum e ...)
             (+ e ...))))

        (my-sum 1 2 3 4 5)
        """
        env = make_initial_env()
        res = compile_ilisp(code, env=env)
        assert res == 15
