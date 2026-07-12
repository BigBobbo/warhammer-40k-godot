#!/usr/bin/env python3
"""Generate top-down unit sprites (Vassal-40k style) for the game.

Draws bird's-eye-view model art with Pillow at 4x supersampling and writes
PNGs into 40k/assets/unit_sprites/ where SpriteResolver picks them up by
unit name (e.g. "Custodian Guard" -> custodian_guard.png).

Design conventions (see 40k/docs/design_guidelines_2d_topdown.md):
- Canvas is square; the full canvas width maps 1:1 onto the model's base
  diameter in-game, so a figure drawn to fill the canvas fills its base.
  Weapons may overhang the inscribed base circle (Vassal look) but must
  stay inside the canvas.
- Figure faces "up" (north) at rotation 0, matching the tank sprites.
- Bold dark outlines and few, large shapes: sprites must read at 63px
  (40mm base) and survive 50% zoom-out.

Usage: python3 tools/sprites/generate_unit_sprites.py [--out DIR] [--preview DIR]
"""

import argparse
import math
import os

from PIL import Image, ImageDraw, ImageFilter

SS = 4          # supersample factor
SIZE = 512      # output sprite size (px)
CANVAS = SIZE * SS

# --- Auramite / Custodes palette -------------------------------------------
OUTLINE = (52, 38, 14, 255)
GOLD = (203, 161, 39, 255)
GOLD_LIGHT = (240, 208, 82, 255)
GOLD_DEEP = (142, 106, 24, 255)
GOLD_DARKEST = (100, 74, 18, 255)
RED = (168, 28, 32, 255)
RED_LIGHT = (212, 62, 52, 255)
RED_DARK = (110, 16, 20, 255)
STEEL = (210, 216, 224, 255)
STEEL_DARK = (146, 154, 165, 255)
BLACK_SUIT = (38, 32, 24, 255)


def S(v):
    """Scale a design-space (512) coordinate/length to supersampled space."""
    if isinstance(v, (tuple, list)):
        return type(v)(S(x) for x in v)
    return v * SS


