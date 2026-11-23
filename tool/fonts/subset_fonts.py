"""Subsets the bundled Inter fonts: Latin (with Vietnamese and extensions),
Greek, Cyrillic, punctuation, currency, arrows and maths. Everything else
(Tamil, CJK, emoji...) is not in Inter anyway and falls back to the system.

    python tool/fonts/subset_fonts.py

Reads tool/fonts/src/*.ttf, writes assets/fonts/*.ttf. Needs: pip install fonttools.
Keeps kerning, ligatures, tabular figures and mark positioning.
"""
import pathlib
from fontTools import subset

ROOT = pathlib.Path(__file__).resolve().parents[2]
SRC = ROOT / "tool" / "fonts" / "src"
OUT = ROOT / "assets" / "fonts"
UNICODES = (
    "U+0000-024F,U+0250-02AF,U+02B0-02FF,U+0300-036F,U+0370-03FF,U+0400-052F,"
    "U+1E00-1EFF,U+1F00-1FFF,U+2000-206F,U+2070-209F,U+20A0-20CF,U+2100-214F,"
    "U+2150-218F,U+2190-21FF,U+2200-22FF,U+2300-23FF,U+25A0-25FF,U+2600-26FF,"
    "U+FB00-FB06,U+FEFF,U+FFFD"
)
FEATURES = ["kern", "liga", "calt", "tnum", "ccmp", "locl", "mark", "mkmk", "case", "zero", "ss01", "cv11"]

for ttf in sorted(SRC.glob("*.ttf")):
    opts = subset.Options()
    opts.layout_features = FEATURES
    opts.glyph_names = False
    opts.notdef_outline = True
    opts.name_IDs = ["*"]
    opts.hinting = False
    font = subset.load_font(str(ttf), opts)
    s = subset.Subsetter(opts)
    s.populate(unicodes=subset.parse_unicodes(UNICODES))
    s.subset(font)
    dest = OUT / ttf.name
    subset.save_font(font, str(dest), opts)
    print(f"{ttf.name}: {ttf.stat().st_size // 1024} KB -> {dest.stat().st_size // 1024} KB")
