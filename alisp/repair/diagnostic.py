"""S-Expression Structured Diagnostic Protocol and Macro Inversion.

Implements DSN-32 Section 6.1 & Section 6.4:
- S-expression structured diagnostics: (diagnostic (severity error) (type ...) ...)
- Macro expansion source location inversion (Source Location Inversion)
  providing LLM agents with original macro invocation expressions and lines.
"""

from __future__ import annotations

from typing import Any, List, Optional, Tuple, Union

from alisp.repair.patch import SPath
from ilisp.types import (
    NIL,
    Cons,
    SourceLocation,
    Symbol,
    car,
    cdr,
    is_pair,
    to_lisp_list,
)


class Diagnostic:
    """Structured S-expression diagnostic container as specified in DSN-32 Section 6.1."""

    def __init__(
        self,
        severity: str = "error",
        type_name: str = ":contract-violation",
        blame: Optional[str] = None,
        function: Optional[str] = None,
        argument: Optional[int] = None,
        parameter: Optional[str] = None,
        expected: Optional[Any] = None,
        received: Optional[Any] = None,
        hint: Optional[str] = None,
        location: Optional[Union[SourceLocation, str]] = None,
        target_path: Optional[Union[SPath, Any]] = None,
        original_form: Optional[Any] = None,
    ) -> None:
        self.severity = severity
        self.type_name = type_name
        self.blame = blame
        self.function = function
        self.argument = argument
        self.parameter = parameter
        self.expected = expected
        self.received = received
        self.hint = hint
        self.location = location
        self.target_path = target_path
        self.original_form = original_form

    def to_sexpr(self) -> Cons:
        """Convert Diagnostic into a compliant Scheme S-expression: (diagnostic ...)."""
        entries: List[Any] = [
            Cons(Symbol.intern("severity"), Cons(Symbol.intern(self.severity), NIL)),
            Cons(
                Symbol.intern("type"),
                Cons(Symbol.intern(self.type_name), NIL),
            ),
        ]

        if self.blame is not None:
            entries.append(
                Cons(Symbol.intern("blame"), Cons(Symbol.intern(str(self.blame)), NIL))
            )
        if self.function is not None:
            entries.append(
                Cons(
                    Symbol.intern("function"),
                    Cons(Symbol.intern(str(self.function)), NIL),
                )
            )
        if self.argument is not None:
            entries.append(Cons(Symbol.intern("argument"), Cons(self.argument, NIL)))
        if self.parameter:
            entries.append(
                Cons(
                    Symbol.intern("parameter"),
                    Cons(Symbol.intern(str(self.parameter)), NIL),
                )
            )
        if self.expected is not None:
            entries.append(
                Cons(
                    Symbol.intern("expected"),
                    Cons(
                        (
                            Symbol.intern(str(self.expected))
                            if not isinstance(self.expected, (int, float, bool, Cons))
                            else self.expected
                        ),
                        NIL,
                    ),
                )
            )
        if self.received is not None:
            entries.append(Cons(Symbol.intern("received"), Cons(self.received, NIL)))
        if self.hint:
            entries.append(Cons(Symbol.intern("hint"), Cons(self.hint, NIL)))
        if self.location is not None:
            entries.append(
                Cons(Symbol.intern("location"), Cons(str(self.location), NIL))
            )
        if self.target_path is not None:
            path_sexpr = (
                self.target_path.to_sexpr()
                if isinstance(self.target_path, SPath)
                else self.target_path
            )
            entries.append(Cons(Symbol.intern("target-path"), Cons(path_sexpr, NIL)))
        if self.original_form is not None:
            entries.append(
                Cons(Symbol.intern("original-form"), Cons(self.original_form, NIL))
            )

        return Cons(Symbol.intern("diagnostic"), to_lisp_list(entries))

    def to_string(self) -> str:
        """Serialize diagnostic S-expression to standard Scheme string format."""
        return format_sexpr(self.to_sexpr())

    def __repr__(self) -> str:
        return self.to_string()


