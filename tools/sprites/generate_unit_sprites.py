#!/usr/bin/env python3
"""Generate top-down unit sprites (Vassal-40k style) for the game.

Draws bird's-eye-view model art with Pillow at 4x supersampling and writes
PNGs into 40k/assets/unit_sprites/ where SpriteResolver picks them up by
unit name (e.g. "Custodian Guard" -> custodian_guard.png).

Design conventions (see 40k/docs/design_guidelines_2d_topdown.md):
- The canvas maps 1:1 onto the model's base: square canvases for circular
  bases, and canvases with the base's aspect ratio for oval bases (the
  in-game fit is min(bounds/size) per axis, so a matching aspect fills the
  base). Weapons/rotors may overhang the inscribed base ellipse (Vassal
  look) but must stay inside the canvas.
- Figures face "up" (north) at rotation 0, matching the tank sprites and
  the tall oval bases (42x75mm bikes, 95x150mm wartrike).
- Bold dark outlines and few, large shapes: sprites must read at 63px
  (40mm base), 50px (32mm) and 39px (25mm), and survive 50% zoom-out.

Usage: python3 tools/sprites/generate_unit_sprites.py [--out DIR] [--preview DIR]
                                                      [--only name1,name2]
"""

import argparse
import math
import os

from PIL import Image, ImageChops, ImageDraw, ImageFilter

SS = 4          # supersample factor
BASE_SIZE = 512  # canvas size for a square (circular-base) sprite

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

# --- Ork palette -------------------------------------------------------------
ORK_OUTLINE = (30, 26, 18, 255)
SKIN = (86, 128, 44, 255)
SKIN_LIGHT = (120, 164, 70, 255)
SKIN_DARK = (56, 88, 28, 255)
ORK_RED = (163, 44, 30, 255)
ORK_RED_LIGHT = (198, 74, 51, 255)
ORK_RED_DARK = (110, 29, 20, 255)
METAL = (138, 133, 120, 255)
METAL_LIGHT = (176, 172, 159, 255)
METAL_DARK = (92, 88, 78, 255)
RUST = (122, 91, 58, 255)
LEATHER = (74, 61, 46, 255)
LEATHER_LIGHT = (100, 84, 64, 255)
TEEF = (216, 207, 176, 255)
ORK_YELLOW = (217, 168, 31, 255)
ORK_BLACK = (44, 40, 34, 255)
TIRE = (48, 44, 40, 255)
TIRE_LIGHT = (74, 69, 63, 255)

# --- Sisters of Silence (Prosecutors) palette --------------------------------
SIS_BLACK = (66, 64, 80, 255)
SIS_BLACK_LIGHT = (108, 106, 128, 255)
SIS_BLACK_DARK = (38, 37, 48, 255)


def S(v):
    """Scale a design-space coordinate/length to supersampled space."""
    if isinstance(v, (tuple, list)):
        return type(v)(S(x) for x in v)
    return v * SS


class Layer:
    """RGBA layer with helpers for outlined, softly shaded shapes."""

    def __init__(self, w=BASE_SIZE, h=BASE_SIZE):
        self.w, self.h = w, h
        self.img = Image.new("RGBA", (w * SS, h * SS), (0, 0, 0, 0))
        self.draw = ImageDraw.Draw(self.img)

    # -- masks ---------------------------------------------------------------
    def _shape_mask(self, painter):
        mask = Image.new("L", self.img.size, 0)
        painter(ImageDraw.Draw(mask))
        return mask

    def _paste_color(self, color, mask):
        solid = Image.new("RGBA", self.img.size, color)
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
        light_mask = Image.composite(light_mask, Image.new("L", self.img.size, 0), body)
        self._paste_color(light, light_mask)

        # dark crescent: body minus body-shifted-up-left
        shift = (int(-w * 0.10), int(-h * 0.12))
        shifted = Image.new("L", self.img.size, 0)
        shifted.paste(body, shift)
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
        if outline:
            self.shaded_ellipse(cx, cy, r * 2, r * 2, fill, fill, fill, outline, ow)
        else:
            self.draw.ellipse([S(cx - r), S(cy - r), S(cx + r), S(cy + r)], fill=fill)

    def arc(self, bbox, start, end, fill, width):
        self.draw.arc([S(v) for v in bbox], start, end, fill=fill, width=int(S(width)))

    def shadow(self, bbox, alpha=70, blur=9):
        sh = Image.new("RGBA", self.img.size, (0, 0, 0, 0))
        ImageDraw.Draw(sh).ellipse([S(v) for v in bbox], fill=(0, 0, 0, alpha))
        sh = sh.filter(ImageFilter.GaussianBlur(S(blur)))
        self.img.alpha_composite(sh)


def _along(p1, p2, t):
    return (p1[0] + (p2[0] - p1[0]) * t, p1[1] + (p2[1] - p1[1]) * t)


def _offset_perp(p1, p2, p, dist):
    dx, dy = p2[0] - p1[0], p2[1] - p1[1]
    L = math.hypot(dx, dy)
    nx, ny = -dy / L, dx / L
    return (p[0] + nx * dist, p[1] + ny * dist)


def rect_pts(cx, cy, w, h, angle_deg=0.0):
    """Corner points of a wxh rectangle centered on (cx,cy), rotated."""
    a = math.radians(angle_deg)
    ca, sa = math.cos(a), math.sin(a)
    pts = []
    for dx, dy in ((-w / 2, -h / 2), (w / 2, -h / 2), (w / 2, h / 2), (-w / 2, h / 2)):
        pts.append((cx + dx * ca - dy * sa, cy + dx * sa + dy * ca))
    return pts


# ============================================================================
# Shared figure rigs
# ============================================================================

def _humanoid(lay, cx, cy, scale, body, body_light, body_dark, head, head_light,
              head_dark, outline, seam=None, shoulder_w=1.0):
    """Generic top-down torso+shoulders+head. Returns key dims for callers.

    scale 1.0 ~= a 40mm-base heavy infantry figure on a 512 canvas.
    """
    sw = 180 * scale * shoulder_w   # shoulder half-span (capsule end distance)
    sh = 172 * scale                # shoulder capsule thickness
    # torso below
    lay.capsule((cx, cy + 13 * scale), (cx, cy + 85 * scale), 150 * scale, body, outline, 7)
    # unified shoulder mass
    p1, p2 = (cx - sw / 2, cy), (cx + sw / 2, cy)

    def clip(d, q1=S(p1), q2=S(p2), w=S(sh)):
        d.line([tuple(q1), tuple(q2)], fill=255, width=int(w))
        for p in (q1, q2):
            d.ellipse([p[0] - w / 2, p[1] - w / 2, p[0] + w / 2, p[1] + w / 2], fill=255)

    lay.capsule(p1, p2, sh, body, outline, 7)
    lay.soft_capsule((cx - sw / 2, cy - 45 * scale), (cx + sw / 2, cy - 45 * scale),
                     56 * scale, body_light, alpha=125, blur=11, clip_painter=clip)
    lay.soft_capsule((cx - sw / 2, cy + 55 * scale), (cx + sw / 2, cy + 55 * scale),
                     50 * scale, body_dark, alpha=115, blur=11, clip_painter=clip)
    if seam is not None:
        lay.capsule((cx - 46 * scale, cy - 61 * scale), (cx - 52 * scale, cy + 59 * scale), 5, seam, None)
        lay.capsule((cx + 46 * scale, cy - 61 * scale), (cx + 52 * scale, cy + 59 * scale), 5, seam, None)
    # head
    lay.shaded_ellipse(cx, cy - 11 * scale, 100 * scale, 102 * scale,
                       head, head_light, head_dark, outline, 7)
    return {"shoulder_half": sw / 2 + sh / 2, "head_r": 50 * scale}


