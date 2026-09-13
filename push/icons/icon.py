#!/usr/bin/env python3
"""
Draw the Chain icon and write it out in every shape the
platforms want: PNG for Linux and for the window itself, .ico for Windows,
.icns for a macOS app bundle.

    python3 icon.py

Needs Pillow (pip install pillow). Only used when building; the program
itself carries a small copy of the icon inside it, so nothing here has to be
present at run time.
"""

import base64
import io
import os
import struct
import sys

from PIL import Image, ImageDraw, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))

# Steel and an electric arc through it. Almost every addon icon in the list is
# warm - gold, red, orange - so a cold palette is the one that gets noticed,
# and a chain is metal before it is anything else.
BG       = (14, 18, 28, 255)      # near black, with blue in it
EDGE     = (48, 60, 84, 255)
STEEL    = (108, 118, 134, 255)   # the link you have already been through
STEEL_HI = (186, 196, 212, 255)
STEEL_LO = (40, 45, 55, 255)
ARC      = (64, 206, 255, 255)    # the one you are in
ARC_HI   = (206, 244, 255, 255)
ARC_LO   = (14, 80, 116, 255)
ARC_GLOW = (40, 180, 255, 120)

# kept for the parts that still want a flat colour
TRACK = STEEL_LO
FILL = ARC
GOLD = ARC


def link(d, box, colour, width):
    """One chain link: a stadium outline."""
    r = int(min(box[2] - box[0], box[3] - box[1]) / 2)
    d.rounded_rectangle(box, radius=r, outline=colour, width=width)


def metal_link(size, box, angle, base, hi, lo, width, glow=None):
    """
    A link with a lit edge and a shaded one, so it reads as a solid object
    rather than an outline. Three passes of the same shape, offset by a
    fraction of the stroke: shadow down-right, body, highlight up-left.

    Drawn straight and then turned, because a rotated rounded rectangle is
    not something the drawing library will do for you.
    """
    layer = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    off = max(1, int(width * 0.22))
    link(d, [box[0] + off, box[1] + off, box[2] + off, box[3] + off], lo, width)
    link(d, box, base, width)
    link(d, [box[0] - off, box[1] - off, box[2] - off, box[3] - off], hi,
         max(1, int(width * 0.34)))
    turned = layer.rotate(angle, resample=Image.BICUBIC, center=(size / 2, size / 2))
    if not glow:
        return turned
    # the arc link throws a little light on what is around it
    g = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    link(ImageDraw.Draw(g), box, glow, int(width * 1.5))
    g = g.rotate(angle, resample=Image.BICUBIC, center=(size / 2, size / 2))
    g = g.filter(ImageFilter.GaussianBlur(size * 0.02))
    out = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    out.alpha_composite(g)
    out.alpha_composite(turned)
    return out


# where the two links sit, at 1024, before scaling
LINK_A = (140, 290, 640, 570)
LINK_B = (400, 455, 900, 735)
ANGLE = -28


def draw(size=1024):
    """
    Two links, one through the other, on a dark tile. At an angle because two
    links lying flat read as spectacles at any size worth caring about, and
    bold because the icon has to survive being twenty pixels wide in somebody
    else's addon list.

    Steel then arc: the run behind you and the one you are in.
    """
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    s = size / 1024.0

    d.rounded_rectangle([0, 0, size - 1, size - 1], radius=int(200 * s), fill=BG)
    d.rounded_rectangle([0, 0, size - 1, size - 1], radius=int(200 * s),
                        outline=EDGE, width=int(12 * s))

    w = int(86 * s)
    sc = lambda box: [int(v * s) for v in box]
    img.alpha_composite(metal_link(size, sc(LINK_A), ANGLE,
                                   STEEL, STEEL_HI, STEEL_LO, w))
    img.alpha_composite(metal_link(size, sc(LINK_B), ANGLE,
                                   ARC, ARC_HI, ARC_LO, w, ARC_GLOW))
    return img


def menubar(size=36):
    """
    The menu bar glyph: black on nothing, which is what macOS calls a template
    image. It draws it white on a dark menu bar and black on a light one, and
    it tints it blue when the menu is open - but only if every pixel is black
    with an alpha. Any colour in here and the icon comes out looking wrong on
    half the Macs in the world.
    """
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    s = size / 36.0
    K = (0, 0, 0, 255)

    # a bar, part filled: the same shape as the app icon, at a size where
    # nothing else survives
    x0, x1 = int(4 * s), int(32 * s)
    y0, y1 = int(15 * s), int(25 * s)
    r = int(4 * s)
    d.rounded_rectangle([x0, y0, x1, y1], radius=r, outline=K,
                        width=max(1, int(2 * s)))
    d.rounded_rectangle([x0 + int(3 * s), y0 + int(3 * s),
                         x0 + int((x1 - x0) * 0.58), y1 - int(3 * s)],
                        radius=int(2 * s), fill=K)
    # and the three runs above it
    ty = int(8 * s)
    for i in range(3):
        cx = x0 + int((x1 - x0) * (0.16 + i * 0.34))
        d.rounded_rectangle([cx - int(2.5 * s), ty, cx + int(2.5 * s), ty + int(4 * s)],
                            radius=int(1.5 * s), fill=K)
    return img


