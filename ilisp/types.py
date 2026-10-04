"""ILISP Core Data Types and Representation Specification.

This module defines the foundational AST and runtime data types for Kernel ILISP
adhering to R7RS-small Scheme semantics and Python zero-copy interop.
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import Any, Callable, Iterator, List, Optional, Sequence, Union


@dataclass(frozen=True)
class SourceLocation:
    """Source map location recording line, column, and file origin."""

    file: str
    line: int
    col: int

    def __str__(self) -> str:
        return f"{self.file}:{self.line}:{self.col}"


class Symbol:
    """Interned Symbol for Lisp identifiers."""

    _table: dict[str, Symbol] = {}

    def __init__(self, name: str) -> None:
        self.name: str = name

    @classmethod
    def intern(cls, name: str) -> Symbol:
        """Retrieve or create a globally unique interned Symbol."""
        if name not in cls._table:
            cls._table[name] = cls(name)
        return cls._table[name]

    def __repr__(self) -> str:
        return self.name

    def __str__(self) -> str:
        return self.name

    def __eq__(self, other: object) -> bool:
        if isinstance(other, Symbol):
            return self.name == other.name
        return False

    def __hash__(self) -> int:
        return hash(self.name)


class NilType:
    """Singleton representing the empty list '()."""

    _instance: Optional[NilType] = None

    def __new__(cls) -> NilType:
        if cls._instance is None:
            cls._instance = super().__new__(cls)
        return cls._instance

    def __repr__(self) -> str:
        return "()"

    def __str__(self) -> str:
        return "()"

    def __bool__(self) -> bool:
        # In Scheme, the empty list is truthy!
        return True

    def __len__(self) -> int:
        return 0

    def __iter__(self) -> Iterator[Any]:
        return iter(())


NIL = NilType()


class Cell:
    """Mutable box for lexical variables mutated by set!."""

    __slots__ = ("value",)

    def __init__(self, value: Any) -> None:
        self.value: Any = value

    def get(self) -> Any:
        return self.value

    def set(self, new_val: Any) -> Any:
        self.value = new_val
        return new_val

    def __repr__(self) -> str:
        return f"#<cell {self.value!r}>"


class Cons:
    """Cons cell representing an immutable or mutable pair in Lisp."""

    __slots__ = ("car", "cdr", "loc")

    def __init__(
        self, car: Any, cdr: Any, loc: Optional[SourceLocation] = None
    ) -> None:
        self.car: Any = car
        self.cdr: Any = cdr
        self.loc: Optional[SourceLocation] = loc

    def __repr__(self) -> str:
        elements: List[str] = []
        curr: Any = self
        while isinstance(curr, Cons):
            elements.append(repr(curr.car))
            curr = curr.cdr
        if curr is not NIL and not isinstance(curr, SequenceView):
            return f"({' '.join(elements)} . {curr!r})"
        if isinstance(curr, SequenceView):
            for item in curr:
                elements.append(repr(item))
        return f"({' '.join(elements)})"

    def __iter__(self) -> Iterator[Any]:
        curr: Any = self
        while isinstance(curr, Cons):
            yield curr.car
            curr = curr.cdr
        if isinstance(curr, SequenceView):
            yield from curr
        elif curr is not NIL:
            raise ValueError(f"Cannot iterate improper list ending with {curr!r}")

    def __eq__(self, other: object) -> bool:
        if isinstance(other, Cons):
            return bool(self.car == other.car and self.cdr == other.cdr)
        return False


class SequenceView:
    """O(1) lazy view over Python sequences (list/tuple) for zero-copy Scheme interop."""

    __slots__ = ("seq", "offset")

    def __init__(self, seq: Sequence[Any], offset: int = 0) -> None:
        self.seq: Sequence[Any] = seq
        self.offset: int = offset

    @property
    def car(self) -> Any:
        if self.offset >= len(self.seq):
            raise IndexError("car on empty SequenceView")
        return self.seq[self.offset]

    @property
    def cdr(self) -> Any:
        if self.offset + 1 >= len(self.seq):
            return NIL
        return SequenceView(self.seq, self.offset + 1)

    def __bool__(self) -> bool:
        return True

    def __len__(self) -> int:
        remaining = len(self.seq) - self.offset
        return max(0, remaining)

    def __iter__(self) -> Iterator[Any]:
        for i in range(self.offset, len(self.seq)):
            yield self.seq[i]

    def __repr__(self) -> str:
        elements = [repr(x) for x in self]
        return f"({' '.join(elements)})"


# Core Lisp Value type union
LispVal = Union[
    int,
    float,
    str,
    bool,
    Symbol,
    NilType,
    Cons,
    SequenceView,
    Cell,
    "Procedure",
    "Primitive",
]


class Procedure:
    """User-defined Scheme closure."""

    def __init__(
        self,
        params: Union[Symbol, List[Symbol]],
        body: List[Any],
        env: Any,
        is_macro: bool = False,
        rest_param: Optional[Symbol] = None,
        name: Optional[str] = None,
    ) -> None:
        self.params: Union[Symbol, List[Symbol]] = params
        self.body: List[Any] = body
        self.env: Any = env
        self.is_macro: bool = is_macro
        self.rest_param: Optional[Symbol] = rest_param
        self.name: Optional[str] = name

    def __call__(self, *args: Any) -> Any:
        from ilisp.evaluator import _apply_procedure

        return _apply_procedure(self, list(args))

    def __repr__(self) -> str:
        kind = "macro" if self.is_macro else "procedure"
        name_str = f" {self.name}" if self.name else ""
        return f"#<{kind}{name_str}>"


class Primitive:
    """Built-in primitive procedure wrapper."""

    def __init__(self, name: str, fn: Callable[..., Any]) -> None:
        self.name: str = name
        self.fn: Callable[..., Any] = fn

    def __call__(self, *args: Any) -> Any:
        return self.fn(*args)

    def __repr__(self) -> str:
        return f"#<primitive-procedure {self.name}>"


def is_pair(val: Any) -> bool:
    """Check if a value is a Cons pair or non-empty SequenceView."""
    if isinstance(val, Cons):
        return True
    if isinstance(val, SequenceView) and len(val) > 0:
        return True
    return False


def is_null(val: Any) -> bool:
    """Check if a value is the empty list NIL or empty SequenceView."""
    return val is NIL or (isinstance(val, SequenceView) and len(val) == 0)


def car(pair: Any) -> Any:
    """Return the car of a Cons cell or SequenceView."""
    if isinstance(pair, Cons):
        return pair.car
    if isinstance(pair, SequenceView):
        return pair.car
    raise TypeError(f"car expected pair, got {type(pair).__name__}: {pair!r}")


def cdr(pair: Any) -> Any:
    """Return the cdr of a Cons cell or SequenceView."""
    if isinstance(pair, Cons):
        return pair.cdr
    if isinstance(pair, SequenceView):
        return pair.cdr
    raise TypeError(f"cdr expected pair, got {type(pair).__name__}: {pair!r}")


def to_lisp_list(elements: Sequence[Any], loc: Optional[SourceLocation] = None) -> Any:
    """Convert a Python sequence to a Scheme Cons list."""
    result: Any = NIL
    for item in reversed(elements):
        result = Cons(item, result, loc=loc)
    return result


def to_py_list(val: Any) -> List[Any]:
    """Convert a Scheme proper list or SequenceView to a Python list."""
    res: List[Any] = []
    curr = val
    while is_pair(curr):
        res.append(car(curr))
        curr = cdr(curr)
    if not is_null(curr):
        raise TypeError(f"to_py_list expected proper list, got improper: {val!r}")
    return res