class Layer:
    """RGBA layer with helpers for outlined, softly shaded shapes."""

    def __init__(self):
        self.img = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
        self.draw = ImageDraw.Draw(self.img)

    # -- masks ---------------------------------------------------------------
    def _shape_mask(self, painter):
        mask = Image.new("L", (CANVAS, CANVAS), 0)
        painter(ImageDraw.Draw(mask))
        return mask

    def _paste_color(self, color, mask):
        solid = Image.new("RGBA", (CANVAS, CANVAS), color)
        self.img.paste(solid, (0, 0), mask)

    # -- shaded primitives ----------------------------------------------------
    def shaded_ellipse(self, cx, cy, w, h, base, light, dark, outline=OUTLINE, ow=7):
        """Ellipse with top-left sheen, bottom-right shade crescent, outline."""
        cx, cy, w, h, ow = S(cx), S(cy), S(w), S(h), S(ow)
        bbox = [cx - w / 2, cy - h / 2, cx + w / 2, cy + h / 2]

        body = self._shape_mask(lambda d: d.ellipse(bbox, fill=255))
        if outline is not None:
            grown = [bbox[0] - ow, bbox[1] - ow, bbox[2] + ow, bbox[3] + ow]
            self._paste_color(outline, self._shape_mask(lambda d: d.ellipse(grown, fill=255)))
        self._paste_color(base, body)

        # light sheen: inset ellipse shifted up-left, clipped to body
        inset = 0.14
        off = (-w * 0.07, -h * 0.09)
        li = [bbox[0] + w * inset + off[0], bbox[1] + h * inset + off[1],
              bbox[2] - w * inset + off[0], bbox[3] - h * inset + off[1]]
        light_mask = self._shape_mask(lambda d: d.ellipse(li, fill=140))
        light_mask = Image.composite(light_mask, Image.new("L", (CANVAS, CANVAS), 0), body)
        self._paste_color(light, light_mask)

        # dark crescent: body minus body-shifted-up-left
        shift = (int(-w * 0.10), int(-h * 0.12))
        shifted = Image.new("L", (CANVAS, CANVAS), 0)
        shifted.paste(body, shift)
        from PIL import ImageChops
        crescent = ImageChops.subtract(body, shifted)
        crescent = crescent.point(lambda a: min(a, 120))
        self._paste_color(dark, crescent)

    def capsule(self, p1, p2, width, fill, outline=OUTLINE, ow=7, alpha=255):
        """Thick round-capped segment (limb / shaft / crest / soft sheen)."""
        p1, p2, width, ow = S(p1), S(p2), S(width), S(ow)

        def painter_factory(w, v):
            def painter(d):
                d.line([tuple(p1), tuple(p2)], fill=v, width=int(w))
                for p in (p1, p2):
                    d.ellipse([p[0] - w / 2, p[1] - w / 2, p[0] + w / 2, p[1] + w / 2], fill=v)
            return painter

        if outline is not None:
            self._paste_color(outline, self._shape_mask(painter_factory(width + ow * 2, 255)))
        self._paste_color(fill, self._shape_mask(painter_factory(width, alpha)))

    def soft_capsule(self, p1, p2, width, fill, alpha=120, blur=10, clip_painter=None):
        """Blurred-edge capsule for sheens/shades. Optionally clipped to a shape."""
        sp1, sp2, swidth = S(p1), S(p2), S(width)

        def painter(d):
            d.line([tuple(sp1), tuple(sp2)], fill=alpha, width=int(swidth))
            for p in (sp1, sp2):
                d.ellipse([p[0] - swidth / 2, p[1] - swidth / 2,
                           p[0] + swidth / 2, p[1] + swidth / 2], fill=alpha)

        mask = self._shape_mask(painter).filter(ImageFilter.GaussianBlur(S(blur)))
        if clip_painter is not None:
            clip = self._shape_mask(clip_painter)
            from PIL import ImageChops
            mask = ImageChops.multiply(mask, clip)
        self._paste_color(fill, mask)

    def polygon(self, pts, fill, outline=OUTLINE, ow=7):
        pts = [tuple(S(p)) for p in pts]
        ow = S(ow)
        if outline is not None:
            def grow(d):
                d.polygon(pts, fill=255)
                d.line(pts + [pts[0]], fill=255, width=int(ow * 2), joint="curve")
            self._paste_color(outline, self._shape_mask(grow))
        self._paste_color(fill, self._shape_mask(lambda d: d.polygon(pts, fill=255)))

    def line(self, p1, p2, width, fill):
        self.draw.line([tuple(S(p1)), tuple(S(p2))], fill=fill, width=int(S(width)))

    def dot(self, cx, cy, r, fill, outline=None, ow=5):
        self.shaded_ellipse(cx, cy, r * 2, r * 2, fill, fill, fill, outline, ow) \
            if outline else self.draw.ellipse(
                [S(cx - r), S(cy - r), S(cx + r), S(cy + r)], fill=fill)


def _along(p1, p2, t):
    return (p1[0] + (p2[0] - p1[0]) * t, p1[1] + (p2[1] - p1[1]) * t)


def _offset_perp(p1, p2, p, dist):
    dx, dy = p2[0] - p1[0], p2[1] - p1[1]
    L = math.hypot(dx, dy)
    nx, ny = -dy / L, dx / L
    return (p[0] + nx * dist, p[1] + ny * dist)


# ============================================================================
# Custodian Guard with Guardian Spear (40mm base)
# ============================================================================

