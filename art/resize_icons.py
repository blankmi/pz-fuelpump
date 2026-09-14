#!/usr/bin/env python3
"""Regenerate the shipped item icons from the 256px sources in this folder.

Usage:  python3 art/resize_icons.py [size]     # default 64

Plain RGBA resizing bleeds the colour of fully transparent pixels into the edges,
which shows up as a dark halo at icon sizes. The colour channels are therefore
premultiplied by alpha before filtering and divided out afterwards.
"""
import sys
from PIL import Image, ImageChops

TEXTURES = "Contents/mods/PortableFuelPump/common/media/textures"
ICONS = ("Item_PortableFuelPump", "Item_SmallPumpAssembly")


def downscale(src, dst, size):
    r, g, b, a = Image.open(src).convert("RGBA").split()
    premultiplied = Image.merge("RGBA", (
        ImageChops.multiply(r, a),
        ImageChops.multiply(g, a),
        ImageChops.multiply(b, a),
        a,
    ))

    small = premultiplied.resize((size, size), Image.LANCZOS)
    channels = small.split()
    colour, alpha = [c.load() for c in channels[:3]], channels[3].load()

    for y in range(size):
        for x in range(size):
            value = alpha[x, y]
            for channel in colour:
                channel[x, y] = 0 if value == 0 else min(255, int(channel[x, y] * 255 / value + 0.5))

    Image.merge("RGBA", channels).save(dst, optimize=True)
    print(f"{dst}  {size}x{size}")


def main():
    size = int(sys.argv[1]) if len(sys.argv) > 1 else 64
    for name in ICONS:
        downscale(f"art/{name}_256.png", f"{TEXTURES}/{name}.png", size)


if __name__ == "__main__":
    main()
