"""pylisp.logic: 構造共有＆Occurs Check付きminiKanren推論エンジン (DSN-29).

Clojureの core.logic および Schemeの miniKanren を基盤とする関係プログラミングエンジン。
認可ルール解決（RBAC/ABAC）やセキュリティ制約充足の宣言的解決を担う。

- 循環参照項の単一化時に CPython の RecursionError クラッシュを完全に防止する Occurs Check を標準内蔵。
- 探索ノード分岐での辞書コピー（{**s}）を全廃し、Pure Python による構造共有不変置換マップ（PersistentMap）を直結。
"""

from __future__ import annotations

from collections.abc import Generator, Sequence
from typing import Any, Callable, Optional


class Var:
    """miniKanren の論理変数シンボル."""

    __slots__ = ("name",)

    def __init__(self, name: str) -> None:
        self.name: str = name

    def __repr__(self) -> str:
        return f"?{self.name}"

    def __eq__(self, other: object) -> bool:
        if self is other:
            return True
        if isinstance(other, Var):
            return self.name == other.name
        return False

    def __hash__(self) -> int:
        return hash(self.name)


class PersistentMap:
    """構造共有（Structural Sharing）に基づく不変置換マップ.

    探索分岐時の dict.copy() によるメモリ・GC負荷を排除し、
    親ノードへの参照リンクを保持することで O(1) で新しい置換を作成する。
    """

    __slots__ = ("_key", "_value", "_parent", "_size")

    def __init__(
        self,
        key: Any = None,
        value: Any = None,
        parent: Optional[PersistentMap] = None,
    ) -> None:
        self._key: Any = key
        self._value: Any = value
        self._parent: Optional[PersistentMap] = parent
        if parent is None:
            self._size: int = 1 if key is not None else 0
        else:
            self._size = parent._size if key in parent else parent._size + 1

    def set(self, key: Any, value: Any) -> PersistentMap:
        """キーと値を束縛した新しい PersistentMap を生成して返却する (構造共有 O(1))."""
        return PersistentMap(key, value, self)

    def __contains__(self, key: Any) -> bool:
        curr: Optional[PersistentMap] = self
        while curr is not None and curr._key is not None:
            if curr._key == key:
                return True
            curr = curr._parent
        return False

    def __getitem__(self, key: Any) -> Any:
        curr: Optional[PersistentMap] = self
        while curr is not None and curr._key is not None:
            if curr._key == key:
                return curr._value
            curr = curr._parent
        raise KeyError(key)

    def get(self, key: Any, default: Any = None) -> Any:
        """キーに対応する値を探索し、存在しなければ default を返却する."""
        curr: Optional[PersistentMap] = self
        while curr is not None and curr._key is not None:
            if curr._key == key:
                return curr._value
            curr = curr._parent
        return default

    def __len__(self) -> int:
        return self._size

    def __bool__(self) -> bool:
        return self._size > 0

    def items(self) -> list[tuple[Any, Any]]:
        """最新のキーと値のペア一覧を返却する."""
        seen: set[Any] = set()
        res: list[tuple[Any, Any]] = []
        curr: Optional[PersistentMap] = self
        while curr is not None and curr._key is not None:
            if curr._key not in seen:
                seen.add(curr._key)
                res.append((curr._key, curr._value))
            curr = curr._parent
        return res

    def keys(self) -> list[Any]:
        """最新のキー一覧を返却する."""
        return [k for k, _ in self.items()]

    def values(self) -> list[Any]:
        """最新の値一覧を返却する."""
        return [v for _, v in self.items()]

    def __repr__(self) -> str:
        items_repr = ", ".join(f"{k!r}: {v!r}" for k, v in self.items())
        return f"PersistentMap({{{items_repr}}})"


Subst = PersistentMap
Goal = Callable[[PersistentMap], Generator[PersistentMap, None, None]]


