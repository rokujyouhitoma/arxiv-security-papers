"""tests.pylisp.test_logic: pylisp.logic miniKanren推論エンジンの包括的テストスイート (DSN-29)."""

import pytest

from pylisp.logic import (
    Goal,
    PersistentMap,
    Var,
    conde,
    eq,
    occurs_check,
    run,
    unify,
    walk,
    walk_all,
)


def test_var_basics() -> None:
    """論理変数 Var の基本属性、文字列表現、ハッシュ性を検証."""
    x = Var("x")
    y = Var("y")
    x2 = Var("x")

    assert str(x) == "?x"
    assert repr(x) == "?x"
    assert x == x2
    assert x != y
    assert hash(x) == hash(x2)
    assert hash(x) != hash(y)
    assert x != "x"


def test_persistent_map_immutability_and_sharing() -> None:
    """構造共有不変置換マップ PersistentMap のイミュータビリティと構造共有を検証."""
    empty_map = PersistentMap()
    assert len(empty_map) == 0
    assert not empty_map
    assert empty_map.get("a") is None
    assert empty_map.get("a", 999) == 999

    with pytest.raises(KeyError):
        _ = empty_map["a"]

    # 構造共有 set
    m1 = empty_map.set("a", 1)
    assert len(empty_map) == 0  # 元のマップは不変
    assert len(m1) == 1
    assert "a" in m1
    assert m1["a"] == 1

    # 分岐ノード生成
    m2 = m1.set("b", 2)
    m3 = m1.set("b", 3)

    assert m2["b"] == 2
    assert m3["b"] == 3
    assert m2["a"] == 1
    assert m3["a"] == 1
    assert len(m2) == 2
    assert len(m3) == 2

    # キーの上書き（シャドーイング）
    m4 = m2.set("a", 100)
    assert m4["a"] == 100
    assert m2["a"] == 1  # 親は不変
    assert len(m4) == 2

    # items, keys, values
    assert dict(m2.items()) == {"a": 1, "b": 2}
    assert set(m2.keys()) == {"a", "b"}
    assert set(m2.values()) == {1, 2}
    assert "PersistentMap(" in repr(m2)


def test_walk_chain_resolution() -> None:
    """walk 関数による多段束縛チェーンの辿り切りを検証."""
    x = Var("x")
    y = Var("y")
    z = Var("z")
    w = Var("w")

    s = PersistentMap().set(x, y).set(y, z).set(z, 42)

    assert walk(x, s) == 42
    assert walk(y, s) == 42
    assert walk(z, s) == 42
    assert walk(w, s) == w  # 未束縛変数は自分自身
    assert walk(100, s) == 100  # 定数はそのまま

    # walk_all による複合構造（タプル・リスト）内の再帰的解決
    assert walk_all((x, [y, (z, w)]), s) == (42, [42, (42, w)])


def test_occurs_check_prevents_recursion_crash() -> None:
    """循環参照項に対する occurs_check および RecursionError 防止 (CWE-674) を検証."""
    x = Var("x")
    y = Var("y")
    s = PersistentMap()

    # 自己言及: x in (x, 1)
    assert occurs_check(x, (x, 1), s) is True
    assert occurs_check(x, [1, [2, x]], s) is True
    assert occurs_check(x, (y, 1), s) is False

    # 間接循環: x -> y, y -> (x, 2)
    s2 = s.set(x, y)
    assert occurs_check(y, (x, 2), s2) is True

    # unify における循環参照検知と安全な None 返却 (クラッシュゼロ)
    result = unify(x, (x, 1), s)
    assert result is None

    result_nested = unify(x, [10, [20, x]], s)
    assert result_nested is None


