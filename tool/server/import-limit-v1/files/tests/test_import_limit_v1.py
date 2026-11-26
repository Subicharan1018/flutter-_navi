"""import-limit-v1: the per-user import limit is a setting; the default is unchanged."""
from tgfetch import exportify as ex


def test_the_limit_is_the_setting_and_twenty_without_one():
    import os
    assert ex.MAX_IMPORTS == int(os.getenv("EXPORTIFY_MAX_IMPORTS", "20"))   # the live .env sets 200


def test_prune_old_keeps_the_newest_up_to_the_limit(conn, monkeypatch):
    ex.ensure_schema(conn)
    monkeypatch.setattr(ex, "MAX_IMPORTS", 3)
    for n in range(5):
        conn.execute("INSERT INTO exportify_imports (user, name, created_at, total_rows, skipped_rows, dupes) "
                     "VALUES ('vijay', ?, ?, 1, 0, 0)", (f"p{n}", float(n)))
    ex.prune_old(conn, "vijay")
    names = [r[0] for r in conn.execute("SELECT name FROM exportify_imports WHERE user='vijay' ORDER BY id")]
    assert names == ["p2", "p3", "p4"]
