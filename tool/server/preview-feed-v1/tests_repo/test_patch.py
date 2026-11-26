"""Repo-only: the patch applies once, a second run changes nothing, a foreign server.py is refused untouched."""
import importlib.util
from pathlib import Path

spec = importlib.util.spec_from_file_location("pf_patch", Path(__file__).parent.parent / "patch_proxy.py")
patch = importlib.util.module_from_spec(spec)
spec.loader.exec_module(patch)

BASE = "x = 1\nregister_weekly_routes(app, require_auth, lambda: _v3_engine())\ny = 2\n"


def test_patch_is_idempotent(tmp_path):
    (tmp_path / "server.py").write_text(BASE, encoding="utf-8")
    assert patch.main(str(tmp_path)) == 0
    once = (tmp_path / "server.py").read_text(encoding="utf-8")
    assert "register_preview_feed_routes(app, require_auth, _pf_access.has_access)" in once
    assert once.index("register_weekly_routes") < once.index("register_preview_feed_routes") < once.index("y = 2")
    assert patch.main(str(tmp_path)) == 0
    assert (tmp_path / "server.py").read_text(encoding="utf-8") == once


def test_foreign_file_is_refused_untouched(tmp_path):
    (tmp_path / "server.py").write_text("something else\n", encoding="utf-8")
    assert patch.main(str(tmp_path)) == 2
    assert (tmp_path / "server.py").read_text(encoding="utf-8") == "something else\n"