def format_sexpr(datum: Any) -> str:
    """Format any Lisp datum to standard Scheme syntax with double-quoted strings."""
    if isinstance(datum, str):
        escaped = datum.replace("\\", "\\\\").replace('"', '\\"')
        return f'"{escaped}"'
    if isinstance(datum, Symbol):
        return datum.name
    if isinstance(datum, Cons):
        elements: List[str] = []
        curr: Any = datum
        while isinstance(curr, Cons):
            elements.append(format_sexpr(curr.car))
            curr = curr.cdr
        if curr is not NIL and curr is not None:
            return f"({' '.join(elements)} . {format_sexpr(curr)})"
        return f"({' '.join(elements)})"
    if isinstance(datum, bool):
        return "#t" if datum else "#f"
    if datum is NIL or datum is None:
        return "()"
    return str(datum)


class MacroExpansionRegistry:
    """Registry maintaining bidirectional mapping between original macro forms and expanded forms."""

    _entries: List[Tuple[Any, Any, Optional[SourceLocation]]] = []

    @classmethod
    def register(
        cls,
        input_form: Any,
        expanded_form: Any,
        loc: Optional[SourceLocation] = None,
    ) -> None:
        if loc is None and hasattr(input_form, "loc"):
            loc = getattr(input_form, "loc", None)
        cls._entries.append((input_form, expanded_form, loc))

    @classmethod
    def clear(cls) -> None:
        cls._entries.clear()

    @classmethod
    def find_original(
        cls, expanded_node: Any
    ) -> Optional[Tuple[Any, Optional[SourceLocation]]]:
        """Look up original macro invocation that generated or contains expanded_node."""
        # Search backwards (most recent macro expansions first)
        for orig, exp, loc in reversed(cls._entries):
            if orig is expanded_node or exp is expanded_node:
                return orig, loc
            # Check if expanded_node is contained inside exp
            if _ast_contains(exp, expanded_node):
                return orig, loc
        return None


def _ast_contains(haystack: Any, needle: Any) -> bool:
    """Check if needle is recursively contained in haystack AST."""
    if haystack is needle:
        return True
    if is_pair(haystack):
        return _ast_contains(car(haystack), needle) or _ast_contains(
            cdr(haystack), needle
        )
    if isinstance(haystack, list):
        return any(_ast_contains(x, needle) for x in haystack)
    return False


def invert_source_location(
    expr: Any,
    loc: Optional[SourceLocation] = None,
) -> Tuple[Optional[Any], Optional[SourceLocation]]:
    """Invert desugared or expanded code back to original macro invocation and source line.

    Returns:
        (original_form, original_source_location)
    """
    # 1. Check registry
    match = MacroExpansionRegistry.find_original(expr)
    if match:
        orig_form, reg_loc = match
        return orig_form, reg_loc or loc

    # 2. Check direct loc attribute
    if loc is None and hasattr(expr, "loc"):
        loc = getattr(expr, "loc", None)

    return expr, loc


def format_diagnostic(
    exc: Exception,
    ast: Optional[Any] = None,
    target_path: Optional[SPath] = None,
) -> Diagnostic:
    """Construct a high-fidelity Diagnostic from any exception, with macro inversion if available."""
    from alisp.contracts import ContractViolationException
    from alisp.repair.patch import CasMismatchError, SPathError

    if isinstance(exc, ContractViolationException):
        # Check if function call or violation can be mapped to original macro form
        orig_form, orig_loc = invert_source_location(exc.received)
        return Diagnostic(
            severity="error",
            type_name=":contract-violation",
            blame=exc.blame,
            function=exc.function_name,
            argument=exc.argument_index,
            parameter=exc.parameter_name,
            expected=exc.expected,
            received=exc.received,
            hint=f"Argument failed contract '{exc.expected}'. Check input values.",
            location=orig_loc,
            target_path=target_path,
            original_form=orig_form if orig_form is not exc.received else None,
        )

    if isinstance(exc, CasMismatchError):
        return Diagnostic(
            severity="error",
            type_name=":cas-mismatch",
            blame=":caller",
            expected=exc.expected,
            received=exc.actual,
            target_path=exc.target_path,
            hint="Expected original AST does not match actual node at target-path. Verify the node before patching.",
        )

    if isinstance(exc, SPathError):
        return Diagnostic(
            severity="error",
            type_name=":spath-error",
            blame=":caller",
            hint=str(exc),
            target_path=target_path,
        )

    # General fallback
    return Diagnostic(
        severity="error",
        type_name=":runtime-error",
        blame=":caller",
        hint=str(exc),
        target_path=target_path,
    )
