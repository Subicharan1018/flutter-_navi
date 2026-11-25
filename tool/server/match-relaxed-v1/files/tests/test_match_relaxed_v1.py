"""match-relaxed-v1: a (nearly) exact title is enough when the artist cannot be compared; never for another recording."""
from tgfetch import channels_first as chf


def post(title="", performer="", fname="", dur=0, mime="audio/flac", text=""):
    return {"id": 1, "mime": mime, "size": 30_000_000, "title": title, "performer": performer, "fname": fname,
            "dur": dur, "text": text}


def song(title, dur=None, artist="X"):
    return {"title": title, "artist": artist, "duration_s": dur}


def test_same_length_is_the_same_recording_whoever_the_post_names():
    p = post("Vinmeen (From \"Thegidi\")", "Abhay Jodhpurkar & Saindhavi", "Vinmeen (From Thegidi).flac", dur=262)
    assert chf.relaxed_match(song("Vinmeen", 263), [p]) is p
    p2 = post("Putham Puthu Kaalai", "S. Janki", "Putham Puthu Kaalai.flac", dur=273)
    assert chf.relaxed_match(song("Putham Puthu Kaalai", 273.5), [p2]) is p2


def test_a_different_length_is_another_recording():
    p = post("Thoovaanam", "Vijay Yesudas", "Thoovaanam.flac", dur=203)
    assert chf.relaxed_match(song("Thoovaanam", 265.5), [p]) is None


def test_a_post_with_no_artist_is_taken_for_a_two_word_title_only():
    bare = post("", "", "12. Kandhan Thiruneeraninthal.flac")
    assert chf.relaxed_match(song("Kandhan Thiruneeraninthal"), [bare]) is bare
    one = post("", "", "12. Thiththikkum.flac")
    assert chf.relaxed_match(song("Thiththikkum"), [one]) is None


def test_a_post_that_names_another_artist_with_an_unknown_length_is_refused():
    p = post("Nee Kavithaigala", "Pradeep Kumar", "35 - Nee Kavithaigala.flac")
    assert chf.relaxed_match(song("Nee Kavithaigala", None), [p]) is None


def test_remixes_other_formats_and_other_titles_are_refused():
    assert chf.relaxed_match(song("Machan Meesai", 270), [post("Machan Meesai Brazilian Remix", "P", "m.flac", dur=270)]) is None
    assert chf.relaxed_match(song("Akila Akila", 284), [post("Akila Akila", "V", "a.mp3", dur=284, mime="audio/mpeg")]) is None
    assert chf.relaxed_match(song("Akila Akila", 284), [post("Akila Akilaa Remastered Edition", "V", "x.flac", dur=284)]) is None
    assert chf.relaxed_match(song("", 284), [post("Akila Akila", "V", "a.flac", dur=284)]) is None