def minimap(size=64):
    """
    The minimap button's face: the two links and nothing else, on a disc dark
    enough to read against whatever the map underneath is doing. Seventeen
    pixels is what it actually gets.
    """
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    s = size / 64.0

    d.ellipse([0, 0, size - 1, size - 1], fill=(10, 13, 20, 255))
    d.ellipse([int(2 * s), int(2 * s), size - 1 - int(2 * s), size - 1 - int(2 * s)],
              outline=(58, 72, 98, 255), width=max(1, int(2 * s)))

    w = max(2, int(6 * s))
    a = [int(11 * s), int(21 * s), int(40 * s), int(38 * s)]
    b = [int(27 * s), int(31 * s), int(56 * s), int(48 * s)]
    img.alpha_composite(metal_link(size, a, ANGLE, STEEL, STEEL_HI, STEEL_LO, w))
    img.alpha_composite(metal_link(size, b, ANGLE, ARC, ARC_HI, ARC_LO, w))
    return img


def write_tga(img, path):
    """
    An uncompressed 32-bit TGA, which is what the game will load from an
    addon folder. Pillow can write TGA, but not reliably with the top-down
    flag the client expects, so the eighteen bytes are written by hand.
    """
    w, h = img.size
    header = struct.pack(
        "<BBBHHBHHHHBB",
        0,            # no id field
        0,            # no colour map
        2,            # uncompressed true-colour
        0, 0, 0,      # colour map spec
        0, 0,         # origin
        w, h,
        32,           # bits per pixel
        0x28          # 8 alpha bits, top-down
    )
    rows = []
    px = img.convert("RGBA").load()
    for y in range(h):
        row = bytearray()
        for x in range(w):
            r, g, b, a = px[x, y]
            row += bytes((b, g, r, a))     # TGA is BGRA
        rows.append(bytes(row))
    with open(path, "wb") as fh:
        fh.write(header + b"".join(rows))


def png_bytes(img, size):
    buf = io.BytesIO()
    img.resize((size, size), Image.LANCZOS).save(buf, format="PNG")
    return buf.getvalue()


def write_icns(img, path):
    """
    ICNS by hand: a header and one typed chunk per size, each holding a PNG.
    Pillow only writes .icns on macOS, and the build has to work anywhere.
    """
    # Every size macOS asks for, including the small ones. An icns missing a
    # size it wants is an icns macOS may quietly ignore in favour of the
    # generic document icon, which is how an app ends up looking like nothing
    # in the Dock with a perfectly good icon file inside it.
    types = [(b"icp4", 16), (b"icp5", 32), (b"icp6", 64),
             (b"ic07", 128), (b"ic08", 256), (b"ic09", 512), (b"ic10", 1024),
             (b"ic11", 32), (b"ic12", 64), (b"ic13", 256), (b"ic14", 512)]
    chunks = b""
    for kind, size in types:
        data = png_bytes(img, size)
        chunks += kind + struct.pack(">I", len(data) + 8) + data
    with open(path, "wb") as fh:
        fh.write(b"icns" + struct.pack(">I", len(chunks) + 8) + chunks)


def main():
    img = draw()
    img.resize((512, 512), Image.LANCZOS).save(os.path.join(HERE, "icon.png"))
    img.resize((256, 256), Image.LANCZOS).save(
        os.path.join(HERE, "icon.ico"),
        sizes=[(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)])
    write_icns(img, os.path.join(HERE, "icon.icns"))

    # a colour one for the notification banner
    img.resize((128, 128), Image.LANCZOS).save(os.path.join(HERE, "notify.png"))

    # two TGAs in the addon folder, because that is the one image format the
    # game will load from there: the minimap button's face, and the square
    # one the addon list shows next to the name
    # push/icons -> push -> the addon folder itself
    addon = os.path.dirname(os.path.dirname(HERE))
    mm = minimap(64)
    write_tga(mm, os.path.join(addon, "minimap.tga"))
    mm.save(os.path.join(HERE, "minimap.png"))
    write_tga(img.resize((64, 64), Image.LANCZOS), os.path.join(addon, "icon.tga"))

    # the copy that lives inside the program, so a plain script run still has
    # a proper icon in the dock or on the taskbar
    b64 = base64.b64encode(png_bytes(img, 128)).decode("ascii")
    lines = [b64[i:i + 76] for i in range(0, len(b64), 76)]
    with open(os.path.join(HERE, "iconbytes.py"), "w") as fh:
        fh.write('"""The icon, as PNG, so the program needs no files beside it."""\n\n')
        fh.write("ICON_PNG_BASE64 = (\n")
        for line in lines:
            fh.write('    "%s"\n' % line)
        fh.write(")\n")
    print("wrote icon.png, icon.ico, icon.icns and iconbytes.py")


if __name__ == "__main__":
    sys.exit(main())
