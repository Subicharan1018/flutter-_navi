"""channel-ids-v1: numeric channel ids reach Telethon as ints, names stay names."""
import pytest

from tgfetch import channel_fallback as cf


@pytest.mark.parametrize("raw,want", [
    ("-1001197115414", -1001197115414), (" -1001270955977 ", -1001270955977), ("123", 123),
    ("FLACsongs", "FLACsongs"), ("retroaudios", "retroaudios"), ("tamil2k10", "tamil2k10"),
])
def test_ref(raw, want):
    assert cf.ref(raw) == want


def test_a_mixed_setting_is_read_in_order(monkeypatch):
    monkeypatch.setenv("CHANNEL_FALLBACK_CHANNELS", "-1001197115414, @FLACsongs ,-1001270955977")
    assert cf.channels() == ["-1001197115414", "FLACsongs", "-1001270955977"]
    assert [cf.ref(c) for c in cf.channels()] == [-1001197115414, "FLACsongs", -1001270955977]