# ============================================================================
# ADEPTUS CUSTODES / TALONS OF THE EMPEROR
# ============================================================================

def draw_custodian_guard():
    """Top-down Custodian Guard: huge gold pauldrons flanking a red-crested
    helm, guardian spear held diagonally past the model's right shoulder with
    an oversized halberd blade (up-right) and counterweight butt (down-left)."""
    lay = Layer()
    lay.shadow([88, 140, 430, 420])

    # --- back tabard tail (red cloth hanging behind the legs) ---
    lay.polygon([(226, 330), (286, 330), (294, 424), (256, 458), (218, 424)],
                RED, OUTLINE, 6)
    lay.polygon([(240, 352), (272, 352), (277, 418), (256, 436), (234, 418)],
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
    lay.soft_capsule((160, 200), (352, 200), 60, GOLD_LIGHT, alpha=125, blur=11,
                     clip_painter=shoulder_clip)
    lay.soft_capsule((162, 300), (350, 300), 52, GOLD_DEEP, alpha=115, blur=11,
                     clip_painter=shoulder_clip)
    lay.capsule((210, 184), (204, 304), 5, GOLD_DARKEST, None)
    lay.capsule((302, 184), (308, 304), 5, GOLD_DARKEST, None)
    lay.arc([88, 167, 244, 323], 100, 260, GOLD_DARKEST, 6)
    lay.arc([268, 167, 424, 323], 280, 80, GOLD_DARKEST, 6)

    # --- helmet: distinct dome between the pauldrons, red crest on top ---
    lay.shaded_ellipse(256, 234, 100, 102, GOLD, GOLD_LIGHT, GOLD_DEEP)
    lay.capsule((256, 194), (256, 280), 24, RED, OUTLINE, 6)          # crest base
    lay.capsule((256, 192), (256, 242), 10, RED_LIGHT, None)          # crest sheen

    # --- guardian spear: butt low-left, blade high-right over the shoulder ---
    shaft0 = (186, 468)
    neck = (414, 128)
    tip = (476, 36)
    butt = (176, 483)

    lay.dot(butt[0], butt[1], 16, GOLD_DEEP)
    lay.capsule(butt, shaft0, 20, GOLD_DEEP)
    lay.capsule(shaft0, neck, 14, GOLD, OUTLINE, 6)
    lay.line(_along(shaft0, neck, 0.08), _along(shaft0, neck, 0.5), 4, GOLD_LIGHT)

    lay.capsule(_along(shaft0, neck, 0.82), _along(shaft0, neck, 0.93), 28, GOLD_DEEP, OUTLINE, 6)
    mz = _along(shaft0, neck, 0.945)
    lay.dot(mz[0], mz[1], 6, BLACK_SUIT)

    bw = 38
    base_l = _offset_perp(neck, tip, neck, -bw)
    base_r = _offset_perp(neck, tip, neck, bw)
    mid_l = _offset_perp(neck, tip, _along(neck, tip, 0.40), -bw * 0.86)
    mid_r = _offset_perp(neck, tip, _along(neck, tip, 0.40), bw * 0.86)
    lay.polygon([base_l, mid_l, tip, mid_r, base_r], STEEL, OUTLINE, 7)
    lay.line(_along(neck, tip, 0.05), _along(neck, tip, 0.9), 6, STEEL_DARK)
    c1 = _offset_perp(neck, tip, neck, -18)
    c2 = _offset_perp(neck, tip, neck, 18)
    lay.capsule(c1, c2, 13, GOLD, OUTLINE, 6)

    # --- forearms + hands gripping the shaft ---
    lower_grip = _along(shaft0, neck, 0.24)
    upper_grip = _along(shaft0, neck, 0.55)
    lay.capsule((202, 348), lower_grip, 32, GOLD, OUTLINE, 6)
    lay.capsule((346, 302), upper_grip, 32, GOLD, OUTLINE, 6)
    lay.shaded_ellipse(lower_grip[0], lower_grip[1], 48, 48, GOLD, GOLD_LIGHT, GOLD_DEEP, OUTLINE, 6)
    lay.shaded_ellipse(upper_grip[0], upper_grip[1], 48, 48, GOLD, GOLD_LIGHT, GOLD_DEEP, OUTLINE, 6)

    return lay


def draw_allarus_custodians():
    """Allarus Terminator: the Guard silhouette blown out to terminator bulk —
    wider shoulder mass with rivets, stubby crest, and a castellan axe with a
    broad bearded blade attached flush at the haft top (up-right)."""
    lay = Layer()
    lay.shadow([64, 124, 450, 436])

    # torso block (terminators are all shoulders)
    lay.capsule((256, 262), (256, 336), 176, GOLD, OUTLINE, 7)
    lay.soft_capsule((256, 312), (256, 356), 104, GOLD_DEEP, alpha=100, blur=9)

    # shoulders: unified capsule, wider and thicker than the Guard's
    sp1, sp2, sw = (152, 242), (360, 242), 192

    def clip(d, q1=S(sp1), q2=S(sp2), w=S(sw)):
        d.line([tuple(q1), tuple(q2)], fill=255, width=int(w))
        for p in (q1, q2):
            d.ellipse([p[0] - w / 2, p[1] - w / 2, p[0] + w / 2, p[1] + w / 2], fill=255)

    lay.capsule(sp1, sp2, sw, GOLD, OUTLINE, 7)
    lay.soft_capsule((146, 192), (366, 192), 64, GOLD_LIGHT, alpha=120, blur=12, clip_painter=clip)
    lay.soft_capsule((150, 306), (362, 306), 58, GOLD_DEEP, alpha=115, blur=12, clip_painter=clip)
    # pauldron rivets (terminator armour tell)
    for ang in (150, 180, 210):
        a = math.radians(ang)
        lay.dot(152 + math.cos(a) * 74, 242 + math.sin(a) * 74, 8, GOLD_DARKEST)
        lay.dot(360 - math.cos(a) * 74, 242 + math.sin(a) * 74, 8, GOLD_DARKEST)
    # trim seams
    lay.capsule((206, 172), (200, 316), 5, GOLD_DARKEST, None)
    lay.capsule((306, 172), (312, 316), 5, GOLD_DARKEST, None)

    # helmet: lower dome, stubbier crest
    lay.shaded_ellipse(256, 230, 94, 94, GOLD, GOLD_LIGHT, GOLD_DEEP)
    lay.capsule((256, 200), (256, 264), 22, RED, OUTLINE, 6)
    lay.capsule((256, 198), (256, 234), 9, RED_LIGHT, None)

    # castellan axe: haft low-left -> bearded axe head up-right
    shaft0 = (170, 474)
    top = (404, 128)
    lay.dot(162, 486, 15, GOLD_DEEP)
    lay.capsule((162, 486), shaft0, 20, GOLD_DEEP)
    lay.capsule(shaft0, top, 15, GOLD, OUTLINE, 6)
    lay.line(_along(shaft0, top, 0.08), _along(shaft0, top, 0.5), 4, GOLD_LIGHT)

    d_ = (top[0] - shaft0[0], top[1] - shaft0[1])
    dl = math.hypot(*d_)
    u = (d_[0] / dl, d_[1] / dl)
    n = (-u[1], u[0])   # points right of the haft direction (down-right here)

    # broad bearded blade: root runs ALONG the haft (flush), edge bows outward
    r0 = _along(shaft0, top, 0.80)                      # root low end (on haft)
    r1 = _along(shaft0, top, 1.00)                      # root high end (haft top)
    e_hi = (r1[0] + n[0] * 92 + u[0] * 26, r1[1] + n[1] * 92 + u[1] * 26)
    e_lo = (r0[0] + n[0] * 96 - u[0] * 34, r0[1] + n[1] * 96 - u[1] * 34)
    e_mid = (_along(r0, r1, 0.55)[0] + n[0] * 112, _along(r0, r1, 0.55)[1] + n[1] * 112)
    lay.polygon([r0, r1, e_hi, e_mid, e_lo], STEEL, OUTLINE, 7)
    lay.line(_along(r0, r1, 0.5), (e_mid[0] - n[0] * 14, e_mid[1] - n[1] * 14), 6, STEEL_DARK)
    # top spike continuing the haft above the blade
    lay.capsule(top, (top[0] + u[0] * 44, top[1] + u[1] * 44), 16, GOLD_DEEP, OUTLINE, 6)

    # arms/fists
    lower_grip = _along(shaft0, top, 0.24)
    upper_grip = _along(shaft0, top, 0.56)
    lay.capsule((192, 356), lower_grip, 38, GOLD, OUTLINE, 6)
    lay.capsule((356, 308), upper_grip, 38, GOLD, OUTLINE, 6)
    lay.shaded_ellipse(lower_grip[0], lower_grip[1], 56, 56, GOLD, GOLD_LIGHT, GOLD_DEEP, OUTLINE, 6)
    lay.shaded_ellipse(upper_grip[0], upper_grip[1], 56, 56, GOLD, GOLD_LIGHT, GOLD_DEEP, OUTLINE, 6)

    return lay


def draw_blade_champion():
    """Blade Champion: red cloak billowing around gold shoulders, tall crest,
    and a long two-handed blade held diagonally (blade up-LEFT, mirroring the
    spear units) for instant tell-apart."""
    lay = Layer()
    lay.shadow([84, 136, 434, 440])

    # billowing cloak behind the figure: wider than the shoulders with
    # wind-blown points so red shows all around the gold at token scale
    lay.polygon([(128, 202), (256, 168), (384, 202), (438, 340), (356, 470),
                 (256, 494), (156, 470), (74, 340)], RED, OUTLINE, 7)
    lay.polygon([(184, 248), (256, 222), (328, 248), (360, 348), (310, 436),
                 (256, 454), (202, 436), (152, 348)], RED_DARK, None)
    lay.soft_capsule((150, 230), (362, 230), 40, RED_LIGHT, alpha=120, blur=10)

    # torso + shoulders (slightly narrower than a Guard)
    lay.capsule((256, 262), (256, 330), 140, GOLD, OUTLINE, 7)
    sp1, sp2, sw = (172, 244), (340, 244), 158

    def clip(d, q1=S(sp1), q2=S(sp2), w=S(sw)):
        d.line([tuple(q1), tuple(q2)], fill=255, width=int(w))
        for p in (q1, q2):
            d.ellipse([p[0] - w / 2, p[1] - w / 2, p[0] + w / 2, p[1] + w / 2], fill=255)

    lay.capsule(sp1, sp2, sw, GOLD, OUTLINE, 7)
    lay.soft_capsule((168, 202), (344, 202), 54, GOLD_LIGHT, alpha=125, blur=11, clip_painter=clip)
    lay.soft_capsule((170, 294), (342, 294), 48, GOLD_DEEP, alpha=115, blur=11, clip_painter=clip)
    lay.capsule((214, 186), (208, 298), 5, GOLD_DARKEST, None)
    lay.capsule((298, 186), (304, 298), 5, GOLD_DARKEST, None)

    # helm with TALL sweeping crest (front overhang)
    lay.shaded_ellipse(256, 232, 96, 98, GOLD, GOLD_LIGHT, GOLD_DEEP)
    lay.capsule((256, 172), (256, 284), 26, RED, OUTLINE, 6)
    lay.capsule((256, 170), (256, 236), 11, RED_LIGHT, None)

    # long blade: hilt low-RIGHT, tip up-LEFT (mirrors the spear diagonal)
    pommel = (352, 470)
    guard_c = (306, 402)
    tip = (66, 62)
    lay.dot(pommel[0], pommel[1], 14, GOLD_DEEP)
    lay.capsule(pommel, guard_c, 15, GOLD, OUTLINE, 6)  # grip
    g1 = _offset_perp(guard_c, tip, guard_c, -34)
    g2 = _offset_perp(guard_c, tip, guard_c, 34)
    lay.capsule(g1, g2, 16, GOLD, OUTLINE, 6)           # crossguard
    # tapering blade
    b0l = _offset_perp(guard_c, tip, guard_c, -13)
    b0r = _offset_perp(guard_c, tip, guard_c, 13)
    lay.polygon([b0l, tip, b0r], STEEL, OUTLINE, 7)
    lay.line(_along(guard_c, tip, 0.04), _along(guard_c, tip, 0.9), 5, STEEL_DARK)

    # arms: both hands on the grip
    h1 = _along(pommel, guard_c, 0.35)
    h2 = _along(pommel, guard_c, 0.8)
    lay.capsule((208, 330), h1, 30, GOLD, OUTLINE, 6)
    lay.capsule((332, 312), h2, 30, GOLD, OUTLINE, 6)
    lay.shaded_ellipse(h1[0], h1[1], 46, 46, GOLD, GOLD_LIGHT, GOLD_DEEP, OUTLINE, 6)
    lay.shaded_ellipse(h2[0], h2[1], 46, 46, GOLD, GOLD_LIGHT, GOLD_DEEP, OUTLINE, 6)

    return lay


def draw_prosecutors():
    """Prosecutor (Sisters of Silence): slim black armour with gold trim, red
    topknot streaming back, boltgun held across the chest."""
    lay = Layer()
    lay.shadow([120, 150, 396, 420])

    # red back-cloak tail
    lay.polygon([(226, 320), (286, 320), (296, 412), (256, 440), (216, 412)],
                RED, OUTLINE, 6)
    lay.polygon([(238, 344), (274, 344), (280, 404), (256, 420), (232, 404)],
                RED_DARK, None)

    dims = _humanoid(lay, 256, 252, 0.82, SIS_BLACK, SIS_BLACK_LIGHT, SIS_BLACK_DARK,
                     SIS_BLACK, SIS_BLACK_LIGHT, SIS_BLACK_DARK, OUTLINE,
                     seam=SIS_BLACK_DARK, shoulder_w=0.9)
    # gold pauldron caps: bold trim arcs + inner line (the faction tell)
    lay.arc([112, 182, 228, 304], 95, 265, GOLD, 12)
    lay.arc([284, 182, 400, 304], 275, 85, GOLD, 12)
    lay.arc([130, 200, 210, 286], 95, 265, GOLD_DEEP, 5)
    lay.arc([302, 200, 382, 286], 275, 85, GOLD_DEEP, 5)
    # gold gorget plate below the head
    lay.capsule((256, 298), (256, 326), 50, GOLD, None, 0, alpha=200)

    # red topknot: bold knot + streaming tail behind (south)
    lay.dot(256, 214, 16, RED, OUTLINE, 5)
    lay.capsule((256, 224), (270, 306), 17, RED, OUTLINE, 5)
    lay.capsule((258, 228), (267, 284), 7, RED_LIGHT, None)

    # boltgun across the chest: stock low-left, muzzle up-right
    stock = (172, 360)
    muzzle = (366, 194)
    lay.capsule(stock, _along(stock, muzzle, 0.16), 30, ORK_BLACK, OUTLINE, 6)   # stock
    lay.capsule(_along(stock, muzzle, 0.12), _along(stock, muzzle, 0.86), 24, STEEL_DARK, OUTLINE, 6)
    lay.capsule(_along(stock, muzzle, 0.84), muzzle, 14, STEEL, OUTLINE, 6)     # barrel
    lay.dot(muzzle[0], muzzle[1], 7, BLACK_SUIT)
    # magazine perpendicular below mid-gun
    mag_c = _along(stock, muzzle, 0.5)
    mg = _offset_perp(stock, muzzle, mag_c, 26)
    lay.capsule(mag_c, mg, 20, ORK_BLACK, OUTLINE, 5)
    # hands
    h1 = _along(stock, muzzle, 0.32)
    h2 = _along(stock, muzzle, 0.68)
    lay.shaded_ellipse(h1[0], h1[1], 40, 40, SIS_BLACK, SIS_BLACK_LIGHT, SIS_BLACK_DARK, OUTLINE, 5)
    lay.shaded_ellipse(h2[0], h2[1], 40, 40, SIS_BLACK, SIS_BLACK_LIGHT, SIS_BLACK_DARK, OUTLINE, 5)

    return lay


# ============================================================================
# ORKS
# ============================================================================

def draw_gretchin():
    """Gretchin: scrawny grot — big head with huge pointy ears, ragged shirt,
    little blasta pistol. Ears are the read at 39px."""
    lay = Layer(BASE_SIZE, BASE_SIZE)
    lay.shadow([120, 140, 400, 430], alpha=60)

    # scrawny shoulders/body in ragged brown
    lay.capsule((256, 300), (256, 372), 110, LEATHER, ORK_OUTLINE, 7)
    lay.capsule((196, 286), (316, 286), 104, LEATHER, ORK_OUTLINE, 7)
    lay.soft_capsule((196, 260), (316, 260), 40, LEATHER_LIGHT, alpha=110, blur=9)

    # skinny arms: one with blasta, one with pointy stikka
    lay.capsule((180, 286), (128, 226), 26, SKIN, ORK_OUTLINE, 6)   # left arm up-left
    lay.capsule((332, 286), (376, 238), 26, SKIN, ORK_OUTLINE, 6)   # right arm up-right
    # blasta pistol in right hand
    lay.dot(382, 232, 17, SKIN, ORK_OUTLINE, 5)
    lay.capsule((382, 230), (408, 164), 22, METAL_DARK, ORK_OUTLINE, 6)
    lay.dot(410, 158, 7, ORK_BLACK)
    # rusty knife in left hand
    lay.dot(122, 220, 15, SKIN, ORK_OUTLINE, 5)
    lay.polygon([(112, 208), (84, 148), (132, 196)], METAL, ORK_OUTLINE, 5)

    # BIG grot head with huge ears
    # ears first (behind head): big pointy triangles L/R
    lay.polygon([(176, 218), (66, 168), (168, 264)], SKIN, ORK_OUTLINE, 7)
    lay.polygon([(336, 218), (446, 168), (344, 264)], SKIN, ORK_OUTLINE, 7)
    lay.polygon([(160, 222), (100, 190), (158, 250)], SKIN_DARK, None)
    lay.polygon([(352, 222), (412, 190), (354, 250)], SKIN_DARK, None)
    # head dome
    lay.shaded_ellipse(256, 226, 150, 140, SKIN, SKIN_LIGHT, SKIN_DARK, ORK_OUTLINE, 7)
    # long pointy snout poking forward (up)
    lay.polygon([(226, 186), (256, 128), (286, 186)], SKIN, ORK_OUTLINE, 6)
    lay.polygon([(240, 180), (256, 148), (272, 180)], SKIN_LIGHT, None)

    return lay


def draw_stormboyz():
    """Stormboy: ork with a big red rokkit pack — the rocket nozzle + flames
    trail south behind him; choppa out to one side."""
    lay = Layer()
    lay.shadow([96, 130, 420, 440])

    # exhaust flames at the back (south) first — big and hot
    lay.polygon([(206, 390), (232, 448), (256, 506), (280, 448), (306, 390)],
                ORK_YELLOW, ORK_OUTLINE, 6)
    lay.polygon([(230, 392), (256, 470), (282, 392)], ORK_RED_LIGHT, None)

    # rokkit pack: fat red cylinder along the spine with fins
    lay.polygon([(196, 348), (160, 420), (216, 400)], ORK_RED_DARK, ORK_OUTLINE, 6)  # left fin
    lay.polygon([(316, 348), (352, 420), (296, 400)], ORK_RED_DARK, ORK_OUTLINE, 6)  # right fin
    lay.capsule((256, 260), (256, 396), 116, ORK_RED, ORK_OUTLINE, 7)
    lay.soft_capsule((236, 260), (236, 390), 26, ORK_RED_LIGHT, alpha=140, blur=8)
    lay.capsule((256, 388), (256, 396), 78, METAL_DARK, ORK_OUTLINE, 6)  # nozzle ring
    # rivet band
    lay.capsule((216, 322), (296, 322), 8, ORK_RED_DARK, None)
    for rx in (222, 256, 290):
        lay.dot(rx, 322, 6, ORK_BLACK)

    # ork body peeking around the pack: shoulders + arms + head
    lay.capsule((176, 250), (336, 250), 128, SKIN, ORK_OUTLINE, 7)
    lay.soft_capsule((176, 216), (336, 216), 42, SKIN_LIGHT, alpha=120, blur=9)
    # left arm holding choppa out
    lay.capsule((160, 262), (98, 330), 34, SKIN, ORK_OUTLINE, 6)
    lay.dot(92, 338, 18, SKIN, ORK_OUTLINE, 5)
    lay.capsule((88, 342), (60, 452), 16, LEATHER, ORK_OUTLINE, 5)     # handle
    lay.polygon([(46, 322), (98, 322), (98, 268), (46, 296)], METAL, ORK_OUTLINE, 6)  # choppa blade... points up
    # right arm gripping pack strap
    lay.capsule((350, 262), (388, 320), 34, SKIN, ORK_OUTLINE, 6)
    lay.dot(392, 328, 18, SKIN, ORK_OUTLINE, 5)

    # head: green dome with iron jaw, slightly forward
    lay.shaded_ellipse(256, 208, 112, 106, SKIN, SKIN_LIGHT, SKIN_DARK, ORK_OUTLINE, 7)
    lay.polygon([(216, 174), (256, 148), (296, 174), (286, 196), (226, 196)],
                METAL_DARK, ORK_OUTLINE, 6)  # iron 'elmet brow
    lay.dot(238, 190, 7, ORK_RED_LIGHT)  # eyes glow
    lay.dot(274, 190, 7, ORK_RED_LIGHT)

    return lay


def draw_mek():
    """Mek: ork tinkerer — giant yellow-headed spanner over one shoulder,
    kustom slugga with coils in the other hand, exhaust stacks on his pack."""
    lay = Layer()
    lay.shadow([96, 130, 420, 436])

    # backpack exhaust stacks poking above shoulders
    lay.capsule((196, 176), (196, 234), 34, METAL_DARK, ORK_OUTLINE, 6)
    lay.capsule((316, 176), (316, 234), 34, METAL_DARK, ORK_OUTLINE, 6)
    lay.dot(196, 172, 12, ORK_BLACK)
    lay.dot(316, 172, 12, ORK_BLACK)

    # body: ork shoulders + leather apron torso
    lay.capsule((256, 300), (256, 368), 132, LEATHER, ORK_OUTLINE, 7)
    lay.capsule((178, 262), (334, 262), 138, SKIN, ORK_OUTLINE, 7)
    lay.soft_capsule((178, 226), (334, 226), 46, SKIN_LIGHT, alpha=120, blur=10)

    # giant spanner: shaft from low-left hand up over right shoulder
    sh0 = (150, 420)
    sh1 = (392, 150)
    lay.capsule(sh0, sh1, 18, METAL, ORK_OUTLINE, 6)
    # yellow open-jaw spanner head
    u = ((sh1[0] - sh0[0]) / math.hypot(sh1[0] - sh0[0], sh1[1] - sh0[1]),
         (sh1[1] - sh0[1]) / math.hypot(sh1[0] - sh0[0], sh1[1] - sh0[1]))
    n = (-u[1], u[0])
    jaw_c = (sh1[0] + u[0] * 24, sh1[1] + u[1] * 24)
    lay.polygon([
        (jaw_c[0] - n[0] * 44, jaw_c[1] - n[1] * 44),
        (jaw_c[0] - n[0] * 44 + u[0] * 52, jaw_c[1] - n[1] * 44 + u[1] * 52),
        (jaw_c[0] - n[0] * 14 + u[0] * 52, jaw_c[1] - n[1] * 14 + u[1] * 52),
        (jaw_c[0] - n[0] * 14 + u[0] * 20, jaw_c[1] - n[1] * 14 + u[1] * 20),
        (jaw_c[0] + n[0] * 14 + u[0] * 20, jaw_c[1] + n[1] * 14 + u[1] * 20),
        (jaw_c[0] + n[0] * 14 + u[0] * 52, jaw_c[1] + n[1] * 14 + u[1] * 52),
        (jaw_c[0] + n[0] * 44 + u[0] * 52, jaw_c[1] + n[1] * 44 + u[1] * 52),
        (jaw_c[0] + n[0] * 44, jaw_c[1] + n[1] * 44),
    ], ORK_YELLOW, ORK_OUTLINE, 6)
    # left hand on spanner shaft
    hg = _along(sh0, sh1, 0.16)
    lay.capsule((170, 320), hg, 30, SKIN, ORK_OUTLINE, 6)
    lay.dot(hg[0], hg[1], 20, SKIN, ORK_OUTLINE, 5)

    # kustom slugga right hand: boxy gun + coil dots
    lay.capsule((342, 274), (392, 320), 30, SKIN, ORK_OUTLINE, 6)
    lay.dot(396, 326, 18, SKIN, ORK_OUTLINE, 5)
    lay.polygon(rect_pts(408, 268, 44, 92, 12), METAL_DARK, ORK_OUTLINE, 6)
    lay.dot(414, 236, 9, ORK_YELLOW)
    lay.dot(408, 262, 9, ORK_YELLOW)
    lay.dot(402, 288, 9, ORK_YELLOW)
    lay.dot(420, 212, 8, ORK_BLACK)  # muzzle

    # head with mek goggles
    lay.shaded_ellipse(256, 218, 110, 104, SKIN, SKIN_LIGHT, SKIN_DARK, ORK_OUTLINE, 7)
    lay.capsule((220, 196), (292, 196), 22, LEATHER, ORK_OUTLINE, 5)  # goggle strap
    lay.dot(238, 196, 13, ORK_RED_LIGHT, ORK_OUTLINE, 5)              # lenses
    lay.dot(274, 196, 13, ORK_RED_LIGHT, ORK_OUTLINE, 5)

    return lay


def draw_warbikers():
    """Warbike from above on the tall 42x75mm oval: front wheel + twin
    dakkaguns at the nose, red tank, rider, fat rear wheel + exhausts."""
    lay = Layer(287, BASE_SIZE)
    cx = 143.5
    lay.shadow([40, 40, 247, 480], alpha=65)

    # rear wheel: fat dark capsule
    lay.capsule((cx, 380), (cx, 458), 88, TIRE, ORK_OUTLINE, 7)
    lay.capsule((cx, 384), (cx, 450), 44, TIRE_LIGHT, None)
    # front wheel: narrower
    lay.capsule((cx, 46), (cx, 128), 54, TIRE, ORK_OUTLINE, 7)
    lay.capsule((cx, 52), (cx, 120), 22, TIRE_LIGHT, None)

    # exhaust pipes flaring out the back
    lay.capsule((cx - 30, 350), (cx - 66, 470), 24, METAL, ORK_OUTLINE, 6)
    lay.capsule((cx + 30, 350), (cx + 66, 470), 24, METAL, ORK_OUTLINE, 6)
    lay.dot(cx - 68, 474, 9, ORK_BLACK)
    lay.dot(cx + 68, 474, 9, ORK_BLACK)

    # main body: red tank/fairing wedge
    lay.polygon([(cx - 58, 170), (cx + 58, 170), (cx + 74, 300), (cx + 52, 396),
                 (cx - 52, 396), (cx - 74, 300)], ORK_RED, ORK_OUTLINE, 7)
    lay.soft_capsule((cx - 30, 200), (cx + 30, 200), 40, ORK_RED_LIGHT, alpha=130, blur=9)
    lay.polygon([(cx - 20, 210), (cx + 20, 210), (cx + 30, 290), (cx - 30, 290)],
                METAL_DARK, ORK_OUTLINE, 5)  # engine block
    # yellow flame decal on nose
    lay.polygon([(cx - 40, 176), (cx - 18, 214), (cx - 30, 176)], ORK_YELLOW, None)
    lay.polygon([(cx + 40, 176), (cx + 18, 214), (cx + 30, 176)], ORK_YELLOW, None)

    # twin dakkaguns flanking the front wheel
    lay.capsule((cx - 44, 176), (cx - 44, 92), 22, METAL_DARK, ORK_OUTLINE, 6)
    lay.capsule((cx + 44, 176), (cx + 44, 92), 22, METAL_DARK, ORK_OUTLINE, 6)
    lay.dot(cx - 44, 86, 8, ORK_BLACK)
    lay.dot(cx + 44, 86, 8, ORK_BLACK)
    # handlebars
    lay.capsule((cx - 62, 190), (cx + 62, 190), 14, METAL, ORK_OUTLINE, 5)

    # rider: green head + shoulders over the saddle
    lay.capsule((cx - 46, 306), (cx + 46, 306), 74, SKIN, ORK_OUTLINE, 6)
    lay.capsule((cx - 40, 300), (cx - 66, 216), 24, SKIN, ORK_OUTLINE, 5)  # arms to bars
    lay.capsule((cx + 40, 300), (cx + 66, 216), 24, SKIN, ORK_OUTLINE, 5)
    lay.shaded_ellipse(cx, 296, 62, 60, SKIN, SKIN_LIGHT, SKIN_DARK, ORK_OUTLINE, 6)
    lay.capsule((cx - 14, 274), (cx + 14, 274), 12, METAL_DARK, None)  # goggles

    return lay


def draw_deffkoptas():
    """Deffkopta from above: the rotor X dominates, small red fuselage with
    twin big shootas at the nose, ork pilot, tail boom to a small tail rotor."""
    lay = Layer(287, BASE_SIZE)
    cx = 143.5
    lay.shadow([36, 60, 251, 470], alpha=60)

    # tail boom + tail rotor (south)
    lay.capsule((cx, 300), (cx, 448), 26, METAL_DARK, ORK_OUTLINE, 6)
    lay.capsule((cx - 44, 452), (cx + 44, 452), 16, METAL, ORK_OUTLINE, 5)  # tail rotor
    lay.dot(cx, 452, 10, ORK_BLACK)
    lay.polygon([(cx - 10, 400), (cx - 54, 430), (cx - 10, 430)], ORK_RED, ORK_OUTLINE, 5)  # tail fin

    # fuselage: stubby red pod
    lay.polygon([(cx - 44, 130), (cx + 44, 130), (cx + 56, 240), (cx + 40, 320),
                 (cx - 40, 320), (cx - 56, 240)], ORK_RED, ORK_OUTLINE, 7)
    lay.soft_capsule((cx - 20, 160), (cx + 20, 160), 36, ORK_RED_LIGHT, alpha=130, blur=8)
    # twin big shootas at the nose
    lay.capsule((cx - 34, 136), (cx - 34, 54), 20, METAL_DARK, ORK_OUTLINE, 6)
    lay.capsule((cx + 34, 136), (cx + 34, 54), 20, METAL_DARK, ORK_OUTLINE, 6)
    lay.dot(cx - 34, 48, 8, ORK_BLACK)
    lay.dot(cx + 34, 48, 8, ORK_BLACK)

    # pilot behind the hub
    lay.shaded_ellipse(cx, 292, 58, 56, SKIN, SKIN_LIGHT, SKIN_DARK, ORK_OUTLINE, 6)

    # ROTOR: four long blades + hub (drawn last, spins above everything)
    for ang in (18, 108):
        a = math.radians(ang)
        dx, dy = math.cos(a), math.sin(a)
        for s in (1, -1):
            tipx, tipy = cx + s * dx * 134, 218 + s * dy * 134
            lay.capsule((cx, 218), (tipx, tipy), 26, ORK_BLACK, ORK_OUTLINE, 5)
            lay.capsule((cx + s * dx * 20, 218 + s * dy * 20),
                        (tipx - s * dx * 8, tipy - s * dy * 8), 10, METAL_DARK, None)
    lay.dot(cx, 218, 26, METAL, ORK_OUTLINE, 6)
    lay.dot(cx, 218, 10, ORK_BLACK)

    return lay


def draw_deffkilla_wartrike():
    """Deffkilla Wartrike on the 95x150mm oval: chunky front wheel, long red
    dragster hull with flame decals + snazzguns, small boss driver at the
    back between two BIG exposed rear wheels."""
    lay = Layer(324, BASE_SIZE)
    cx = 162
    lay.shadow([30, 36, 294, 486], alpha=65)

    # rear wheels: fat, fully visible, poking wide of the hull
    for wx in (52, 272):
        lay.capsule((wx, 352), (wx, 472), 92, TIRE, ORK_OUTLINE, 7)
        lay.capsule((wx, 360), (wx, 464), 46, TIRE_LIGHT, None)
        lay.capsule((wx, 380), (wx, 444), 18, TIRE, None)
    # rear axle beam behind the hull
    lay.capsule((52, 412), (272, 412), 34, METAL_DARK, ORK_OUTLINE, 6)

    # front wheel: chunky, with a visible metal hub fork
    lay.capsule((cx, 34), (cx, 148), 66, TIRE, ORK_OUTLINE, 7)
    lay.capsule((cx, 44), (cx, 138), 32, TIRE_LIGHT, None)
    lay.polygon(rect_pts(cx, 158, 54, 40), METAL, ORK_OUTLINE, 5)  # fork clamp

    # hull: long red dragster wedge, nose at the fork
    lay.polygon([(cx - 34, 168), (cx + 34, 168), (cx + 78, 280), (cx + 86, 420),
                 (cx - 86, 420), (cx - 78, 280)], ORK_RED, ORK_OUTLINE, 8)
    lay.soft_capsule((cx, 200), (cx, 330), 60, ORK_RED_LIGHT, alpha=115, blur=12)
    # yellow flame decals licking back from the nose
    lay.polygon([(cx - 26, 172), (cx - 14, 236), (cx - 2, 176)], ORK_YELLOW, None)
    lay.polygon([(cx + 26, 172), (cx + 14, 236), (cx + 2, 176)], ORK_YELLOW, None)
    lay.polygon([(cx - 22, 178), (cx - 15, 218), (cx - 8, 182)], ORK_RED_LIGHT, None)
    lay.polygon([(cx + 22, 178), (cx + 15, 218), (cx + 8, 182)], ORK_RED_LIGHT, None)
    # engine block mid-hull with piston dots
    lay.polygon(rect_pts(cx, 292, 84, 74), METAL_DARK, ORK_OUTLINE, 6)
    for px_ in (cx - 24, cx, cx + 24):
        lay.dot(px_, 292, 9, METAL_LIGHT)

    # snazzguns: twin forward gun pods flanking the nose
    for s in (-1, 1):
        gx = cx + s * 62
        lay.capsule((gx, 268), (gx, 180), 26, METAL, ORK_OUTLINE, 6)
        lay.dot(gx, 172, 9, ORK_BLACK)

    # exhaust stacks angled out behind the driver
    lay.capsule((cx - 62, 372), (cx - 92, 300), 26, METAL_DARK, ORK_OUTLINE, 6)
    lay.capsule((cx + 62, 372), (cx + 92, 300), 26, METAL_DARK, ORK_OUTLINE, 6)
    lay.dot(cx - 96, 292, 10, ORK_BLACK)
    lay.dot(cx + 96, 292, 10, ORK_BLACK)

    # deffkilla boss: compact head + shoulders at the wheel (rear cockpit)
    lay.capsule((cx - 40, 372), (cx + 40, 372), 62, SKIN, ORK_OUTLINE, 6)
    lay.capsule((cx - 34, 366), (cx - 18, 322), 20, SKIN, ORK_OUTLINE, 5)
    lay.capsule((cx + 34, 366), (cx + 18, 322), 20, SKIN, ORK_OUTLINE, 5)
    lay.capsule((cx - 26, 322), (cx + 26, 322), 12, METAL, ORK_OUTLINE, 4)  # wheel bar
    lay.shaded_ellipse(cx, 366, 54, 52, SKIN, SKIN_LIGHT, SKIN_DARK, ORK_OUTLINE, 5)
    lay.capsule((cx - 11, 350), (cx + 11, 350), 10, METAL_DARK, None)  # iron gob

    return lay


def draw_wazdakka_gutsmek():
    """Wazdakka Gutsmek: the bike boss crammed onto a 32mm round base — a red
    bike with a big visible tank, twin light-metal dakkacannons wide of the
    front wheel, and a red-armoured boss with horns at the back."""
    lay = Layer()
    cx = 256
    lay.shadow([80, 60, 432, 470], alpha=65)

    # rear wheel
    lay.capsule((cx, 380), (cx, 466), 100, TIRE, ORK_OUTLINE, 7)
    lay.capsule((cx, 388), (cx, 458), 50, TIRE_LIGHT, None)
    # front wheel
    lay.capsule((cx, 40), (cx, 138), 62, TIRE, ORK_OUTLINE, 7)
    lay.capsule((cx, 48), (cx, 130), 28, TIRE_LIGHT, None)

    # exhausts out the back
    lay.capsule((cx - 46, 380), (cx - 100, 474), 30, METAL, ORK_OUTLINE, 6)
    lay.capsule((cx + 46, 380), (cx + 100, 474), 30, METAL, ORK_OUTLINE, 6)
    lay.dot(cx - 104, 480, 11, ORK_BLACK)
    lay.dot(cx + 104, 480, 11, ORK_BLACK)

    # twin dakkacannons: light metal, spaced WIDE of the front wheel
    for s in (-1, 1):
        gx = cx + s * 84
        lay.capsule((gx, 210), (gx, 76), 34, METAL, ORK_OUTLINE, 6)
        lay.capsule((gx, 204), (gx, 110), 12, METAL_LIGHT, None)
        lay.dot(gx, 66, 12, ORK_BLACK)
        lay.capsule((cx + s * 40, 226), (gx, 200), 22, METAL_DARK, ORK_OUTLINE, 5)  # mount

    # bike hull: big red tank filling the mid-canvas, clearly visible
    lay.polygon([(cx - 62, 150), (cx + 62, 150), (cx + 88, 262), (cx + 74, 356),
                 (cx - 74, 356), (cx - 88, 262)], ORK_RED, ORK_OUTLINE, 8)
    lay.soft_capsule((cx - 26, 186), (cx + 26, 186), 56, ORK_RED_LIGHT, alpha=145, blur=10)
    # yellow checks band across the tank (speed freek tell)
    for i, chx in enumerate(range(cx - 60, cx + 60, 24)):
        lay.polygon(rect_pts(chx + 12, 246, 24, 26),
                    ORK_YELLOW if i % 2 == 0 else ORK_BLACK, None)
    lay.capsule((cx - 78, 232), (cx + 78, 232), 4, ORK_OUTLINE, None)
    lay.capsule((cx - 74, 260), (cx + 74, 260), 4, ORK_OUTLINE, None)

    # Wazdakka: compact boss — red mega-armour shoulders, green head, horns
    lay.capsule((cx - 56, 330), (cx + 56, 330), 84, ORK_RED_DARK, ORK_OUTLINE, 7)
    lay.soft_capsule((cx - 50, 310), (cx + 50, 310), 30, ORK_RED, alpha=150, blur=7)
    lay.capsule((cx - 48, 322), (cx - 66, 250), 24, ORK_RED_DARK, ORK_OUTLINE, 5)
    lay.capsule((cx + 48, 322), (cx + 66, 250), 24, ORK_RED_DARK, ORK_OUTLINE, 5)
    lay.shaded_ellipse(cx, 314, 74, 70, SKIN, SKIN_LIGHT, SKIN_DARK, ORK_OUTLINE, 6)
    lay.capsule((cx - 17, 292), (cx + 17, 292), 14, METAL_DARK, None)  # iron gob
    # boss horns off the shoulders
    lay.polygon([(cx - 62, 306), (cx - 88, 274), (cx - 52, 290)], TEEF, ORK_OUTLINE, 4)
    lay.polygon([(cx + 62, 306), (cx + 88, 274), (cx + 52, 290)], TEEF, ORK_OUTLINE, 4)

    return lay


def draw_stompa():
    """Stompa from above (180mm base): colossal rusty-red effigy hull with an
    ork face at the front, hazard chevrons, smoke stacks, a mega-choppa arm
    (left) and a supa-gatler arm (right)."""
    lay = Layer()
    cx, cy = 256, 268
    lay.shadow([40, 60, 472, 480], alpha=80, blur=12)

    # --- arms first (under the hull rim) ---
    # LEFT: mega-choppa — armored arm + giant toothed blade up-left
    lay.capsule((120, 300), (66, 202), 64, METAL_DARK, ORK_OUTLINE, 8)
    blade = [(20, 196), (54, 60), (98, 34), (86, 196), (56, 226)]
    lay.polygon(blade, METAL, ORK_OUTLINE, 8)
    lay.line((54, 196), (66, 70), 7, METAL_DARK)
    for t in (0.2, 0.45, 0.7):  # saw teeth on the leading edge
        p = _along((20, 196), (54, 60), t)
        lay.polygon([(p[0], p[1]), (p[0] - 22, p[1] - 4), (p[0] - 2, p[1] - 22)],
                    METAL, ORK_OUTLINE, 5)
    # RIGHT: supa-gatler — arm + rotary barrel cluster up-right
    lay.capsule((392, 300), (446, 210), 64, METAL_DARK, ORK_OUTLINE, 8)
    lay.capsule((446, 208), (446, 88), 74, METAL, ORK_OUTLINE, 8)
    for bx, by in [(424, 74), (446, 66), (468, 74)]:
        lay.dot(bx, by, 13, ORK_BLACK, ORK_OUTLINE, 5)
    lay.capsule((414, 150), (478, 150), 12, METAL_DARK, None)  # barrel band

    # --- main hull: huge round belly ---
    lay.shaded_ellipse(cx, cy, 360, 356, ORK_RED, ORK_RED_LIGHT, ORK_RED_DARK, ORK_OUTLINE, 9)
    # armour plate seams: concentric arc + radial rivet lines
    lay.arc([cx - 140, cy - 138, cx + 140, cy + 142], 0, 360, ORK_RED_DARK, 6)
    for ang in range(0, 360, 45):
        a = math.radians(ang)
        for rr in (108, 152):
            lay.dot(cx + math.cos(a) * rr, cy + math.sin(a) * rr, 6, ORK_BLACK)

    # hazard chevron band across the lower hull
    band_y = cy + 96
    for i in range(-4, 5):
        x0 = cx + i * 44
        lay.polygon([(x0 - 18, band_y + 22), (x0 + 4, band_y - 22), (x0 + 26, band_y - 22),
                     (x0 + 4, band_y + 22)], ORK_YELLOW if i % 2 == 0 else ORK_BLACK, None)
    lay.capsule((cx - 178, band_y - 22), (cx + 178, band_y - 22), 5, ORK_OUTLINE, None)
    lay.capsule((cx - 178, band_y + 22), (cx + 178, band_y + 22), 5, ORK_OUTLINE, None)

    # smoke stacks (rear-left cluster)
    for sx, sy, r in [(160, 396, 26), (204, 416, 22), (122, 372, 20)]:
        lay.dot(sx, sy, r + 6, ORK_OUTLINE)
        lay.dot(sx, sy, r, METAL_DARK)
        lay.dot(sx, sy, r * 0.55, ORK_BLACK)

    # --- the effigy face at the front (top) ---
    # jaw plate: metal trapezoid with teef
    lay.polygon([(cx - 96, 128), (cx + 96, 128), (cx + 74, 44), (cx - 74, 44)],
                METAL, ORK_OUTLINE, 8)
    for i in range(-3, 4):
        tx = cx + i * 26
        lay.polygon([(tx - 10, 128), (tx + 10, 128), (tx, 96)], TEEF, ORK_OUTLINE, 4)
    # brow + glowing eyes
    lay.polygon([(cx - 88, 160), (cx + 88, 160), (cx + 70, 122), (cx - 70, 122)],
                ORK_RED_DARK, ORK_OUTLINE, 6)
    lay.dot(cx - 40, 142, 15, ORK_RED_LIGHT, ORK_OUTLINE, 5)
    lay.dot(cx + 40, 142, 15, ORK_RED_LIGHT, ORK_OUTLINE, 5)

    # glyph plate (yellow) on the belly
    lay.polygon([(cx - 36, cy - 24), (cx + 36, cy - 24), (cx + 24, cy + 40), (cx - 24, cy + 40)],
                ORK_YELLOW, ORK_OUTLINE, 6)
    lay.dot(cx, cy + 2, 12, ORK_BLACK)  # dead simple glyph
    lay.polygon([(cx - 12, cy + 26), (cx + 12, cy + 26), (cx, cy + 38)], ORK_BLACK, None)

    # banner pole at the rear with a red flag
    lay.capsule((352, 420), (398, 486), 12, METAL, ORK_OUTLINE, 5)
    lay.polygon([(396, 470), (474, 452), (420, 500)], ORK_RED, ORK_OUTLINE, 5)

    return lay


SPRITES = {
    # filename (SpriteResolver key) -> draw function
    "custodian_guard": draw_custodian_guard,
    "allarus_custodians": draw_allarus_custodians,
    "blade_champion": draw_blade_champion,
    "prosecutors": draw_prosecutors,
    "gretchin": draw_gretchin,
    "stormboyz": draw_stormboyz,
    "mek": draw_mek,
    "warbikers": draw_warbikers,
    "deffkoptas": draw_deffkoptas,
    "deffkilla_wartrike": draw_deffkilla_wartrike,
    "wazdakka_gutsmek": draw_wazdakka_gutsmek,
    "stompa": draw_stompa,
}

# base footprint (w_mm, h_mm) per sprite, for the game-scale contact sheet
BASES = {
    "custodian_guard": (40, 40),
    "allarus_custodians": (40, 40),
    "blade_champion": (40, 40),
    "prosecutors": (32, 32),
    "gretchin": (25, 25),
    "stormboyz": (32, 32),
    "mek": (32, 32),
    "warbikers": (42, 75),
    "deffkoptas": (42, 75),
    "deffkilla_wartrike": (95, 150),
    "wazdakka_gutsmek": (32, 32),
    "stompa": (180, 180),
}

PX_PER_MM = 40.0 / 25.4  # in-game scale: 40 px/inch


def render(fn):
    lay = fn()
    return lay.img.resize((lay.w, lay.h), Image.LANCZOS)


def make_contact_sheet(rendered, path):
    """All sprites on their bases at true in-game relative scale."""
    pad = 18
    entries = []
    for name, img in rendered.items():
        bw, bh = BASES[name]
        w, h = int(bw * PX_PER_MM), int(bh * PX_PER_MM)
        entries.append((name, img, w, h))
    entries.sort(key=lambda e: -e[3])
    total_w = sum(e[2] for e in entries) + pad * (len(entries) + 1)
    total_h = max(e[3] for e in entries) + pad * 2 + 28
    sheet = Image.new("RGBA", (total_w, total_h), (40, 44, 36, 255))
    d = ImageDraw.Draw(sheet)
    x = pad
    midy = pad + max(e[3] for e in entries) // 2
    for name, img, w, h in entries:
        d.ellipse([x, midy - h // 2, x + w, midy + h // 2], fill=(70, 74, 82, 255),
                  outline=(20, 18, 12, 255), width=max(1, w // 32))
        small = img.resize((w, h), Image.LANCZOS)
        sheet.alpha_composite(small, (x, midy - h // 2))
        d.text((x, midy + h // 2 + 6), name[:20], fill=(220, 220, 210, 255))
        x += w + pad
    sheet.save(path)


def main():
    ap = argparse.ArgumentParser()
    root = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
    ap.add_argument("--out", default=os.path.join(root, "40k", "assets", "unit_sprites"))
    ap.add_argument("--preview", default=None, help="write preview contact sheet here")
    ap.add_argument("--only", default=None, help="comma-separated sprite names")
    args = ap.parse_args()

    only = set(args.only.split(",")) if args.only else None
    os.makedirs(args.out, exist_ok=True)
    rendered = {}
    for name, fn in SPRITES.items():
        if only and name not in only:
            continue
        img = render(fn)
        rendered[name] = img
        out_path = os.path.join(args.out, name + ".png")
        img.save(out_path)
        print("wrote", out_path)

    if args.preview and rendered:
        os.makedirs(args.preview, exist_ok=True)
        sheet_path = os.path.join(args.preview, "contact_sheet.png")
        make_contact_sheet(rendered, sheet_path)
        print("wrote", sheet_path)


if __name__ == "__main__":
    main()