def draw_custodian_guard():
    """Top-down Custodian Guard: huge gold pauldrons flanking a red-crested
    helm, guardian spear held diagonally past the model's right shoulder with
    an oversized halberd blade (up-right) and counterweight butt (down-left)."""
    lay = Layer()

    # --- soft drop shadow under the figure ---
    sh = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
    ImageDraw.Draw(sh).ellipse([S(88), S(140), S(430), S(420)], fill=(0, 0, 0, 70))
    sh = sh.filter(ImageFilter.GaussianBlur(S(9)))
    lay.img.alpha_composite(sh)

    # --- back tabard tail (red cloth hanging behind the legs) ---
    lay.polygon([(226, 330), (286, 330), (294, 424), (256, 458), (218, 424)],
                RED, OUTLINE, 6)
    lay.polygon([(240, 356), (272, 356), (277, 418), (256, 436), (235, 418)],
                RED_DARK, None)

    # --- torso: vertical armored mass below the shoulders ---
    lay.capsule((256, 258), (256, 330), 150, GOLD, OUTLINE, 7)
    lay.soft_capsule((256, 300), (256, 350), 90, GOLD_DEEP, alpha=100, blur=9)

    # --- shoulders: ONE unified wide mass whose round ends are the pauldrons ---
    shoulder_p1, shoulder_p2, shoulder_w = (166, 245), (346, 245), 172

    def shoulder_clip(d, p1=S(shoulder_p1), p2=S(shoulder_p2), w=S(shoulder_w)):
        d.line([tuple(p1), tuple(p2)], fill=255, width=int(w))
        for p in (p1, p2):
            d.ellipse([p[0] - w / 2, p[1] - w / 2, p[0] + w / 2, p[1] + w / 2], fill=255)

    lay.capsule(shoulder_p1, shoulder_p2, shoulder_w, GOLD, OUTLINE, 7)
    # smooth sheen along the top of the whole mass + shade along the bottom,
    # both soft-edged and clipped inside the shoulder shape
    lay.soft_capsule((160, 200), (352, 200), 60, GOLD_LIGHT, alpha=125, blur=11,
                     clip_painter=shoulder_clip)
    lay.soft_capsule((162, 300), (350, 300), 52, GOLD_DEEP, alpha=115, blur=11,
                     clip_painter=shoulder_clip)
    # seam lines where the pauldrons meet the torso
    lay.capsule((210, 184), (204, 304), 5, GOLD_DARKEST, None)
    lay.capsule((302, 184), (308, 304), 5, GOLD_DARKEST, None)
    # engraved trim band on each pauldron's outer edge
    lay.draw.arc([S(88), S(167), S(244), S(323)], 100, 260, fill=GOLD_DARKEST, width=S(6))
    lay.draw.arc([S(268), S(167), S(424), S(323)], 280, 80, fill=GOLD_DARKEST, width=S(6))

    # --- helmet: distinct dome between the pauldrons, red crest on top ---
    lay.shaded_ellipse(256, 234, 100, 102, GOLD, GOLD_LIGHT, GOLD_DEEP)
    lay.capsule((256, 194), (256, 280), 24, RED, OUTLINE, 6)          # crest base
    lay.capsule((256, 192), (256, 242), 10, RED_LIGHT, None)          # crest sheen

    # --- guardian spear: butt low-left, blade high-right over the shoulder ---
    shaft0 = (186, 468)
    neck = (414, 128)   # where the shaft meets the blade assembly
    tip = (476, 36)
    butt = (176, 483)

    lay.dot(butt[0], butt[1], 16, GOLD_DEEP)                          # counterweight
    lay.capsule(butt, shaft0, 20, GOLD_DEEP)
    lay.capsule(shaft0, neck, 14, GOLD, OUTLINE, 6)                   # shaft
    lay.line(_along(shaft0, neck, 0.08), _along(shaft0, neck, 0.5), 4, GOLD_LIGHT)

    # bolter housing straddling the shaft just below the blade (built-in gun)
    lay.capsule(_along(shaft0, neck, 0.82), _along(shaft0, neck, 0.93), 28, GOLD_DEEP, OUTLINE, 6)
    mz = _along(shaft0, neck, 0.945)
    lay.dot(mz[0], mz[1], 6, BLACK_SUIT)

    # halberd blade: broad leaf shape, steel with a dark center ridge
    bw = 38   # half-width of blade at its widest
    base_l = _offset_perp(neck, tip, neck, -bw)
    base_r = _offset_perp(neck, tip, neck, bw)
    mid_l = _offset_perp(neck, tip, _along(neck, tip, 0.40), -bw * 0.86)
    mid_r = _offset_perp(neck, tip, _along(neck, tip, 0.40), bw * 0.86)
    lay.polygon([base_l, mid_l, tip, mid_r, base_r], STEEL, OUTLINE, 7)
    lay.line(_along(neck, tip, 0.05), _along(neck, tip, 0.9), 6, STEEL_DARK)
    # gold collar where blade meets shaft
    c1 = _offset_perp(neck, tip, neck, -18)
    c2 = _offset_perp(neck, tip, neck, 18)
    lay.capsule(c1, c2, 13, GOLD, OUTLINE, 6)

    # --- forearms + hands gripping the shaft ---
    lower_grip = _along(shaft0, neck, 0.24)
    upper_grip = _along(shaft0, neck, 0.55)
    lay.capsule((202, 348), lower_grip, 32, GOLD, OUTLINE, 6)         # left forearm
    lay.capsule((346, 302), upper_grip, 32, GOLD, OUTLINE, 6)         # right forearm
    lay.shaded_ellipse(lower_grip[0], lower_grip[1], 48, 48, GOLD, GOLD_LIGHT, GOLD_DEEP, OUTLINE, 6)
    lay.shaded_ellipse(upper_grip[0], upper_grip[1], 48, 48, GOLD, GOLD_LIGHT, GOLD_DEEP, OUTLINE, 6)

    return lay.img


