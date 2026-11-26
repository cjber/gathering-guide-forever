"""Export the world map node pins in media/Nodes from their originals in tools/pin_source.

The originals are AI-assisted art on a flat magenta (#FF00FF) background, made for this addon with no Blizzard art,
one file per picture under the name of the texture it becomes. This keys the magenta to alpha, takes its spill out of
the rim, crops to the art and centres it at its native aspect on a square canvas. Data/NodeArt.lua says which node
wears which.

    uv run --project tools --frozen --group dev python tools/export_nodes.py
"""

import sys
from pathlib import Path

from PIL import Image, ImageFilter

ROOT = Path(__file__).resolve().parent.parent
SOURCES = ROOT / "tools/pin_source"
TARGETS = ROOT / "media/Nodes"
# A power of two, with a clear pixel on every side of the art so filtering never reads past its edge.
SIZE = 64
ART = 62
# A pixel this close to pure magenta is background.
KEY_DISTANCE = 60
# How far in from the background, in source pixels, magenta blends into the art. Every picture has an outline thicker
# than this in one near-black, so a pixel in this band is that colour over magenta, and the interior (purple petals
# included) is never touched.
RIM = 3
OUTLINE = (14, 12, 30)


def spill(r: int, g: int, b: int) -> int:
    """How much magenta a colour holds: what its red and blue both have over its green."""
    return max(0, min(r, b) - g)


def key_magenta(image: Image.Image) -> Image.Image:
    """Magenta to alpha. A rim pixel becomes the outline colour, as opaque as the share of it that is not magenta."""
    rgb = image.convert("RGB")
    data = rgb.tobytes()
    pixels = [data[i : i + 3] for i in range(0, len(data), 3)]
    background = bytes(255 if max(255 - r, g, 255 - b) < KEY_DISTANCE else 0 for r, g, b in pixels)
    near = Image.frombytes("L", rgb.size, background).filter(ImageFilter.MaxFilter(2 * RIM + 1)).tobytes()
    clear = spill(255, 0, 255) - spill(*OUTLINE)
    keyed = bytearray()
    for (r, g, b), is_background, in_rim in zip(pixels, background, near, strict=True):
        if is_background:
            keyed += bytes((*OUTLINE, 0))
        elif in_rim:
            share = (spill(255, 0, 255) - spill(r, g, b)) / clear
            keyed += bytes((*OUTLINE, min(255, round(255 * share))))
        else:
            keyed += bytes((r, g, b, 255))
    return Image.frombytes("RGBA", rgb.size, bytes(keyed))


def export(source: Path, target: Path) -> None:
    art = key_magenta(Image.open(source))
    box = art.getchannel("A").point(lambda value: 255 if value > 40 else 0).getbbox()
    if box is None or box[0] == 0 or box[1] == 0 or box[2] == art.width or box[3] == art.height:
        raise ValueError(f"{source.name}: no art, or art cut off at the edge of its source")
    art = art.crop(box)
    scale = ART / max(art.size)  # one factor for both axes: the art keeps its shape
    art = art.resize((round(art.width * scale), round(art.height * scale)), Image.Resampling.LANCZOS)
    canvas = Image.new("RGBA", (SIZE, SIZE))
    canvas.paste(art, ((SIZE - art.width) // 2, (SIZE - art.height) // 2))
    canvas.save(target, compression=None)


def main() -> int:
    TARGETS.mkdir(parents=True, exist_ok=True)
    for source in sorted(SOURCES.glob("*.png")):
        export(source, TARGETS / f"{source.stem}.tga")
        print(f"wrote media/Nodes/{source.stem}.tga")
    return 0


if __name__ == "__main__":
    sys.exit(main())
