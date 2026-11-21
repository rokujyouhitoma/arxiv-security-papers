#!/usr/bin/env python3
"""Unit and Integration Tests for C99 PEG Grammar Specification (tools/grammars/c99.peg).

Validates compilation and execution of tools/grammars/c99.peg via src/core/peg/
(MetaGrammarParser + CodeGenerator + Warth Left-Recursion Packrat runtime).
Conforms to DSN-25, DSN-33-11, DSN-33-32 & Issue #931.
"""

from __future__ import annotations

from pathlib import Path
from typing import Any, Dict

from core.peg.compiler.backend.python import CodeGenerator
from core.peg.compiler.parser import MetaGrammarParser
from core.peg.runtime import PEGSyntaxError

ROOT_DIR = Path(__file__).resolve().parents[4]
C99_PEG_PATH = ROOT_DIR / "tools" / "grammars" / "c99.peg"


def _compile_c99_parser() -> Any:
    text = C99_PEG_PATH.read_text(encoding="utf-8")
    ast = MetaGrammarParser(use_aot=False).parse(text)
    code = CodeGenerator(ast).generate()
    ns: Dict[str, Any] = {}
    exec(code, ns)
    return ns["C99Parser"]()


class TestC99PEGGrammar:
    """Validates C99 PEG grammar compilation and real C99/Lua snippet parsing."""

    @classmethod
    def setup_class(cls) -> None:
        cls.parser = _compile_c99_parser()

    def test_c99_grammar_compiles_with_all_rules(self) -> None:
        text = C99_PEG_PATH.read_text(encoding="utf-8")
        ast = MetaGrammarParser(use_aot=False).parse(text)
        assert ast.name == "C99"
        assert len(ast.rules) >= 70

    def test_left_recursive_postfix_and_precedence(self) -> None:
        code = """
        int calc_expr(int *p, int i) {
            int v = 1 + 2 * 3 - (4 << 1);
            int w = p[i] + sizeof(int) + sizeof p[0] + (int){ 10, 20 }[0];
            return v + w;
        }
        """
        res = self.parser.parse(code)
        assert res is not None

    def test_complex_declarators_and_function_pointers(self) -> None:
        code = """
        int (*(*signal(int sig, void (*func)(int)))(int));
        typedef int (*lua_CFunction)(void *L);
        typedef int T;
        int f(int T) { return T + 1; }
        """
        res = self.parser.parse(code)
        assert res is not None

    def test_c99_designated_initializers_and_for_decl(self) -> None:
        code = """
        struct Point { int x; int y; };
        int sum_points(int n) {
            struct Point p = { .y = 2, .x = 1 };
            int a[4] = { [2] = 42, [0] = 7 };
            int s = 0;
            for (int i = 0; i < n; i++) {
                s += p.x + a[i & 3];
            }
            return s;
        }
        """
        res = self.parser.parse(code)
        assert res is not None

    def test_hex_floats_and_integer_suffixes(self) -> None:
        code = """
        double fhex = 0x1.8p+1;
        float fsuf = 3.14f;
        unsigned long long mask = 0xFFFFFFFFFFFFFFFFULL;
        const char *msg = "hello" " world\\n";
        """
        res = self.parser.parse(code)
        assert res is not None

    def test_lua_5x_core_snippet_parses(self) -> None:
        lua_code = """
        typedef unsigned char lu_byte;
        typedef double lua_Number;
        typedef long long lua_Integer;
        typedef struct lua_State lua_State;
        typedef int (*lua_CFunction)(lua_State *L);

        typedef union Value {
            void *gc;
            void *p;
            int b;
            lua_CFunction f;
            lua_Integer i;
            lua_Number n;
        } Value;

        typedef struct TValue {
            Value value_;
            lu_byte tt_;
        } TValue;

        int luaV_execute(lua_State *L, int nexeccalls) {
            int pc = 0;
            for (int i = 0; i < nexeccalls; i++) {
                int op = i & 0x3F;
                switch (op) {
                    case 0:
                        pc += 1;
                        break;
                    case 1:
                        goto l_ret;
                    default:
                        pc = pc + 2;
                        break;
                }
            }
        l_ret:
            return pc;
        }
        """
        res = self.parser.parse(lua_code)
        assert res is not None

    def test_invalid_c99_syntax_raises_peg_error(self) -> None:
        try:
            self.parser.parse("int broken(void) { return 1 + ; }")
            raise AssertionError("Expected PEGSyntaxError for invalid syntax")
        except PEGSyntaxError:
            pass