SPRITES = {
    # filename (SpriteResolver key)  ->  draw function
    "custodian_guard": draw_custodian_guard,
}


def render(name, fn):
    img = fn().resize((SIZE, SIZE), Image.LANCZOS)
    return img


def make_preview(sprite, path):
    """Contact sheet: sprite on token-like base circles at game scales."""
    scales = [(63, "40mm @ 1x"), (126, "@ 2x"), (252, "@ 4x")]
    pad = 24
    W = sum(s for s, _ in scales) + pad * (len(scales) + 1)
    H = max(s for s, _ in scales) + pad * 2 + 40
    for bg, base_col, fname in [
        ((34, 38, 30, 255), (96, 78, 26, 255), path + "_gold.png"),
        ((34, 38, 30, 255), (70, 74, 82, 255), path + "_slate.png"),
    ]:
        sheet = Image.new("RGBA", (W, H), bg)
        d = ImageDraw.Draw(sheet)
        x = pad
        for s, label in scales:
            cy = pad + max(sc for sc, _ in scales) // 2
            r = s // 2
            d.ellipse([x, cy - r, x + s, cy + r], fill=base_col,
                      outline=(20, 18, 12, 255), width=max(1, s // 32))
            small = sprite.resize((s, s), Image.LANCZOS)
            sheet.alpha_composite(small, (x, cy - r))
            d.text((x, cy + r + 8), label, fill=(220, 220, 210, 255))
            x += s + pad
        sheet.save(fname)


def main():
    ap = argparse.ArgumentParser()
    root = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
    ap.add_argument("--out", default=os.path.join(root, "40k", "assets", "unit_sprites"))
    ap.add_argument("--preview", default=None, help="also write preview contact sheets here")
    args = ap.parse_args()

    os.makedirs(args.out, exist_ok=True)
    for name, fn in SPRITES.items():
        img = render(name, fn)
        out_path = os.path.join(args.out, name + ".png")
        img.save(out_path)
        print("wrote", out_path)
        if args.preview:
            os.makedirs(args.preview, exist_ok=True)
            make_preview(img, os.path.join(args.preview, name))
            print("wrote previews for", name)


if __name__ == "__main__":
    main()