def test_unify_primitives_and_nested_structures() -> None:
    """単一化コア unify の定数照合、変数束縛、タプル・リスト再帰単一化を検証."""
    x = Var("x")
    y = Var("y")
    z = Var("z")
    s = PersistentMap()

    # 定数同士
    assert unify(1, 1, s) == s
    assert unify(1, 2, s) is None
    assert unify("admin", "admin", s) == s
    assert unify("admin", "guest", s) is None

    # 変数束縛
    s1 = unify(x, "alice", s)
    assert s1 is not None
    assert walk(x, s1) == "alice"

    # 変数同士の結合
    s2 = unify(x, y, s)
    assert s2 is not None
    s3 = unify(y, "bob", s2)
    assert s3 is not None
    assert walk(x, s3) == "bob"
    assert walk(y, s3) == "bob"

    # ネストしたタプル
    t1 = (x, ("read", z))
    t2 = ("doc_1", ("read", "allow"))
    s4 = unify(t1, t2, s)
    assert s4 is not None
    assert walk(x, s4) == "doc_1"
    assert walk(z, s4) == "allow"

    # ネストしたリスト
    l1 = [x, 2, y]
    l2 = [1, 2, 3]
    s5 = unify(l1, l2, s)
    assert s5 is not None
    assert walk(x, s5) == 1
    assert walk(y, s5) == 3

    # 長さ不一致 / 型不一致
    assert unify((1, 2), (1, 2, 3), s) is None
    assert unify([1, 2], (1, 2), s) is None


def test_mini_kanren_run_and_eq() -> None:
    """run および eq による miniKanren ゴール充足推論を検証."""
    q = Var("q")
    x = Var("x")
    y = Var("y")

    # 単一解
    results = run(q, eq(q, "security_paper"))
    assert results == ["security_paper"]

    # 複数ゴール連立 (AND)
    results_and = run(
        q,
        eq(x, "NIST_SP_800"),
        eq(y, "53_Rev5"),
        eq(q, (x, y)),
    )
    assert results_and == [("NIST_SP_800", "53_Rev5")]

    # 充足不能制約 (解なし)
    results_none = run(q, eq(q, "active"), eq(q, "revoked"))
    assert results_none == []


def test_mini_kanren_conde_branching() -> None:
    """conde による OR 分岐・バックトラック複数解探索を検証."""
    q = Var("q")

    # 複数ロールのいずれかにマッチ
    results = run(
        q,
        conde(
            [eq(q, "admin")],
            [eq(q, "security_auditor")],
            [eq(q, "operator")],
        ),
    )
    assert results == ["admin", "security_auditor", "operator"]


def test_rbac_authorization_relational_reasoning() -> None:
    """認可ルール (RBAC) の関係プログラミング宣言的推論シナリオを検証."""

    # 定義: user_role(user, role)
    # alice -> admin, bob -> auditor, charlie -> viewer
    def user_role(u: Var | str, r: Var | str) -> Goal:
        return conde(
            [eq(u, "alice"), eq(r, "admin")],
            [eq(u, "bob"), eq(r, "auditor")],
            [eq(u, "charlie"), eq(r, "viewer")],
        )

    # 定義: role_permission(role, perm)
    # admin -> delete, admin -> write, auditor -> read, viewer -> read
    def role_permission(r: Var | str, p: Var | str) -> Goal:
        return conde(
            [eq(r, "admin"), eq(p, "delete")],
            [eq(r, "admin"), eq(p, "write")],
            [eq(r, "admin"), eq(p, "read")],
            [eq(r, "auditor"), eq(p, "audit")],
            [eq(r, "auditor"), eq(p, "read")],
            [eq(r, "viewer"), eq(p, "read")],
        )

    # 複合ルール: user_permission(user, perm) :- user_role(user, role), role_permission(role, perm)
    def user_permission(u: Var | str, p: Var | str) -> Goal:
        r = Var("r")
        return conde(
            [user_role(u, r), role_permission(r, p)],
        )

    # クエリ 1: alice が持つ全権限を推論
    perm = Var("perm")
    alice_perms = run(perm, user_permission("alice", perm))
    assert set(alice_perms) == {"delete", "write", "read"}

    # クエリ 2: 'read' 権限を持つ全ユーザーを推論 (双方向推論)
    usr = Var("usr")
    read_users = run(usr, user_permission(usr, "read"))
    assert set(read_users) == {"alice", "bob", "charlie"}

    # クエリ 3: 'delete' 権限を持つユーザーを推論
    del_users = run(usr, user_permission(usr, "delete"))
    assert del_users == ["alice"]
