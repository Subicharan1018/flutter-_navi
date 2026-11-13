import sys
from PIL import Image, ImageOps
src, out = sys.argv[1], sys.argv[2]
glyph = Image.open(src).convert("RGBA")
# The app icon is a black glyph on transparent: make it white for a black tile.
alpha = glyph.split()[3]
white = Image.new("RGBA", glyph.size, (255, 255, 255, 255))
white.putalpha(alpha)
def tile(size, scale):
    bg = Image.new("RGBA", (size, size), (0, 0, 0, 255))
    g = int(size * scale)
    bg.alpha_composite(white.resize((g, g), Image.LANCZOS), ((size - g) // 2, (size - g) // 2))
    return bg.convert("RGB")
tile(192, 0.78).save(f"{out}/icons/Icon-192.png", optimize=True)
tile(512, 0.78).save(f"{out}/icons/Icon-512.png", optimize=True)
# Maskable: Android may crop to a circle, keep the glyph in the 80% safe zone.
tile(192, 0.58).save(f"{out}/icons/Icon-maskable-192.png", optimize=True)
tile(512, 0.58).save(f"{out}/icons/Icon-maskable-512.png", optimize=True)
tile(180, 0.72).save(f"{out}/icons/apple-touch-icon.png", optimize=True)
tile(48, 0.86).save(f"{out}/favicon.png", optimize=True)