def walk(u: Any, s: PersistentMap) -> Any:
    """置換マップ s 内を変数束縛に従って再帰走査し、最終的な値または未束縛変数を返却する."""
    while isinstance(u, Var) and u in s:
        u = s[u]
    return u


def walk_all(u: Any, s: PersistentMap) -> Any:
    """項の中のすべての論理変数を再帰的に walk して完全具体化する (deep walk / reify)."""
    u = walk(u, s)
    if isinstance(u, tuple):
        return tuple(walk_all(x, s) for x in u)
    if isinstance(u, list):
        return [walk_all(x, s) for x in u]
    return u


def occurs_check(v: Var, term: Any, s: PersistentMap) -> bool:
    """term の中に論理変数 v が循環して含まれていないかを検証する (CWE-674 RecursionError 防止)."""
    term = walk(term, s)
    if term == v:
        return True
    if isinstance(term, (tuple, list)):
        return any(occurs_check(v, x, s) for x in term)
    return False


def _bind(var: Var, term: Any, s: PersistentMap) -> Optional[PersistentMap]:
    """Occurs Check 付き変数束縛ヘルパー (CWE-674 RecursionError 防止)."""
    return None if occurs_check(var, term, s) else s.set(var, term)


def _is_unifiable_seq(u: Any, v: Any) -> bool:
    """u と v が同型かつ等長のシーケンスであるか判定するヘルパー."""
    return type(u) is type(v) and isinstance(u, (tuple, list)) and len(u) == len(v)


def _unify_seq(us: Any, vs: Any, s: PersistentMap) -> Optional[PersistentMap]:
    """シーケンス各要素を順に単一化するヘルパー."""
    curr_s = s
    for x, y in zip(us, vs):
        next_s = unify(x, y, curr_s)
        if next_s is None:
            return None
        curr_s = next_s
    return curr_s


def unify(u: Any, v: Any, s: PersistentMap) -> Optional[PersistentMap]:
    """構造共有置換マップ & Occurs Check 付き単一化コア (Unification Core).

    - 循環参照検知時は探索失敗 (None) を即座に返し、RecursionError クラッシュを防止。
    - 辞書コピーを行わず、s.set() による構造共有更新を実施。
    """
    u = walk(u, s)
    v = walk(v, s)
    if u == v:
        return s
    if isinstance(u, Var):
        return _bind(u, v, s)
    if isinstance(v, Var):
        return _bind(v, u, s)
    if _is_unifiable_seq(u, v):
        return _unify_seq(u, v, s)
    return None


def eq(u: Any, v: Any) -> Goal:
    """等値ゴール生成器 (miniKanren の == 相当)."""

    def _goal(s: PersistentMap) -> Generator[PersistentMap, None, None]:
        s_new = unify(u, v, s)
        if s_new is not None:
            yield s_new

    return _goal


def conde(*clauses: Sequence[Goal]) -> Goal:
    """OR分岐および連立ANDゴール生成器 (miniKanren の conde 相当)."""

    def _goal(s: PersistentMap) -> Generator[PersistentMap, None, None]:
        for clause in clauses:

            def run_clause(
                gls: Sequence[Goal], current_s: PersistentMap
            ) -> Generator[PersistentMap, None, None]:
                if not gls:
                    yield current_s
                    return
                for next_s in gls[0](current_s):
                    yield from run_clause(gls[1:], next_s)

            yield from run_clause(clause, s)

    return _goal


def run(q: Var, *goals: Goal) -> list[Any]:
    """論理変数 q に対する解を探索し、すべての有効な解をリストで返却する."""

    def run_all(
        gls: tuple[Goal, ...], s: PersistentMap
    ) -> Generator[PersistentMap, None, None]:
        if not gls:
            yield s
            return
        for next_s in gls[0](s):
            yield from run_all(gls[1:], next_s)

    results: list[Any] = []
    initial_subst = PersistentMap()
    for s in run_all(goals, initial_subst):
        results.append(walk_all(q, s))
    return results
